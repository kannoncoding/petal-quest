// Offline adapter only: intercepts all runner I/O and HTTPS. Never contacts Supabase.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const tables=Object.fromEntries(['families','memberships','task_definitions','rule_versions','task_occurrences','submissions','decisions','xp_events'].map(x=>[x,[]]));
const users=new Map(),invites=new Map(),receipts=new Map();let inFlight=0,maxConcurrent=0;
const authFailure=process.env.PETAL_MOCK_AUTH_FAILURE==='1';
const originalRead=fs.readFile.bind(fs);fs.readFile=async(p,...args)=>{
 if(String(p).endsWith('development.local.json'))return JSON.stringify({projectUrl:'https://hijtwgugzzpjjkuutyfy.supabase.co',publishableKey:'sb_publishable_mock'});
 if(String(p).endsWith('phase6-backend-fixtures.json'))throw Object.assign(Error('absent'),{code:'ENOENT'});
 return originalRead(p,...args);
};
fs.writeFile=async(p,s)=>{if(String(p).endsWith('phase6-live-acceptance-results.json')){const r=JSON.parse(s);if(authFailure){assert.ok(r.results.some(x=>x.name==='parent B authentication'&&x.status==='FAIL'&&x.httpStatus===400&&x.code==='invalid_credentials'));assert.ok(!s.includes('sensitive-response-must-not-leak'));assert.equal(tables.families.length,0);console.log('OFFLINE auth-failure diagnostic and redaction: PASS; no live request')}else{assert.ok(!r.results.some(x=>x.status==='FAIL'),JSON.stringify(r));assert.ok(r.results.some(x=>x.name==='populated paired work isolation in both directions'&&x.status==='PASS'));assert.ok(maxConcurrent>=2,'Approval HTTPS launches must overlap');console.log('OFFLINE mock completed; no live acceptance claim')}}else assert.ok(/phase6-backend-fixtures.json|phase6-outbox-owner-audit.sql/.test(String(p)))};
function session(anonymous){const s={user:{id:randomUUID(),is_anonymous:anonymous},access_token:randomUUID(),refresh_token:randomUUID()};users.set(s.access_token,s);return s}
const own=s=>tables.memberships.find(m=>m.user_id===s?.user.id&&m.active);
const family=s=>own(s)?.family_id;
const response=(data,status=200)=>({status,json:async()=>data});
globalThis.fetch=async(url,options={})=>{
 const u=new URL(url),body=options.body?JSON.parse(options.body):{},s=users.get((options.headers?.Authorization||'').replace('Bearer ',''));
 if(u.pathname==='/auth/v1/token'){assert.ok(body.password==='synthetic-only'||body.password==='synthetic-\u00f1\u{1f512}','Synthetic stdin transport corrupted');if(authFailure&&body.email==='qa-parent-b@example.com')return response({error_code:'invalid_credentials',message:'sensitive-response-must-not-leak'},400);return response(session(false))}
 if(u.pathname==='/auth/v1/signup')return response(session(true));
 if(u.pathname==='/auth/v1/logout'){assert.equal(u.searchParams.get('scope'),'local');return response(null,204)}
 if(!s)return response({},401);
 if(u.pathname.startsWith('/rest/v1/rpc/')){
 const name=u.pathname.split('/').at(-1),f=family(s),role=own(s)?.role;
 if(name==='create_family'){
 const id=randomUUID();tables.families.push({id,name:body.p_name});tables.memberships.push({family_id:id,user_id:s.user.id,actor_id:randomUUID(),role:'parent',active:true});
 const def=randomUUID();tables.task_definitions.push({id:def,family_id:id,catalogue_key:'mock-duty',enabled:true});tables.rule_versions.push({id:randomUUID(),family_id:id,definition_id:def,current_version:true,version:1,local_due_time:'23:59:59',weekdays:[0,1,2,3,4,5,6]});return response({family_id:id});}
 if(['issue_parent_invite','issue_teen_pairing','issue_teen_replacement'].includes(name)){if(role!=='parent'||f!==body.p_family_id)return response({},403);const code=randomUUID();invites.set(code,{family_id:f,role:name==='issue_parent_invite'?'parent':'teen',actor_id:body.p_actor_id||randomUUID()});return response({code})}
 if(['accept_parent_invite','redeem_teen_pairing'].includes(name)){const i=invites.get(body.p_code);assert.ok(i);tables.memberships.push({...i,user_id:s.user.id,active:true});return response(i)}
 if(name==='revoke_membership'){assert.equal(role,'parent');const m=tables.memberships.find(m=>m.family_id===f&&m.user_id===body.p_user_id);assert.ok(m);m.active=false;return response({})}
 if(name==='register_device')return response({},f?200:403);
 if(name==='create_occurrence'){const d=tables.task_definitions.find(d=>d.id===body.p_definition_id&&d.family_id===f);assert.ok(d);const o={id:randomUUID(),family_id:f,teen_id:body.p_teen_id,points_snapshot:11,due_at:new Date(Date.now()+3600000).toISOString()};tables.task_occurrences.push(o);return response(o)}
 if(name==='submit_occurrence'){const o=tables.task_occurrences.find(o=>o.id===body.p_occurrence_id);if(role!=='teen'||o?.teen_id!==own(s)?.actor_id)return response({},403);let sub=tables.submissions.find(x=>x.occurrence_id===o.id);if(!sub){sub={id:randomUUID(),family_id:f,teen_id:o.teen_id,occurrence_id:o.id};tables.submissions.push(sub)}return response({...sub,request_id:body.p_request_id})}
 if(name==='approve_submission'){const sub=tables.submissions.find(x=>x.id===body.p_submission_id);if(role!=='parent'||sub?.family_id!==f)return response({},403);inFlight++;maxConcurrent=Math.max(maxConcurrent,inFlight);await new Promise(r=>setTimeout(r,10));inFlight--;let d=tables.decisions.find(x=>x.submission_id===sub.id);if(!d){d={id:randomUUID(),submission_id:sub.id,family_id:f};tables.decisions.push(d);tables.xp_events.push({id:randomUUID(),family_id:f,decision_id:d.id,teen_id:sub.teen_id,contribution_points:11,spendable_xp:0,coins:0})}return response({decision_id:d.id,request_id:body.p_request_id,submission_id:sub.id,status:'approved',contribution_points:11,spendable_xp:0})}
 throw Error('Unhandled mock RPC');
 }
 const table=u.pathname.split('/').at(-1);if(options.method&&options.method!=='GET')return response({},403);
 let rows=tables[table];assert.ok(rows,'Unexpected mock table');rows=rows.filter(r=>r.family_id?r.family_id===family(s):r.id===family(s));for(const [key,value]of u.searchParams){if(key==='select')continue;assert.ok(value.startsWith('eq.'));rows=rows.filter(r=>String(r[key])===value.slice(3))}return response(rows.map(x=>({...x})));
};


