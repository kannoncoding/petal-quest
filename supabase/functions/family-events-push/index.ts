// Development only. Never log tokens, credentials, payloads or FCM response bodies.
import { JWT } from "npm:google-auth-library@10.3.0";
const BASE = "https://hijtwgugzzpjjkuutyfy.supabase.co";
const PROJECT = "petal-quest-dev";
async function matchesSecret(a: string, b: string) {
  const enc = new TextEncoder();
  const values = await Promise.all([a,b].map(x => crypto.subtle.digest("SHA-256",enc.encode(x))));
  const left=new Uint8Array(values[0]),right=new Uint8Array(values[1]);let delta=0;
  for(let i=0;i<left.length;i++) delta |= left[i]^right[i];return delta===0;
}
Deno.serve(async (request: Request) => {
  const reply=(status:number,value:object)=>Response.json(value,{status});
  if(request.method!=="POST") return reply(405,{status:"method_not_allowed"});
  const secret=Deno.env.get("PETAL_FAMILY_WORKER_SECRET")||"";
  if(secret.length<32) return reply(503,{status:"not_configured"});
  if(!await matchesSecret(request.headers.get("x-petal-worker-key")||"",secret)) return reply(401,{status:"unauthorized"});
  const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")||"";
  if(Deno.env.get("SUPABASE_URL")!==BASE || !key) return reply(503,{status:"not_configured"});
  async function rpc(name:string,args:object) {
    const response=await fetch(`${BASE}/rest/v1/rpc/${name}`,{method:"POST",redirect:"error",signal:AbortSignal.timeout(15000),
      headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json"},body:JSON.stringify(args)});
    if(!response.ok) throw new Error("RPC unavailable");return await response.json();
  }
  try {
    const account=JSON.parse(Deno.env.get("PETAL_FCM_SERVICE_ACCOUNT_JSON")||"{}");
    if(account.project_id!==PROJECT || account.type!=="service_account" || typeof account.client_email!=="string" || typeof account.private_key!=="string") return reply(503,{status:"not_configured"});
    // Acquire the access token before taking bounded 90-second delivery leases.
    const client=new JWT({email:account.client_email,key:account.private_key,scopes:["https://www.googleapis.com/auth/firebase.messaging"]});
    const access=await client.getAccessToken();if(!access.token) return reply(503,{status:"push_unavailable"});
    const batch=await rpc("claim_family_event_push",{p_limit:5});let completed=0,retry=0;
    await Promise.all((batch.deliveries||[]).map(async (lease:{delivery_id:string;lease_id:string})=>{
      let success=false,invalid=false;
      try {
        // Recheck authoritative member/role/actor and current installation binding immediately before send.
        const d=await rpc("authorize_family_event_push",{p_delivery_id:lease.delivery_id,p_lease_id:lease.lease_id});
        const expiry=Date.parse(d.expires_at),ttl=Math.max(0,Math.min(604800,Math.floor((expiry-Date.now())/1000)));
        if(d.authorized && ttl>0 && typeof d.token==="string" && d.token.length<=4096 && ["review","today","results","rewards","routines","school"].includes(d.destination)) {
          const data:Record<string,string>={kind:"family_update",event_id:d.event_id,recipient_user_id:d.recipient_user_id,family_id:d.family_id,
            destination:d.destination,expires_at_epoch:String(Math.floor(expiry/1000))};
          if(d.teen_id) data.teen_id=d.teen_id;if(d.local_date) data.local_date=d.local_date;
          const response=await fetch(`https://fcm.googleapis.com/v1/projects/${PROJECT}/messages:send`,{method:"POST",redirect:"error",signal:AbortSignal.timeout(15000),
            headers:{Authorization:`Bearer ${access.token}`,"Content-Type":"application/json"},
            // Data only: client checks current account, membership and expiry before showing the generic text.
            body:JSON.stringify({message:{token:d.token,data,android:{priority:"HIGH",ttl:`${ttl}s`,collapse_key:`family-${d.event_id}`}}})});
          success=response.ok;
          if(!success && response.status===404) {
            const body=await response.json().catch(()=>null);
            invalid=body?.error?.details?.some((x:{"@type"?:string;errorCode?:string})=>x["@type"]==="type.googleapis.com/google.firebase.fcm.v1.FcmError" && x.errorCode==="UNREGISTERED")===true;
          }
          await response.body?.cancel().catch(()=>{});
        }
      } catch { /* Leave a retry receipt; never expose private response data. */ }
      const result=await rpc("complete_family_event_push",{p_delivery_id:lease.delivery_id,p_lease_id:lease.lease_id,p_success:success,p_invalid_token:invalid});
      if(result.status==="done") completed++;else retry++;
    }));
    return reply(200,{status:"processed",completed,retry});
  } catch {return reply(503,{status:"push_unavailable"});}
});
