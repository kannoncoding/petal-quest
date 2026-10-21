import {PGlite} from '@electric-sql/pglite';
import {pgcrypto} from '@electric-sql/pglite/contrib/pgcrypto';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';

// No cloud configuration, credentials, network or installed-app data are read.
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'..');
const db=new PGlite({extensions:{pgcrypto}});
const results=[];
async function test(name,fn){try{await fn();results.push({name,status:'PASS'});console.log('PASS '+name)}catch(e){results.push({name,status:'FAIL',error:e.message,code:e.code});console.log('FAIL '+name+': '+e.message)}}
const q=(sql,params=[])=>db.query(sql,params);
const value=async(sql,params=[])=>Object.values((await q(sql,params)).rows[0])[0];
const uid=(group,n)=>`${group}0000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const A=uid(1,0),B=uid(2,0),p1=uid(1,1),p2=uid(1,2),t1=uid(1,3),pb=uid(2,1),tb=uid(2,3);
const actorA='11000000-0000-0000-0000-000000000003',actorB='22000000-0000-0000-0000-000000000003';
const defA='13000000-0000-0000-0000-000000000001',defB='23000000-0000-0000-0000-000000000001';
async function user(id,anonymous,fn,role='authenticated'){
 await db.exec('begin');
 try{await db.exec(`set local role ${role}`);await q("select set_config('request.jwt.claims',$1,true)",[JSON.stringify(id?{sub:id,role,is_anonymous:anonymous}:{role})]);const r=await fn();await db.exec('commit');return r}
 catch(e){await db.exec('rollback');throw e}
}
const rpc=(name,args)=>value(`select public.${name}(${args.map((_,i)=>'$'+(i+1)).join(',')})`,args);
async function denied(fn,code='42501'){await assert.rejects(fn,e=>e.code===code)}
async function addUser(id,anonymous=true){await q('insert into auth.users(id,is_anonymous) values($1,$2)',[id,anonymous])}
let occurrence,submission,decision;
try{
 await db.exec(`create role anon nologin; create role authenticated nologin; create schema auth;
 create table auth.users(id uuid primary key,aud text,role text,is_anonymous boolean not null default false);
 create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
 create function auth.uid() returns uuid language sql stable as $$ select (auth.jwt()->>'sub')::uuid $$;
 grant usage on schema public,auth to anon,authenticated;`);
 await test('all migrations compile and apply atomically',async()=>{await db.exec(await fs.readFile(path.join(root,'deploy-development.sql'),'utf8'))});
 if(results.at(-1).status!=='PASS')throw Error('Migration failed; later tests not run');
 await db.exec(await fs.readFile(path.join(root,'review/fixture.sql'),'utf8'));
 await test('all 16 application/private tables enable RLS',async()=>{assert.equal(await value("select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','petal_private') and c.relkind='r' and not c.relrowsecurity"),0)});
 await test('unauthenticated role cannot read families',()=>user(null,false,()=>denied(()=>q('select * from public.families')),'anon'));
 const unpaired=uid(3,1);await addUser(unpaired);
 await test('unpaired authenticated identity reads zero families',()=>user(unpaired,true,async()=>assert.equal((await q('select * from public.families')).rows.length,0)));
 await test('teen sees own family and no other family',()=>user(t1,true,async()=>{assert.deepEqual((await q('select id from public.families')).rows.map(x=>x.id),[A]);assert.equal((await q('select * from public.families where id=$1',[B])).rows.length,0)}));
 await test('parent cannot create occurrence in another family',()=>denied(()=>user(p1,false,()=>rpc('create_occurrence',[defB,actorB]))));
 await test('teen cannot elevate membership role',()=>denied(()=>user(t1,true,()=>q("update public.memberships set role='parent'"))));
 await test('teen cannot insert XP events',()=>denied(()=>user(t1,true,()=>q('insert into public.xp_events default values'))));
 await test('clients cannot read invitation hashes',()=>denied(()=>user(p1,false,()=>q('select * from petal_private.invites'))));
 await test('clients cannot invoke internal issuer',()=>denied(()=>user(p1,false,()=>value("select petal_private.issue_invite($1,'parent')",[A]))));
 await test('anonymous identity cannot create a parent family',()=>denied(()=>user(unpaired,true,()=>rpc('create_family',['Unauthorized']))));
 await test('API v1 handshake available only to authenticated users',async()=>{assert.equal((await user(t1,true,()=>rpc('get_contract_version',[]))).api_contract_version,1);await denied(()=>user(null,false,()=>rpc('get_contract_version',[]),'anon'))});
 await test('occurrence is stable across retries',async()=>{occurrence=await user(t1,true,()=>rpc('create_occurrence',[defA,actorA]));const again=await user(p1,false,()=>rpc('create_occurrence',[defA,actorA]));assert.equal(occurrence.id,again.id);assert.equal(occurrence.points_snapshot,10)});
 await test('submission retry reuses request and submission identity',async()=>{const request=randomUUID();submission=await user(t1,true,()=>rpc('submit_occurrence',[occurrence.id,request]));const again=await user(t1,true,()=>rpc('submit_occurrence',[occurrence.id,request]));assert.equal(again.id,submission.id);assert.equal(again.request_id,request)});
 await test('new request cannot create second submission for same slot',async()=>{const again=await user(t1,true,()=>rpc('submit_occurrence',[occurrence.id,randomUUID()]));assert.equal(again.id,submission.id)});
 await test('teen cannot approve its own submission',()=>denied(()=>user(t1,true,()=>rpc('approve_submission',[submission.id,randomUUID()]))));
 await test('other-family parent cannot approve',()=>denied(()=>user(pb,false,()=>rpc('approve_submission',[submission.id,randomUUID()]))));
 let approvalRequest;
 await test('two parents sequentially converge on one decision',async()=>{approvalRequest=randomUUID();decision=await user(p1,false,()=>rpc('approve_submission',[submission.id,approvalRequest]));const second=await user(p2,false,()=>rpc('approve_submission',[submission.id,randomUUID()]));assert.equal(decision.decision_id,second.decision_id);assert.equal(second.spendable_xp,0)});
 await test('approval retry returns exact original receipt',async()=>assert.deepEqual(await user(p1,false,()=>rpc('approve_submission',[submission.id,approvalRequest])),decision));
 await test('decision, zero-mint contribution and outbox occur once',async()=>{for(const sql of ['select count(*)::int from public.decisions','select count(*)::int from public.xp_events',"select count(*)::int from petal_private.outbox where topic='submission.approved'"])assert.equal(await value(sql),1);assert.equal(await value('select sum(spendable_xp+coins)::int from public.xp_events'),0)});
 await test('cross-family submission, decision and contribution reads return zero',()=>user(pb,false,async()=>{for(const table of ['submissions','decisions','xp_events'])assert.equal((await q(`select * from public.${table} where family_id=$1`,[A])).rows.length,0)}));
 const otherDef=randomUUID();
 await q('insert into public.task_definitions(id,family_id,title,enabled) values($1,$2,$3,true)',[otherDef,A,'SYNTHETIC SECOND TASK']);
 await q("insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source) values($1,$2,1,10,'23:59:59',array[0,1,2,3,4,5,6],true,'LOCAL SYNTHETIC')",[A,otherDef]);
 const otherOccurrence=await user(t1,true,()=>rpc('create_occurrence',[otherDef,actorA]));const otherSubmission=await user(t1,true,()=>rpc('submit_occurrence',[otherOccurrence.id,randomUUID()]));
 await test('same request ID with different payload is rejected',()=>denied(()=>user(p1,false,()=>rpc('approve_submission',[otherSubmission.id,approvalRequest])),'22023'));
 await test('late new submission is rejected without award',async()=>{await q("update public.task_occurrences set due_at=clock_timestamp()-interval '1 minute' where id=$1",[otherOccurrence.id]);const lateDef=randomUUID();await q('insert into public.task_definitions(id,family_id,title,enabled) values($1,$2,$3,true)',[lateDef,A,'SYNTHETIC LATE']);await q("insert into public.rule_versions(family_id,definition_id,version,points,local_due_time,weekdays,current_version,approved_source) values($1,$2,1,10,'00:00:00',array[0,1,2,3,4,5,6],true,'LOCAL SYNTHETIC')",[A,lateDef]);const late=await user(t1,true,()=>rpc('create_occurrence',[lateDef,actorA]));await assert.rejects(()=>user(t1,true,()=>rpc('submit_occurrence',[late.id,randomUUID()])),/late_policy_unresolved/);assert.equal(await value('select count(*)::int from public.xp_events'),1)});
 await test('published day blocks new approval but retains old receipt',async()=>{await q("insert into public.day_results(family_id,teen_id,local_date,first_published_at,effective_seal_at) values($1,$2,$3,clock_timestamp(),clock_timestamp()+interval '1 day')",[A,actorA,occurrence.local_date]);await assert.rejects(()=>user(p1,false,()=>rpc('approve_submission',[otherSubmission.id,randomUUID()])),/published_day_correction_unresolved/);assert.deepEqual(await user(p1,false,()=>rpc('approve_submission',[submission.id,approvalRequest])),decision)});
 await test('initial catch-up is idempotent and excludes future ranges',async()=>{const today=await value("select (clock_timestamp() at time zone 'America/Costa_Rica')::date");const args=[A,actorA,today,today];const a=await user(t1,true,()=>rpc('reconcile_occurrences',args));const b=await user(t1,true,()=>rpc('reconcile_occurrences',args));assert.equal(a.historical_generation_status,'initial_version_only');assert.equal(a.occurrences.length,b.occurrences.length);await assert.rejects(()=>user(t1,true,()=>rpc('reconcile_occurrences',[A,actorA,today,'2099-01-01'])),/invalid_reconciliation_range/)});
 await test('initial rules cannot silently be changed',()=>assert.rejects(()=>q('update public.rule_versions set points=11 where definition_id=$1',[defA]),/rule_change_policy_unresolved/));
 const p3=uid(3,3);await addUser(p3,false);let familyC,code;
 await test('new parent creates 28 seeded duty variants',async()=>{familyC=(await user(p3,false,()=>rpc('create_family',['SYNTHETIC FAMILY C']))).family_id;assert.equal(await value('select count(*)::int from public.task_definitions where family_id=$1',[familyC]),28);const sums=(await q("select case when 1=any(weekdays) then 'weekday' else 'weekend' end as variant,sum(points)::int as points from public.rule_versions where family_id=$1 group by 1 order by 1",[familyC])).rows;assert.deepEqual(sums.map(x=>x.points),[100,100])});
 await test('teen cannot issue codes',()=>denied(()=>user(t1,true,()=>rpc('issue_teen_pairing',[A]))));
 await test('pairing code is hashed at rest and single-use across identities',async()=>{code=await user(p3,false,()=>rpc('issue_teen_pairing',[familyC]));assert.match(code.code,/^[0-9a-f]{64}$/);assert.equal(await value('select count(*)::int from petal_private.invites where code_hash=extensions.digest($1,\'sha256\')',[code.code]),1);const joined=await user(unpaired,true,()=>rpc('redeem_teen_pairing',[code.code]));assert.equal(joined.role,'teen');const other=uid(3,4);await addUser(other);assert.equal((await user(other,true,()=>rpc('redeem_teen_pairing',[code.code]))).error,'invalid_or_expired_code');assert.equal((await user(unpaired,true,()=>rpc('redeem_teen_pairing',[code.code]))).actor_id,joined.actor_id)});
 await test('anonymous identity cannot redeem a parent invitation',async()=>{const invitation=await user(p3,false,()=>rpc('issue_parent_invite',[familyC]));const other=uid(3,5);await addUser(other);await denied(()=>user(other,true,()=>rpc('accept_parent_invite',[invitation.code])));assert.equal((await user(other,true,()=>rpc('redeem_teen_pairing',[invitation.code]))).error,'invalid_or_expired_code')});
 await test('expired code is rejected',async()=>{const expired=await user(p3,false,()=>rpc('issue_teen_pairing',[familyC]));await q("update petal_private.invites set expires_at=clock_timestamp()-interval '1 second' where code_hash=extensions.digest($1,'sha256')",[expired.code]);const other=uid(3,6);await addUser(other);assert.equal((await user(other,true,()=>rpc('redeem_teen_pairing',[expired.code]))).error,'invalid_or_expired_code')});
 await test('invalid-code rate counter commits through denials',async()=>{const other=uid(3,7);await addUser(other);for(let i=0;i<10;i++)assert.equal((await user(other,true,()=>rpc('redeem_teen_pairing',['0'.repeat(64)]))).error,'invalid_or_expired_code');assert.equal((await user(other,true,()=>rpc('redeem_teen_pairing',['0'.repeat(64)]))).error,'rate_limited')});
 await test('revoked teen loses access and replacement preserves stable actor',async()=>{await user(p1,false,()=>rpc('revoke_membership',[A,t1]));assert.equal((await user(t1,true,()=>q('select * from public.families'))).rows.length,0);await denied(()=>user(t1,true,()=>rpc('submit_occurrence',[occurrence.id,randomUUID()])));const replacement=await user(p1,false,()=>rpc('issue_teen_replacement',[A,actorA]));const newTeen=uid(4,1);await addUser(newTeen);assert.equal((await user(newTeen,true,()=>rpc('redeem_teen_pairing',[replacement.code]))).actor_id,actorA);assert.equal((await user(newTeen,true,()=>q('select * from public.task_occurrences where id=$1',[occurrence.id]))).rows.length,1)});
 await test('revoked parent loses access; last-parent removal is blocked',async()=>{await user(p1,false,()=>rpc('revoke_membership',[A,p2]));assert.equal((await user(p2,false,()=>q('select * from public.families'))).rows.length,0);await assert.rejects(()=>user(p1,false,()=>rpc('revoke_membership',[A,p1])),/last_parent_cannot_be_revoked/)});
 await test('no health/cycle payload columns in synchronized schema',async()=>{const names=(await q("select column_name from information_schema.columns where table_schema='public'")).rows;assert.equal(names.filter(x=>/health|symptom|cycle|period/i.test(x.column_name)).length,0)});
}catch(e){results.push({name:'harness',status:'FAIL',error:e.message,code:e.code});console.log('HARNESS FAIL '+e.message)}
finally{
 await db.close();
 const report={date:new Date().toISOString(),scope:'Disposable local PGlite PostgreSQL with minimal Supabase Auth role/claim stubs; no hosted Supabase or real accounts accessed',engine:'PGlite 0.5.11',passed:results.filter(x=>x.status==='PASS').length,failed:results.filter(x=>x.status==='FAIL').length,notVerified:['Hosted JWT/Auth gateway','Real multi-connection row-lock concurrency','Actual development deployment matches local source','Live network/offline reconnect'],results};
 await fs.writeFile(path.resolve(here,'../../..','Documentation/Phase6/backend-local-results.json'),JSON.stringify(report,null,2));
 console.log(`RESULT ${report.passed} passed; ${report.failed} failed`);
 if(report.failed)process.exitCode=1;
}

