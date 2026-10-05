const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, content-type, x-client-info, apikey','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const json=(b:unknown,status=200)=>new Response(JSON.stringify(b),{status,headers:cors});
const esc=(s:unknown)=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export function createHandler({createClient,env,loadEnvironment=async(e:any)=>e,fetchImpl=fetch}:{createClient:any;env:any;loadEnvironment?:any;fetchImpl?:typeof fetch}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({ok:false,error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return json({ok:false,error:'not_authenticated'},401);
  try{
   const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}}});const {data,error}=await caller.auth.getUser();if(error||!data?.user||data.user.is_anonymous)return json({ok:false,error:'not_authenticated'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>4096)return json({ok:false,error:'body_too_large'},413);let body:any;try{body=JSON.parse(raw);}catch{return json({ok:false,error:'bad_json'},400);}
   if(typeof body?.invite_code!=='string'||!body.invite_code||body.invite_code.length>128)return json({ok:false,error:'missing_fields'},400);
   let {data:invite,error:denied}=await caller.rpc('tj_invite_delivery_context',{p_code:body.invite_code,p_reserve:false});if(denied)return json({ok:false,error:denied.code==='42501'?'forbidden':'invite_not_available'},denied.code==='42501'?403:404);
   // The registered admin application is the only invitation destination. Request-provided names, roles and origins are ignored.
   const accept_url='https://applianceiq-intelligence-group.netlify.app/admin.html#invite='+encodeURIComponent(invite.invite_code);
   const config=await loadEnvironment(env),key=config('RESEND_API_KEY');if(!key)return json({ok:true,sent:false,reason:'no_mail_provider',accept_url});
   const {data:reservation,error:failure}=await caller.rpc('tj_invite_delivery_context',{p_code:body.invite_code,p_reserve:true});if(failure)return json({ok:false,error:'invite_not_available'},403);if(!reservation.reserved)return json({ok:true,sent:false,reason:'recent_attempt',accept_url});
   invite=reservation;
   const label=invite.role==='owner'?'Owner':invite.role==='admin'?'Administrator':'Team Member';
   const html=`<h1>You're invited to join ${esc(invite.org_name)}</h1><p>${esc(invite.inviter_email||'An administrator')} invited you as ${label}.</p><p><a href="${esc(accept_url)}">Accept invitation</a></p><p>Expires ${esc(invite.expires_at)}.</p>`;
   const payload={from:config('INVITE_FROM_EMAIL')||'ApplianceIQ <onboarding@resend.dev>',to:[invite.invited_email],subject:`You're invited to join ${String(invite.org_name).replace(/[\r\n]/g,' ')} on ApplianceIQ`,html};
   const digest=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(payload))))).map(x=>x.toString(16).padStart(2,'0')).join('');
   let sent=false;try{sent=(await fetchImpl('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','Idempotency-Key':'aiq-invite/'+digest},body:JSON.stringify(payload),signal:AbortSignal.timeout(15000)})).ok;}catch{}
   return json({ok:true,sent,...(!sent?{reason:'mail_error'}:{}),accept_url});
  }catch{return json({ok:false,error:'invite_delivery_failed'},500);}
 };
}
