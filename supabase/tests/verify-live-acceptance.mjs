import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const here=path.dirname(fileURLToPath(import.meta.url)), root=path.resolve(here,'../../..');
const cfg=JSON.parse((await fs.readFile(path.join(root,'Configuration/Supabase/development.local.json'),'utf8')).replace(/^\uFEFF/,''));
assert.equal(cfg.projectUrl,'https://hijtwgugzzpjjkuutyfy.supabase.co');
assert.ok(cfg.publishableKey?.startsWith('sb_publishable_'));
const input=[];for await(const chunk of process.stdin)input.push(chunk);
let credentials;try{credentials=JSON.parse(Buffer.concat(input).toString('utf8'))}catch{console.error('Invalid credential input');process.exit(1)}input.length=0;
assert.equal(credentials.length,3);assert.equal(new Set(credentials.map(x=>x.email)).size,3);
const sessions=[], results=[], allowed=new Set();
let stage='signing in dedicated parents';
const safeCodes=new Set(['invalid_credentials','email_not_confirmed','bad_jwt','user_banned','over_request_rate_limit','over_email_send_rate_limit','rate_limited','PGRST202','PGRST301','42501','42P01','42703','42883','23505','22P02','P0001','ECONNREFUSED','ECONNRESET','ENOTFOUND','ETIMEDOUT','CERT_HAS_EXPIRED','UNABLE_TO_VERIFY_LEAF_SIGNATURE','SELF_SIGNED_CERT_IN_CHAIN']);
function diagnostic(error){return {reason:error?.safeReason||'Assertion or sequence prerequisite failed; no response bodies recorded',...(Number.isInteger(error?.httpStatus)?{httpStatus:error.httpStatus}:{}),...(safeCodes.has(error?.safeCode)?{code:error.safeCode}:{}),...(error?.operation?{operation:error.operation}:{})}}
const fixturePath=path.join(here,'phase6-backend-fixtures.json');
let fixture={version:1,families:{},teens:[]};
try{fixture=JSON.parse(await fs.readFile(fixturePath,'utf8'));assert.equal(fixture.version,1)}catch(e){if(e.code!=='ENOENT')throw Error('Invalid fixture manifest')}
const uuid=x=>typeof x==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x);
async function request(s,route,method='GET',body){let r;const operation=route.split('?')[0];try{r=await fetch(cfg.projectUrl+route,{method,headers:{apikey:cfg.publishableKey,...(s?{Authorization:'Bearer '+s.access_token}:{}),...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(25000)})}catch(error){throw Object.assign(Error('Network request failed'),{safeReason:'Network or TLS connection failed',safeCode:error?.cause?.code,operation})}let data;try{data=await r.json()}catch{}return {status:r.status,data,operation}}
function ok(r){if(r.status<200||r.status>=300||r.data?.error)throw Object.assign(Error('Service rejected operation'),{safeReason:'Service rejected operation',httpStatus:r.status,safeCode:r.data?.error_code||r.data?.code||(typeof r.data?.error==='string'?r.data.error:undefined),operation:r.operation});return r.data}
const rpc=async(s,name,args)=>ok(await request(s,'/rest/v1/rpc/'+name,'POST',args));
const read=async(s,t,f,columns='*')=>{assert.ok(allowed.has(f),'Family outside QA allowlist');return ok(await request(s,`/rest/v1/${t}?select=${columns}&family_id=eq.${f}`))};
const denied=r=>assert.ok([401,403].includes(r.status),'Expected access denial');
async function check(name,fn){stage=name;try{await fn();results.push({name,status:'PASS'})}catch(error){results.push({name,status:'FAIL',...diagnostic(error)});throw error}}
async function save(){await fs.writeFile(fixturePath,JSON.stringify(fixture,null,2))}
async function parent(c,index){const name='parent '+['A','B','C'][index]+' authentication';try{const s=ok(await request(null,'/auth/v1/token?grant_type=password','POST',{email:c.email,password:c.password}));assert.ok(s.access_token&&s.user?.id,'Parent sign-in requires a dedicated confirmed QA account');sessions.push(s);assert.equal(s.user.is_anonymous,false);results.push({name,status:'PASS'});return s}catch(error){results.push({name,status:'FAIL',...diagnostic(error)});throw error}finally{c.password=''}}
async function membership(s){return ok(await request(s,'/rest/v1/memberships?select=family_id,role,active,actor_id&user_id=eq.'+s.user.id))}
async function validateFamily(s,id){assert.ok(uuid(id));const rows=ok(await request(s,'/rest/v1/families?select=id,name&id=eq.'+id));assert.equal(rows.length,1);assert.ok(rows[0].name.startsWith('QA P6 '),'Refusing non-QA family');allowed.add(id);return id}
async function family(s,label){const m=await membership(s);if(m.length){assert.equal(m.length,1);assert.ok(m[0].active&&m[0].role==='parent');return validateFamily(s,m[0].family_id)}const f=await rpc(s,'create_family',{p_name:'QA P6 '+label});return validateFamily(s,f.family_id)}
async function anon(){const s=ok(await request(null,'/auth/v1/signup','POST',{}));assert.ok(s.access_token&&s.user?.is_anonymous);sessions.push(s);return s}
async function teen(p,f,label){
 // Old JWTs are intentionally never persisted. Revoke only our recorded anonymous fixture before replacing it.
 const old=fixture.teens.find(x=>x.label===label&&x.family_id===f);
 let invite;
 if(old){assert.ok(uuid(old.actor_id)&&uuid(old.user_id));const recorded=(await read(p,'memberships',f)).filter(m=>m.user_id===old.user_id&&m.actor_id===old.actor_id&&m.role==='teen');assert.equal(recorded.length,1,'Stored fixture must match QA teen membership');await rpc(p,'revoke_membership',{p_family_id:f,p_user_id:old.user_id});invite=await rpc(p,'issue_teen_replacement',{p_family_id:f,p_actor_id:old.actor_id})}
 else invite=await rpc(p,'issue_teen_pairing',{p_family_id:f});
 const s=await anon(), m=await rpc(s,'redeem_teen_pairing',{p_code:invite.code});assert.equal(m.family_id,f);assert.ok(uuid(m.actor_id));if(old)assert.equal(m.actor_id,old.actor_id);
 fixture.teens=fixture.teens.filter(x=>x.label!==label);fixture.teens.push({label,family_id:f,actor_id:m.actor_id,user_id:s.user.id});await save();return {s,actor:m.actor_id};
}
let audit=null;
try{
 const signed=await Promise.allSettled(credentials.map(parent));assert.ok(signed.every(x=>x.status==='fulfilled'),'Dedicated parent sign-in failed');const [a,b,c]=signed.map(x=>x.value);
 // Inspect every provided parent before any family mutation.
 stage='checking existing parent memberships and QA family guard';
 for(const s of [a,b,c])for(const m of await membership(s)){assert.ok(m.active&&m.role==='parent');await validateFamily(s,m.family_id)}
 stage='creating or resuming QA family A';const fa=await family(a,'A');stage='creating or resuming QA family B';const fb=await family(c,'B');assert.notEqual(fa,fb);
 stage='inviting QA parent B';
 const bm=await membership(b);if(!bm.length){const i=await rpc(a,'issue_parent_invite',{p_family_id:fa});const joined=await rpc(b,'accept_parent_invite',{p_code:i.code});assert.equal(joined.family_id,fa)}else assert.equal(bm[0].family_id,fa);
 fixture.families={A:fa,B:fb};await save();
 stage='pairing backend QA teen A';const ta=await teen(a,fa,'backend-A');stage='pairing backend QA teen B';const tb=await teen(c,fb,'backend-B');
 await check('paired own and cross-family reads',async()=>{for(const [s,own,other] of [[a,fa,fb],[b,fa,fb],[c,fb,fa],[ta.s,fa,fb],[tb.s,fb,fa]]){assert.ok((await read(s,'memberships',own)).length>0);for(const t of ['memberships','task_occurrences','submissions','decisions','xp_events'])assert.deepEqual(await read(s,t,other),[])}});
 await check('paired role and XP writes denied',async()=>{for(const s of [a,ta.s]){denied(await request(s,'/rest/v1/memberships?user_id=eq.'+s.user.id,'PATCH',{role:'parent'}));denied(await request(s,'/rest/v1/xp_events','POST',{family_id:fa,teen_id:ta.actor,contribution_points:100,spendable_xp:100}))}});
 stage='selecting known future catalogue deadline';const date=new Intl.DateTimeFormat('en-CA',{timeZone:'America/Costa_Rica',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const weekday=new Date(date+'T12:00:00-06:00').getUTCDay();
 const rules=await read(a,'rule_versions',fa), defs=await read(a,'task_definitions',fa);
 const eligible=rules.filter(r=>r.current_version&&r.version===1&&r.local_due_time&&r.weekdays.includes(weekday)&&Date.parse(date+'T'+r.local_due_time+'-06:00')>Date.now()+120000&&defs.some(d=>d.id===r.definition_id&&d.enabled&&d.catalogue_key));
 if(!eligible.length)results.push({name:'positive submission and concurrent approval',status:'BLOCKED',reason:'No provisioned catalogue task has a known future deadline today'});
 else {
 stage='creating positive work and approval fixtures';
 eligible.sort((x,y)=>y.local_due_time.localeCompare(x.local_due_time));const occurrence=await rpc(a,'create_occurrence',{p_definition_id:eligible[0].definition_id,p_teen_id:ta.actor});const brules=await read(c,'rule_versions',fb);const bdefs=await read(c,'task_definitions',fb);const bdef=bdefs.find(d=>d.catalogue_key===defs.find(d=>d.id===eligible[0].definition_id).catalogue_key);assert.ok(bdef&&brules.some(r=>r.definition_id===bdef.id&&r.current_version));const bo=await rpc(c,'create_occurrence',{p_definition_id:bdef.id,p_teen_id:tb.actor});const bs=await rpc(tb.s,'submit_occurrence',{p_occurrence_id:bo.id,p_request_id:randomUUID()});await rpc(c,'approve_submission',{p_submission_id:bs.id,p_request_id:randomUUID()});assert.ok(Date.parse(occurrence.due_at)>Date.now());
 const rid=randomUUID(), args={p_occurrence_id:occurrence.id,p_request_id:rid};
 const sub=await rpc(ta.s,'submit_occurrence',args);assert.equal(sub.request_id,rid);
 await check('submission replay and duplicate are idempotent',async()=>{const replay=await rpc(ta.s,'submit_occurrence',args);assert.equal(replay.id,sub.id);assert.equal(replay.request_id,rid);const duplicateId=randomUUID(),duplicate=await rpc(ta.s,'submit_occurrence',{...args,p_request_id:duplicateId});assert.equal(duplicate.id,sub.id);assert.equal(duplicate.request_id,duplicateId)});
 await check('teen and cross-family approvals denied',async()=>{for(const s of [ta.s,c])denied(await request(s,'/rest/v1/rpc/approve_submission','POST',{p_submission_id:sub.id,p_request_id:randomUUID()}))});
 let approvals;const ar={p_submission_id:sub.id,p_request_id:randomUUID()},br={p_submission_id:sub.id,p_request_id:randomUUID()};
 await check('separate concurrent parent HTTPS approvals produce one award',async()=>{approvals=await Promise.all([rpc(a,'approve_submission',ar),rpc(b,'approve_submission',br)]);assert.equal(approvals[0].request_id,ar.p_request_id);assert.equal(approvals[1].request_id,br.p_request_id);for(const receipt of approvals){assert.equal(receipt.submission_id,sub.id);assert.equal(receipt.status,'approved');assert.equal(receipt.contribution_points,occurrence.points_snapshot);assert.equal(receipt.spendable_xp,0)}assert.equal(approvals[0].decision_id,approvals[1].decision_id);const replay=await rpc(a,'approve_submission',ar);assert.equal(replay.decision_id,approvals[0].decision_id);assert.equal(replay.request_id,ar.p_request_id);const ds=(await read(a,'decisions',fa)).filter(d=>d.submission_id===sub.id),xs=(await read(a,'xp_events',fa)).filter(x=>x.decision_id===approvals[0].decision_id);assert.equal(ds.length,1);assert.equal(xs.length,1);assert.equal(xs[0].contribution_points,occurrence.points_snapshot);assert.equal(xs[0].spendable_xp,0);assert.equal(xs[0].coins,0)});
 await check('populated paired work isolation in both directions',async()=>{for(const [ownS,crossS,f] of [[ta.s,tb.s,fa],[tb.s,ta.s,fb],[a,c,fa],[c,a,fb]])for(const t of ['task_occurrences','submissions','decisions','xp_events']){assert.ok((await read(ownS,t,f)).length>0);assert.deepEqual(await read(crossS,t,f),[])}});
 for(const id of [fa,sub.id,approvals[0].decision_id])assert.ok(uuid(id));
 audit=`-- Owner-only, read-only audit. Run separately; never supply owner credentials to this runner.\nselect topic, count(*) as event_count from petal_private.outbox where family_id='${fa}'::uuid and ((topic='submission.pending' and source_id='${sub.id}'::uuid) or (topic='submission.approved' and source_id='${approvals[0].decision_id}'::uuid)) group by topic;\n-- Expected: submission.pending=1 and submission.approved=1.\n`;
 }
 await check('revocation denies old JWT and replacement preserves actor',async()=>{const history={};for(const t of ['task_occurrences','submissions','decisions','xp_events'])history[t]=(await read(ta.s,t,fa)).map(x=>x.id).sort();await rpc(a,'revoke_membership',{p_family_id:fa,p_user_id:ta.s.user.id});assert.deepEqual(await read(ta.s,'memberships',fa),[]);assert.deepEqual(await read(ta.s,'task_occurrences',fa),[]);denied(await request(ta.s,'/rest/v1/rpc/register_device','POST',{p_family_id:fa,p_push_token:'qa-revoked-probe'}));const i=await rpc(a,'issue_teen_replacement',{p_family_id:fa,p_actor_id:ta.actor});const replacement=await anon(),m=await rpc(replacement,'redeem_teen_pairing',{p_code:i.code});assert.equal(m.actor_id,ta.actor);fixture.teens.find(x=>x.label==='backend-A').user_id=replacement.user.id;await save();assert.ok((await read(replacement,'memberships',fa)).length);assert.deepEqual(await read(ta.s,'memberships',fa),[]);for(const t of ['task_occurrences','submissions','decisions','xp_events']){assert.deepEqual(await read(ta.s,t,fa),[]);assert.deepEqual((await read(replacement,t,fa)).map(x=>x.id).sort(),history[t])}});
}catch(error){results.push({name:'runner prerequisite or acceptance sequence',status:'FAIL',stage,...diagnostic(error)})}
finally{for(const s of sessions){try{const logout=await request(s,'/auth/v1/logout?scope=local','POST');assert.ok(logout.status>=200&&logout.status<300)}catch{results.push({name:'local fixture session logout',status:'UNVERIFIED'})}s.access_token='';s.refresh_token=''}credentials.length=0;
 if(audit)await fs.writeFile(path.join(here,'phase6-outbox-owner-audit.sql'),audit);
 results.push({name:'private outbox uniqueness',status:'UNVERIFIED',reason:audit?'Run generated read-only owner audit separately':'Positive path did not produce audit fixture'});
 const report={timestamp:new Date().toISOString(),scope:'Dedicated QA P6 families only; public key; dedicated parent logins and new anonymous fixture identities',results};await fs.writeFile(path.join(here,'phase6-live-acceptance-results.json'),JSON.stringify(report,null,2));for(const r of results)console.log(r.status+' '+r.name+(r.stage?' ['+r.stage+']':'')+(r.httpStatus?' HTTP '+r.httpStatus:'')+(r.code?' '+r.code:'')+(r.operation?' '+r.operation:''));process.exitCode=results.some(r=>r.status==='FAIL')?1:results.some(r=>r.status==='BLOCKED'||r.status==='UNVERIFIED')?2:0;
}







