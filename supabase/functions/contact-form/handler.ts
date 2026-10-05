const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
export const escapeHtml=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function createHandler({createClient,env,loadEnvironment=async(e:any)=>e,fetchImpl=fetch}:{createClient:any;env:(n:string)=>string|undefined;loadEnvironment?:any;fetchImpl?:typeof fetch}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({error:'POST only'},405);
  try{
   const raw=await req.text();if(new TextEncoder().encode(raw).length>16384)return json({error:'body_too_large'},413);let body:any;try{body=JSON.parse(raw);}catch{return json({error:'invalid_json'},400);}
   if(!body||Array.isArray(body)||typeof body!=='object'||typeof body.name!=='string'||typeof body.email!=='string')return json({error:'Name and email are required'},400);
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'));const {data,error}=await service.rpc('aiq_submit_contact',{p_body:body});
   if(error)return json({error:error.code==='P0001'?'Please try again later':error.code==='22023'?'Invalid contact details':'Failed to save submission'},error.code==='P0001'?429:error.code==='22023'?400:500);
   if(!data?.id)return json({error:'Failed to save submission'},500);
   let notification='not_configured';
   if(!data.duplicate){try{
    const configured=await loadEnvironment(env);const key=configured('RESEND_API_KEY');
    if(key){const html='<div><h2>New Demo Request</h2><p>Name: '+escapeHtml(body.name)+'</p><p>Email: '+escapeHtml(body.email)+'</p><p>Company: '+escapeHtml(body.company||'Not provided')+'</p><p>Role: '+escapeHtml(body.role||'Not specified')+'</p><p>Message:</p><pre>'+escapeHtml(body.message||'No message provided')+'</pre></div>';
     const r=await fetchImpl('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+key,'Idempotency-Key':'aiq-contact/'+data.id},body:JSON.stringify({from:configured('RESEND_FROM_EMAIL')??'ApplianceIQ <onboarding@resend.dev>',to:['tjrobar5@gmail.com'],subject:('New Demo Request: '+body.name+' from '+(body.company||'Unknown Company')).replace(/[\r\n]/g,' ').slice(0,240),html}),signal:AbortSignal.timeout(10000)});notification=r.ok?'accepted':'failed';await r.body?.cancel();}
   }catch{notification='failed';}}
   return json({success:true,id:data.id,notification:data.duplicate?'duplicate_not_resent':notification});
  }catch{return json({error:'Submission failed'},500);}
 };
}
