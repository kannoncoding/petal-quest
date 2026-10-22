// Credentials enter only through the private stdin pipe; never emit response bodies.
const parts=[];for await(const c of process.stdin)parts.push(c);
let input;try{input=JSON.parse(Buffer.concat(parts).toString('utf8'));}catch{process.exit(1);}parts.length=0;
try{
 if(input.projectUrl!=='https://hijtwgugzzpjjkuutyfy.supabase.co'||input.operation!=='save_reflection_note')throw Error();
 const r=await fetch(input.projectUrl+'/rest/v1/rpc/'+input.operation,{method:'POST',headers:{apikey:input.publishableKey,Authorization:'Bearer '+input.access_token,'Content-Type':'application/json'},body:JSON.stringify(input.args),redirect:'error',signal:AbortSignal.timeout(25000)});
 input.access_token='';const data=await r.json();if(!r.ok)throw Error();
 // The first process intentionally discards its successful application receipt.
 // The replacement process emits only the stable identity/version, never note text.
 if(input.mode==='discard')console.log(JSON.stringify({completed:true,pid:process.pid}));
 else console.log(JSON.stringify({completed:true,pid:process.pid,id:data.id,version:data.version,request_id:data.request_id}));
}catch{console.log(JSON.stringify({completed:false}));process.exitCode=1;}finally{if(input)input.access_token='';}
