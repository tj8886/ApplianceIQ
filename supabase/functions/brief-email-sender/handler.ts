const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors});
const number=(v:unknown)=>v===null||v===undefined||v===''||typeof v==='boolean'||!Number.isFinite(Number(v))?'unknown':Number(v).toLocaleString('en-CA');
export function briefText(b:any){
 const list=(value:any)=>Array.isArray(value)?value.slice(0,100):[];
 return ['APPLIANCEIQ '+String(b.brief_type??'daily').toUpperCase()+' BRIEF — '+b.brief_date,'','HEADLINE: '+b.headline,'',b.executive_summary,'',
 'WORKLOAD: '+number(b.workload?.open)+' active, '+number(b.workload?.blocked)+' blocked, '+number(b.workload?.overdue)+' overdue, '+number(b.workload?.completed_7d)+' completed this week',
 'FINANCIAL EXPOSURE (CAD): '+number(b.financial_exposure_cad),'','TOP PRIORITIES:',list(b.priorities).map((p:any)=>'• '+p.title+' ('+p.severity+', impact CAD '+number(p.financial_impact_cad)+')').join('\n')||'(none)',
 '','RISKS & BLOCKERS:',list(b.risks).map((r:any)=>'• '+r.title+' — '+r.status+(r.due_at?', due '+String(r.due_at).slice(0,10):'')).join('\n')||'(none)',
 '','RECENT WINS:',list(b.wins).map((w:any)=>'• '+w.title+(w.completed_at?' ('+String(w.completed_at).slice(0,10)+')':'')).join('\n')||'(none)',
 '','View full brief: https://applianceiq-command-center.netlify.app/briefs.html','ApplianceIQ Intelligence Group'].join('\n');
}
export function createHandler({createClient,env,loadEnvironment=async(e:any)=>e,fetchImpl=fetch}:{createClient:any;env:(n:string)=>string|undefined;loadEnvironment?:any;fetchImpl?:typeof fetch}){
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});if(req.method!=='POST')return json({error:'method_not_allowed'},405);
  const auth=req.headers.get('Authorization')??'';if(!/^Bearer \S+$/i.test(auth))return json({error:'auth_required'},401);
  try{
   const caller=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:auth}}});const {data,error}=await caller.auth.getUser();if(error||!data?.user||data.user.is_anonymous)return json({error:'auth_required'},401);
   const raw=await req.text();if(new TextEncoder().encode(raw).length>8192)return json({error:'body_too_large'},413);let body:any;try{body=JSON.parse(raw);}catch{return json({error:'invalid_json'},400);}
   if(!body||Array.isArray(body)||typeof body!=='object'||typeof body.organization_id!=='string'||!Array.isArray(body.recipients??[]))return json({error:'invalid_request'},400);
   const {data:context,error:scope}=await caller.rpc('tj_brief_delivery_context',{p_org:body.organization_id,p_brief:body.brief_id??null,p_recipients:body.recipients??[]});
   if(scope)return json({error:scope.code==='42501'?'not_authorized':scope.code==='P0002'?'no_brief_found':'invalid_delivery_request'},scope.code==='42501'?403:scope.code==='P0002'?404:400);
   if(!context?.brief?.id||!Array.isArray(context.recipients)||!context.recipients.length||context.recipients.length>20)return json({error:'invalid_delivery_context'},500);
   const configured=await loadEnvironment(env);const key=configured('RESEND_API_KEY');if(!key)return json({error:'resend_api_key_not_configured'},503);
   const from=configured('EMAIL_FROM')??'ApplianceIQ <onboarding@resend.dev>';const text=briefText(context.brief);if(text.length>100000)return json({error:'brief_too_large'},400);
   const subject='[ApplianceIQ] '+(context.brief.brief_type==='morning'?'Morning Brief':context.brief.brief_type==='eod'?'End of Day':'Weekly Review')+' — '+context.brief.brief_date;
   const deadline=Date.now()+25000;let sent=0,failed=0;const errors:string[]=[];
   for(const to of context.recipients){
    if(Date.now()>=deadline){failed++;errors.push('delivery_budget_exceeded');continue;}
    const bytes=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify({brief:context.brief.id,from,to,subject,text})));
    const hash=Array.from(new Uint8Array(bytes),v=>v.toString(16).padStart(2,'0')).join('');
    try{const r=await fetchImpl('https://api.resend.com/emails',{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+key,'Idempotency-Key':'aiq-brief/'+hash},body:JSON.stringify({from,to:[to],subject,text}),signal:AbortSignal.timeout(Math.max(1,Math.min(10000,deadline-Date.now())))});if(r.ok)sent++;else{failed++;errors.push('provider_rejected');}await r.body?.cancel();}catch{failed++;errors.push('provider_unavailable');}
   }
   const service=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'));const {error:commit}=await service.rpc('aiq_finish_brief_delivery',{p_native:data.user.id,p_org:body.organization_id,p_brief:context.brief.id,p_recipients:context.recipients,p_sent:sent,p_failed:failed});
   if(commit)return json({ok:false,error:'delivery_status_commit_failed',sent,failed},500);
   return json({ok:true,sent,failed,provider_accepted:sent,errors:errors.length?errors:undefined});
  }catch{return json({error:'brief_delivery_failed'},500);}
 };
}
