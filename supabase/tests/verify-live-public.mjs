import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const here=path.dirname(fileURLToPath(import.meta.url));
const workspace=path.resolve(here,'../../..');
const config=JSON.parse((await fs.readFile(path.join(workspace,'Configuration/Supabase/development.local.json'),'utf8')).replace(/^\uFEFF/,''));
assert.equal(config.projectUrl,'https://hijtwgugzzpjjkuutyfy.supabase.co');
assert.ok(config.publishableKey.startsWith('sb_publishable_'));
let token=null,probeId=null;
const results=[];
async function request(route,{method='GET',body,authenticated=false,headers={}}={}){
 const r=await fetch(config.projectUrl+route,{method,headers:{apikey:config.publishableKey,...(authenticated?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),...headers},body:body?JSON.stringify(body):undefined,redirect:'error',signal:AbortSignal.timeout(20000)});
 const text=await r.text();let data;try{data=JSON.parse(text)}catch{data=null}return {status:r.status,data};
}
async function test(name,fn){try{await fn();results.push({name,status:'PASS'});console.log('PASS '+name)}catch(e){results.push({name,status:'FAIL',error:e.message});console.log('FAIL '+name+': '+e.message)}}
const denied=r=>assert.ok([401,403].includes(r.status),'Expected access denial; received HTTP '+r.status);
try{
 await test('unauthenticated family reads denied',async()=>denied(await request('/rest/v1/families?select=id')));
 await test('unauthenticated membership reads denied',async()=>denied(await request('/rest/v1/memberships?select=user_id')));
 await test('private schema not exposed to API',async()=>{const r=await request('/rest/v1/invites?select=id',{headers:{'Accept-Profile':'petal_private'}});assert.equal(r.status,406);assert.equal(r.data?.code,'PGRST106')});
 const auth=await request('/auth/v1/signup',{method:'POST',body:{}});
 assert.equal(auth.status,200,'Anonymous verification identity could not be created');
 token=auth.data.access_token;probeId=auth.data.user.id;assert.ok(token&&probeId);
 await test('unpaired anonymous JWT reaches contract v1',async()=>{const r=await request('/rest/v1/rpc/get_contract_version',{method:'POST',body:{},authenticated:true});assert.equal(r.status,200);assert.equal(r.data?.api_contract_version,1)});
 for(const table of ['families','memberships','task_occurrences','xp_events'])await test('unpaired JWT sees zero '+table,async()=>{const r=await request('/rest/v1/'+table+'?select=*',{authenticated:true});assert.equal(r.status,200);assert.deepEqual(r.data,[])});
 await test('unpaired teen cannot become a parent through family creation',async()=>denied(await request('/rest/v1/rpc/create_family',{method:'POST',body:{p_name:'VERIFICATION MUST NOT BE CREATED'},authenticated:true})));
 await test('direct membership role changes denied',async()=>denied(await request('/rest/v1/memberships?user_id=eq.'+probeId,{method:'PATCH',body:{role:'parent'},authenticated:true})));
 await test('direct XP writes denied',async()=>denied(await request('/rest/v1/xp_events',{method:'POST',body:{},authenticated:true})));
 await test('teen approval RPC denied',async()=>denied(await request('/rest/v1/rpc/approve_submission',{method:'POST',body:{p_submission_id:randomUUID(),p_request_id:randomUUID()},authenticated:true})));
 await test('unpaired identity cannot read pairing hashes',async()=>{const r=await request('/rest/v1/invites?select=*',{authenticated:true});assert.equal(r.status,404)});
}catch(e){results.push({name:'live harness prerequisite',status:'FAIL',error:e.message});console.log('FAIL prerequisite: '+e.message)}
finally{
 if(token)try{await request('/auth/v1/logout',{method:'POST',authenticated:true})}catch{}
 token=null;probeId=null;
 const report={date:new Date().toISOString(),scope:'Real development HTTPS API; public key and one newly created unpaired anonymous verification identity. No existing user credentials or app data read.',probe:'One anonymous Auth row created, signed out after checks; no family membership or scoring rows created.',passed:results.filter(x=>x.status==='PASS').length,failed:results.filter(x=>x.status==='FAIL').length,notVerified:['Paired cross-family records','Valid concurrent parent approval','Paired identity revocation/recovery'],results};
 await fs.writeFile(path.join(workspace,'Documentation/Phase6/backend-live-public-results.json'),JSON.stringify(report,null,2));
 console.log(`RESULT ${report.passed} passed; ${report.failed} failed`);if(report.failed)process.exitCode=1;
}
