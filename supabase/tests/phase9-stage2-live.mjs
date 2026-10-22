import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID as id} from 'node:crypto';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
const here=path.dirname(fileURLToPath(import.meta.url));
const cfg=JSON.parse((await fs.readFile(path.resolve(here,'../../../Configuration/Supabase/development.local.json'),'utf8')).replace(/^\uFEFF/,''));
assert.equal(cfg.projectUrl,'https://hijtwgugzzpjjkuutyfy.supabase.co');
assert.ok(cfg.publishableKey?.startsWith('sb_publishable_'));
const chunks=[];for await(const c of process.stdin)chunks.push(c);
const credentials=JSON.parse(Buffer.concat(chunks).toString('utf8'));chunks.length=0;
assert.deepEqual(credentials.map(c=>c.email),['qa-parent-a@example.com','qa-parent-b@example.com','qa-parent-c@example.com']);
const sessions=[],fixtures=[],results=[],families=new Set();let stage='authenticate';
async function req(s,name,args){const route=name.startsWith('/')?name:'/rest/v1/rpc/'+name;let r;
 try{r=await fetch(cfg.projectUrl+route,{method:'POST',headers:{apikey:cfg.publishableKey,...(s?{Authorization:'Bearer '+s.access_token}:{}),'Content-Type':'application/json'},body:JSON.stringify(args??{}),redirect:'error',signal:AbortSignal.timeout(25000)})}catch{throw {safeReason:'Network request failed',operation:route.split('?')[0]}}
 let data;try{data=await r.json()}catch{}return {status:r.status,data,operation:route.split('?')[0]};}
const safeAuthCodes=new Set(['invalid_credentials','email_not_confirmed','user_banned','signup_disabled','anonymous_provider_disabled','over_request_rate_limit','over_email_send_rate_limit','rate_limited','request_timeout','unexpected_failure','validation_failed','bad_jwt','session_not_found','refresh_token_not_found','refresh_token_already_used']);
function safeCode(data){if(safeAuthCodes.has(data?.error_code))return data.error_code;if(safeAuthCodes.has(data?.code))return data.code;return typeof data?.code==='string'&&/^(?:[0-9]{2}[A-Z0-9]{3}|PGRST[0-9]{3})$/.test(data.code)?data.code:undefined;}
function ok(r){if(r.status<200||r.status>=300)throw {safeReason:'Service rejected operation',httpStatus:r.status,code:safeCode(r.data),operation:r.operation};return r.data;}
const rpc=async(s,n,a)=>ok(await req(s,n,a));
async function get(s,table,filter){assert.ok(!filter.includes('family_id=eq.')||[...families].some(f=>filter.includes('family_id=eq.'+f)));const r=await fetch(cfg.projectUrl+'/rest/v1/'+table+'?select=*&'+filter,{headers:{apikey:cfg.publishableKey,Authorization:'Bearer '+s.access_token},redirect:'error',signal:AbortSignal.timeout(25000)});return ok({status:r.status,data:await r.json(),operation:table});}
const member=s=>get(s,'memberships','user_id=eq.'+s.user.id);
async function reject(s,n,a,code){const r=await req(s,n,a);assert.ok(r.status>=400&&r.status<500);if(code)assert.equal(r.data?.code,code);}
async function check(name,fn){stage=name;try{await fn();results.push({name,status:'PASS'});console.log('PASS '+name);}catch(e){results.push({name,status:'FAIL',reason:e.safeReason??'Assertion or prerequisite failed',...(e.httpStatus?{httpStatus:e.httpStatus}:{}),...(e.code?{code:e.code}:{}),...(e.operation?{operation:e.operation}:{})});throw e;}}
function manual(name,reason){results.push({name,status:'UNVERIFIED',reason});}
async function validate(s,f){const rows=await get(s,'families','id=eq.'+f);assert.equal(rows.length,1);assert.match(rows[0].name,/^QA P(?:6|9) /);families.add(f);}
async function family(s,label){const m=await member(s);if(m.length){assert.equal(m.length,1);assert.equal(m[0].role,'parent');assert.equal(m[0].active,true);await validate(s,m[0].family_id);return m[0].family_id;}const f=(await rpc(s,'create_family',{p_name:'QA P9 '+label})).family_id;await validate(s,f);return f;}
async function teen(p,f){assert.ok(families.has(f));const invite=await rpc(p,'issue_teen_pairing',{p_family_id:f});const s=await rpc(null,'/auth/v1/signup',{});assert.ok(s.user?.is_anonymous&&s.access_token);sessions.push(s);const m=await rpc(s,'redeem_teen_pairing',{p_code:invite.code});assert.equal(m.family_id,f);const t={s,actor:m.actor_id,f,p};fixtures.push(t);await rpc(s,'materialize_teen_tasks',{});return t;}
let today;
const dash=t=>rpc(t.p,'get_parent_dashboard',{p_family_id:t.f,p_teen_id:t.actor,p_from:today,p_to:today});
const day=async t=>(await dash(t)).day_summaries.find(d=>d.local_date===today);
async function correction(t,o,outcome){return rpc(t.p,'correct_occurrence',{p_occurrence_id:o.id,p_outcome:outcome,p_expected_revision:(await day(t)).edit_revision,p_reason:'Fictional Phase9 acceptance',p_request_id:id()});}
const finalize=t=>rpc(t.p,'finalize_complete_day',{p_teen_id:t.actor,p_local_date:today,p_request_id:id()});
async function deduction(t,key){return rpc(t.p,'enter_deduction',{p_teen_id:t.actor,p_local_date:today,p_deduction_key:key,p_entry_id:id(),p_request_id:id()});}
async function reverse(t,e){return rpc(t.p,'reverse_deduction',{p_entry_id:e.id,p_expected_revision:(await day(t)).edit_revision,p_reason:'Fictional reversal',p_request_id:id()});}
async function full(t){for(const o of (await dash(t)).tasks)await correction(t,o,'approved');}
async function statusBoth(t,occurrenceId,status){const parent=await dash(t),teen=await rpc(t.s,'get_teen_dashboard',{p_from:today,p_to:today});assert.equal(parent.tasks.find(x=>x.id===occurrenceId)?.status,status);assert.equal(teen.tasks.find(x=>x.id===occurrenceId)?.status,status);}
try{
 const parents=[];for(const [index,c] of credentials.entries()){await check('Parent '+['A','B','C'][index]+' authentication',async()=>{try{const s=await rpc(null,'/auth/v1/token?grant_type=password',{email:c.email,password:c.password});assert.equal(s.user.is_anonymous,false);assert.ok(s.access_token);sessions.push(s);parents.push(s);}finally{c.password='';}});}
 const [a,b,c]=parents;assert.equal(new Set(parents.map(s=>s.user.id)).size,3);
 // Inspect all supplied identities before any family mutation. Never alter a non-QA family.
 for(const s of parents)for(const m of await member(s)){assert.equal(m.role,'parent');assert.equal(m.active,true);await validate(s,m.family_id);}
 const fa=await family(a,'A'),fb=await family(c,'B');assert.notEqual(fa,fb);
 const bm=await member(b);if(!bm.length){const inv=await rpc(a,'issue_parent_invite',{p_family_id:fa});assert.equal((await rpc(b,'accept_parent_invite',{p_code:inv.code})).family_id,fa);}else assert.equal(bm[0].family_id,fa);
 // Use the server's local date. Client timezone cannot choose the accounting day.
 const initial=await rpc(a,'get_parent_dashboard',{p_family_id:fa,p_teen_id:null,p_from:'2026-10-22',p_to:'2026-10-22'});today=initial.server_local_date;assert.match(today,/^\d{4}-\d{2}-\d{2}$/);
 const t=await teen(a,fa),other=await teen(c,fb);
 const future=new Date(Date.parse(today+'T12:00:00Z')+86400000).toISOString().slice(0,10);
 const plan={created_at:new Date().toISOString(),project:'hijtwgugzzpjjkuutyfy',operations:[]};
 const planPath=path.join(here,'phase9-stage2-plan.local.json');
 async function record(operation,args){plan.operations.push({operation,args});await fs.writeFile(planPath,JSON.stringify(plan,null,2));}
 async function reviewedReward(s,r,outcome){return req(s,'review_reward_request',{p_reward_request_id:r.id,p_outcome:outcome,p_note:'Fictional stage2 transition',p_request_id:id()});}
 async function reward(){const d=await dash(t),item=d.reward_catalogue.filter(x=>x.sourceStatus==='Available'&&x.coinCost>0).sort((x,y)=>x.coinCost-y.coinCost)[0];assert.ok(item);return rpc(t.s,'request_reward',{p_reward_key:item.id,p_request_id:id()});}
 function racedResponses(rr){assert.ok(rr.every(r=>(r.status>=200&&r.status<300)||(r.status>=400&&r.status<500)));assert.ok(rr.some(r=>r.status>=200&&r.status<300));}
 async function rewardFacts(r){const d=await dash(t);return {d,row:d.reward_requests.find(x=>x.id===r.id),debits:d.wallet_events.filter(x=>x.source_key==='reward-debit:'+r.id),refunds:d.wallet_events.filter(x=>x.source_key==='reward-refund:'+r.id)};}
 await check('approve versus return race commits one checked generation; both dashboards agree',async()=>{
  const o=(await dash(t)).tasks[0],sub=await rpc(t.s,'submit_occurrence',{p_occurrence_id:o.id,p_request_id:id()});
  const version=(await dash(t)).tasks.find(x=>x.id===o.id).review_version;
  const base={p_submission_id:sub.id,p_review_note:'Fictional competing decisions',p_expected_version:version};
  const rr=await Promise.all([req(a,'review_submission_checked',{...base,p_outcome:'approved',p_request_id:id()}),req(b,'review_submission_checked',{...base,p_outcome:'returned',p_request_id:id()})]);racedResponses(rr);assert.equal(rr.filter(r=>r.status>=200&&r.status<300).length,1);
  const observed=(await dash(t)).tasks.find(x=>x.id===o.id);assert.ok(['approved','returned'].includes(observed.status));await statusBoth(t,o.id,observed.status);
  const history=(await dash(t)).review_history.filter(x=>x.submission_id===sub.id);assert.equal(history.length,1);
  const decisions=(await get(a,'decisions','family_id=eq.'+fa)).filter(x=>x.submission_id===sub.id);assert.equal(decisions.length,observed.status==='approved'?1:0);
 });
 await check('negative raw score clamps actual/protected/earned to zero without negative earnings',async()=>{
  await deduction(other,'torn-clothes');const d=await day(other);assert.equal(d.preview.deduction_points,20);assert.equal(d.preview.actual_score,0);assert.equal(d.preview.protected_score,0);assert.equal(d.preview.earned_xp,0);const pub=await finalize(other);assert.equal(pub.actual_score,0);assert.equal(pub.earned_xp,0);assert.equal((await dash(other)).balance.earned_xp,0);
 });
 await check('cash explicit amount and privilege confirmations are audited/idempotent and award no coins',async()=>{
  const before=(await dash(t)).balance;
  const make=async(kind,key)=>rpc(t.s,'request_extra_outcome',{p_kind:kind,p_outcome_key:key,p_target_date:today,p_reason:'Fictional stage2 request',p_request_id:id()});
  const cash=await make('cash','daily-cash');
  await reject(a,'review_extra_outcome',{p_outcome_request_id:cash.id,p_outcome:'confirmed',p_note:'Explicit amount missing',p_request_id:id()});
  await reject(a,'confirm_cash_outcome',{p_outcome_request_id:cash.id,p_cash_amount:-1,p_note:'Invalid amount',p_request_id:id()});
  const args={p_outcome_request_id:cash.id,p_cash_amount:500,p_note:'Fictional explicit500 CRC confirmation; no real payment',p_request_id:id()};
  await reject(t.s,'confirm_cash_outcome',args,'42501');const receipt=await rpc(a,'confirm_cash_outcome',args);assert.equal(receipt.snapshot.cash_amount,500);await rpc(a,'confirm_cash_outcome',args);await rpc(b,'confirm_cash_outcome',{...args,p_request_id:id()});
  const privilege=await make('privilege','privilege-skincare'),pa={p_outcome_request_id:privilege.id,p_outcome:'confirmed',p_note:'Fictional kept privilege',p_request_id:id()};await rpc(a,'review_extra_outcome',pa);await rpc(a,'review_extra_outcome',pa);await rpc(b,'review_extra_outcome',{...pa,p_request_id:id()});
  const d=await dash(t);assert.deepEqual(d.balance,before);for(const r of [cash,privilege])assert.equal(d.parent_actions.filter(x=>x.source_kind==='extra_outcome'&&x.source_id===r.id).length,1);
 });
 await check('reward approval race debits saved price exactly once',async()=>{
  const achievement=(await dash(t)).achievements.find(x=>x.xp===2000);assert.ok(achievement);const e=await rpc(t.s,'request_extra_outcome',{p_kind:'achievement',p_outcome_key:achievement.id,p_target_date:today,p_reason:'Fictional stage2 reward race funding',p_request_id:id()});await rpc(a,'review_extra_outcome',{p_outcome_request_id:e.id,p_outcome:'confirmed',p_note:'Fictional accomplishment',p_request_id:id()});
  const r=await reward(),before=(await dash(t)).balance;const rr=await Promise.all([reviewedReward(a,r,'approved'),reviewedReward(b,r,'approved')]);racedResponses(rr);assert.ok(rr.every(x=>x.status>=200&&x.status<300));const facts=await rewardFacts(r);assert.equal(facts.row.status,'approved');assert.equal(facts.debits.length,1);assert.equal(facts.debits[0].coin_delta,-r.price_snapshot);assert.equal(facts.d.balance.available_coins,before.available_coins-r.price_snapshot);assert.equal(facts.d.balance.earned_xp,before.earned_xp);ok(await reviewedReward(a,r,'cancelled'));
 });
 await check('competing reward approval and cancellation has at most one debit/refund',async()=>{
  const r=await reward(),before=(await dash(t)).balance;const rr=await Promise.all([reviewedReward(a,r,'approved'),reviewedReward(b,r,'cancelled')]);racedResponses(rr);const facts=await rewardFacts(r);assert.equal(facts.row.status,'cancelled');assert.ok(facts.debits.length<=1);assert.equal(facts.refunds.length,facts.debits.length);assert.deepEqual(facts.d.balance,before);
 });
 await check('competing fulfilled versus cancellation preserves one terminal outcome and wallet amount',async()=>{
  const r=await reward(),before=(await dash(t)).balance;ok(await reviewedReward(a,r,'approved'));const rr=await Promise.all([reviewedReward(a,r,'fulfilled'),reviewedReward(b,r,'cancelled')]);racedResponses(rr);assert.equal(rr.filter(x=>x.status>=200&&x.status<300).length,1);const facts=await rewardFacts(r);assert.equal(facts.debits.length,1);assert.ok(['fulfilled','cancelled'].includes(facts.row.status));assert.equal(facts.refunds.length,facts.row.status==='cancelled'?1:0);assert.equal(facts.d.balance.available_coins,before.available_coins-(facts.row.status==='fulfilled'?r.price_snapshot:0));assert.equal(facts.d.balance.earned_xp,before.earned_xp);
 });
 await check('discarded receipt and separate Node process restart replay one durable request',async()=>{
  const args={p_teen_id:t.actor,p_local_date:today,p_text:'Fictional restart receipt fixture',p_expected_version:0,p_request_id:id()};await record('save_reflection_note',args);
  async function worker(mode,requestArgs=args){return new Promise((resolve,rejectWorker)=>{const child=spawn(process.execPath,[path.join(here,'phase9-restart-worker.mjs')],{stdio:['pipe','pipe','pipe'],windowsHide:true});let output='';child.stdout.setEncoding('utf8');child.stdout.on('data',c=>{output+=c;if(output.length>4096)child.kill();});child.stderr.resume();child.on('error',()=>rejectWorker({safeReason:'Restart worker could not start'}));child.on('exit',code=>{try{assert.equal(code,0);resolve(JSON.parse(output));}catch{rejectWorker({safeReason:'Restart worker failed; response body discarded'});}});child.stdin.end(JSON.stringify({projectUrl:cfg.projectUrl,publishableKey:cfg.publishableKey,access_token:a.access_token,operation:'save_reflection_note',args:requestArgs,mode}));});}
  const first=await worker('discard');assert.equal(first.completed,true);assert.equal(first.id,undefined);
  // Reload durable nonsecret intent, rather than recovering it from the first child's memory.
  const persisted=JSON.parse(await fs.readFile(planPath,'utf8')).operations.find(x=>x.args.p_request_id===args.p_request_id);assert.deepEqual(persisted.args,args);
  const second=await worker('recover',persisted.args);assert.equal(second.completed,true);assert.notEqual(first.pid,second.pid);assert.equal(second.request_id,args.p_request_id);assert.equal(second.version,1);
  const d=await dash(t);assert.equal(d.reflection_notes.filter(x=>x.local_date===today).length,1);assert.equal(d.reflection_note_history.filter(x=>x.local_date===today).length,1);
 });
 await check('assigned routine optimistic versions, future snapshot, isolation and inactive cleanup',async()=>{
  const routineWallet=(await dash(t)).wallet_events;const routineBalance=(await dash(t)).balance;const routineId=id(),args={p_family_id:fa,p_teen_id:t.actor,p_routine_id:routineId,p_expected_version:null,p_effective_from:future,p_title:'Fictional stage2 reminder',p_local_times:['07:00','19:00'],p_weekdays:[0,1,2,3,4,5,6],p_active:true,p_request_id:id()};await record('save_assigned_routine',args);
  await reject(t.s,'save_assigned_routine',args,'42501');await reject(c,'save_assigned_routine',args,'42501');await reject(a,'save_assigned_routine',{...args,p_effective_from:today,p_request_id:id()});
  const version=await rpc(a,'save_assigned_routine',args);assert.equal(version.version,1);await rpc(a,'save_assigned_routine',args);await reject(b,'save_assigned_routine',{...args,p_title:'Stale edit',p_request_id:id()});
  const d=await rpc(a,'get_parent_dashboard',{p_family_id:fa,p_teen_id:t.actor,p_from:future,p_to:future});const r=d.assigned_routines.find(x=>x.routine_id===routineId);assert.equal(r?.title,args.p_title);assert.deepEqual(r.local_times,['07:00','19:00']);assert.equal((await dash(t)).assigned_routines.some(x=>x.routine_id===routineId),false);assert.deepEqual(await get(c,'assigned_routine_versions','family_id=eq.'+fa),[]);
  const td=await rpc(t.s,'get_teen_dashboard',{p_from:future,p_to:future});assert.equal(td.assigned_routines.find(x=>x.routine_id===routineId)?.title,args.p_title);
  const cleanup={...args,p_expected_version:version.id,p_active:false,p_request_id:id()};await record('save_assigned_routine',cleanup);await rpc(a,'save_assigned_routine',cleanup);const after=await rpc(a,'get_parent_dashboard',{p_family_id:fa,p_teen_id:t.actor,p_from:future,p_to:future});assert.equal(after.assigned_routines.some(x=>x.routine_id===routineId),false);assert.equal(after.assigned_routine_versions.filter(x=>x.routine_id===routineId).length,2);assert.deepEqual((await dash(t)).wallet_events,routineWallet);assert.deepEqual((await dash(t)).balance,routineBalance);
 });
 const catalogueState=await dash(t);if(catalogueState.catalogue_versions.some(x=>x.effective_from>today))manual('future complete catalogue positive save','Existing future QA versions found; preserve their scheduled intent.');else await check('future complete task catalogue validates total, stale version and immutable current snapshots',async()=>{
  const before=catalogueState;
  const tasks=before.task_definitions.map(x=>({catalogue_key:x.catalogue_key,title:x.title,points:x.points,local_due_time:x.local_due_time,weekdays:x.weekdays,enabled:x.enabled}));
  const versions=[...before.catalogue_versions].sort((x,y)=>y.created_at.localeCompare(x.created_at)||y.id.localeCompare(x.id)),expected=versions[0]?.id??null;
  const args={p_family_id:fa,p_effective_from:future,p_tasks:tasks,p_expected_version:expected,p_request_id:id()};
  await reject(a,'save_task_catalogue',{...args,p_effective_from:today,p_request_id:id()});const invalid=structuredClone(tasks);invalid[0].points+=1;await reject(a,'save_task_catalogue',{...args,p_tasks:invalid,p_request_id:id()});
  // Save the exact current definitions: no future title/weight/schedule changes.
  await record('save_task_catalogue',args);await rpc(a,'save_task_catalogue',args);await rpc(a,'save_task_catalogue',args);await reject(b,'save_task_catalogue',{...args,p_request_id:id()});
  const after=await dash(t);const snapshot=d=>d.tasks.map(x=>({id:x.id,rule_version_id:x.rule_version_id,title_snapshot:x.title_snapshot,points_snapshot:x.points_snapshot,due_at:x.due_at,local_date:x.local_date}));assert.deepEqual(snapshot(after),snapshot(before));assert.deepEqual(after.balance,before.balance);assert.equal(after.catalogue_versions.length,before.catalogue_versions.length+tasks.length);const saved=after.catalogue_versions.filter(x=>x.effective_from===future);for(const task of tasks){const version=saved.find(x=>x.catalogue_key===task.catalogue_key);assert.ok(version);assert.equal(version.payload.points,task.points);assert.equal(version.payload.title,task.title);}
 });
 await check('appeal approval references a later correction and does not itself change accounting',async()=>{
  const appeal=await rpc(other.s,'request_day_appeal',{p_local_date:today,p_reason:'Fictional stage2 appeal',p_request_id:id()});const prior=(await day(other)).revision;
  const o=(await dash(other)).tasks[0];await correction(other,o,'approved');const changed=await day(other);assert.ok(changed.revision>prior);const before=await dash(other);
  const args={p_appeal_id:appeal.id,p_outcome:'approved',p_expected_revision:changed.edit_revision,p_reason:'Fictional correction reviewed explicitly',p_request_id:id()};await rpc(c,'resolve_day_appeal',args);await rpc(c,'resolve_day_appeal',args);const after=await dash(other);assert.deepEqual(after.balance,before.balance);assert.deepEqual(after.wallet_events,before.wallet_events);assert.equal(after.appeal_resolutions.filter(x=>x.appeal_id===appeal.id).length,1);assert.equal(after.day_appeals.find(x=>x.id===appeal.id).status,'resolved');assert.equal(after.appeal_resolutions.find(x=>x.appeal_id===appeal.id).outcome,'approved');assert.equal(after.appeal_resolutions.find(x=>x.appeal_id===appeal.id).result_revision,changed.revision);
 });
 await check('unsubmitted complete day pays0; actual80 virtual20 pays0; conversion85 then100 never doubles',async()=>{
  const bonusTeen=await teen(a,fa),tasks=(await dash(bonusTeen)).tasks;assert.equal((await finalize(bonusTeen)).earned_xp,0);
  function subset(items,target){const choices=new Map([[0,[]]]);for(const item of items)for(const [total,list] of [...choices])if(total+item.points_snapshot<=target&&!choices.has(total+item.points_snapshot))choices.set(total+item.points_snapshot,[...list,item]);return choices.get(target);}
  let excused,first;
  for(let mask=1;mask<(1<<tasks.length);mask++){const candidate=tasks.filter((_,index)=>mask&(1<<index));if(candidate.reduce((n,o)=>n+o.points_snapshot,0)!==20)continue;const five=subset(candidate,5);if(five){excused=candidate;first=five;break;}}
  assert.ok(excused&&first);const excusedIds=new Set(excused.map(x=>x.id));for(const o of tasks)await correction(bonusTeen,o,excusedIds.has(o.id)?'excused':'approved');let d=await day(bonusTeen);assert.equal(d.actual_score,80);assert.equal(d.protected_score,100);assert.equal(d.virtual_remaining,20);assert.equal(d.earned_xp,0);
  async function convert(o){const offer=await rpc(a,'offer_bonus',{p_occurrence_id:o.id,p_description:'Fictional bounded replacement',p_expected_revision:(await day(bonusTeen)).edit_revision,p_request_id:id()});assert.equal(offer.points_snapshot,o.points_snapshot);await rpc(bonusTeen.s,'submit_bonus',{p_bonus_id:offer.id,p_request_id:id()});return rpc(a,'review_bonus',{p_bonus_id:offer.id,p_outcome:'approved',p_expected_revision:(await day(bonusTeen)).edit_revision,p_reason:'Fictional verified replacement',p_request_id:id()});}
  for(const o of first)await convert(o);d=await day(bonusTeen);assert.equal(d.actual_score,85);assert.equal(d.earned_xp,85);assert.equal(d.converted_points,5);assert.equal(d.virtual_remaining,15);
  const firstIds=new Set(first.map(x=>x.id));for(const o of excused.filter(x=>!firstIds.has(x.id)))await convert(o);d=await day(bonusTeen);assert.equal(d.actual_score,100);assert.equal(d.earned_xp,100);assert.equal(d.converted_points,20);assert.equal(d.virtual_remaining,0);assert.equal((await dash(bonusTeen)).balance.earned_xp,100);
 });
 manual('revoked Parent old JWT authority','Public revoke leaves an inactive membership; public invite refuses any existing membership. Reusable QA Parent B cannot be restored safely; requires disposable fourth confirmed Parent or a reviewed restoration API.');
 manual('real future task and routine activation','Future-date dashboard previews and unchanged catalogue writes do not prove materialization after the server date advances.');
 manual('saved reward price after catalogue activation','Requires real future effective server date; future unchanged task save does not prove reward activation.');
 manual('Android process restart and device response loss','Separate Node processes verify server request replay only; Android durable outbox/device restart needs device evidence.');
 manual('seal boundary and appeal expiry','Requires real server seal passage; no privileged clock manipulation.');
 manual('private outbox payload and uniqueness','Run generated read-only owner audit separately.');
}catch(e){if(!results.some(r=>r.status==='FAIL'))results.push({name:'runner prerequisites',status:'FAIL',stage,reason:e.safeReason??'Assertion or prerequisite failed',...(e.httpStatus?{httpStatus:e.httpStatus}:{}),...(e.code?{code:e.code}:{}),...(e.operation?{operation:e.operation}:{})});}
finally{
 for(const t of fixtures)try{await rpc(t.p,'revoke_membership',{p_family_id:t.f,p_user_id:t.s.user.id});}catch{results.push({name:'revoke disposable fictional teen',status:'UNVERIFIED',reason:'Fixture membership cleanup requires QA Parent review'});}
 for(const s of sessions){try{ok(await req(s,'/auth/v1/logout?scope=local',{}));}catch{results.push({name:'session logout',status:'UNVERIFIED'});}s.access_token='';s.refresh_token='';}for(const c of credentials)c.password='';credentials.length=0;
 const report={timestamp:new Date().toISOString(),project:'hijtwgugzzpjjkuutyfy',scope:'Stage2 dedicated fictional QA families, fresh disposable Teen actors; no owner/health data',fixtures:fixtures.map(t=>({family_id:t.f,actor_id:t.actor})),results};await fs.writeFile(path.join(here,'phase9-stage2-results.local.json'),JSON.stringify(report,null,2));for(const r of results.filter(x=>x.status!=='PASS'))console.log(`${r.status} ${r.name}${r.httpStatus?' HTTP '+r.httpStatus:''}${r.code?' '+r.code:''}`);process.exitCode=results.some(r=>r.status==='FAIL')?1:results.some(r=>r.status==='UNVERIFIED')?2:0;
}
