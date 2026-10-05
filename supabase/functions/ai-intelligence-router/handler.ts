import {classifyComplexity,route,memoryContext,memorySummary} from './routing.ts';
import {deterministicEvidence,crossAppContext} from './evidence.ts';
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json'};
export function createHandler({createClient,env,fetchImpl=fetch}:{createClient:any;env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}){
 const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers});
 return async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers});if(req.method!=='POST')return reply({ok:false,detail:'method_not_allowed'},405);
  const authorization=req.headers.get('Authorization')??'';if(!authorization.startsWith('Bearer '))return reply({ok:false,detail:'authentication_required'},401);
  try{
   const url=env('SUPABASE_URL')??'',anon=env('SUPABASE_ANON_KEY')??'';
   const user=createClient(url,anon,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
   const identity=await user.auth.getUser();if(identity.error||!identity.data?.user)return reply({ok:false,detail:'invalid_session'},401);
   const ctx=await user.rpc('tj_runtime_my_platform_context');if(ctx.error||!ctx.data?.organization_id||!ctx.data.source_user_id)return reply({ok:false,detail:'active_mapped_organization_required'},403);
   const raw=await req.text();if(raw.length>65536)return reply({ok:false,detail:'request_too_large'},413);
   let body;try{body=JSON.parse(raw);}catch{return reply({ok:false,detail:'invalid_json'},400);}
   if(!body||typeof body!=='object'||Array.isArray(body))return reply({ok:false,detail:'invalid_json'},400);
   const message=typeof body.message==='string'?body.message.trim():'';const history=body.history??[];const country=String(body.country??'CA').toUpperCase();const max=body.max_specialists??3;
   if(message.length<3||message.length>12000||!Array.isArray(history)||history.length>20||history.some(h=>!h||!['user','assistant','ai'].includes(h.role)||typeof (h.text??h.content)!=='string'||String(h.text??h.content).length>8000)||!['CA','US'].includes(country)||!Number.isInteger(max)||max<1||max>4||body.model_tier&&!['fast','standard','strong'].includes(body.model_tier))return reply({ok:false,detail:'invalid_request'},400);
   const org=body.organization_id??ctx.data.organization_id;if(typeof org!=='string'||! /^[0-9a-f-]{36}$/i.test(org))return reply({ok:false,detail:'invalid_organization'},400);
   const db=user.schema('tj');
   const call=async(slug:string,payload:unknown)=>{
    const r=await fetchImpl(url+'/functions/v1/'+slug,{method:'POST',headers:{'Content-Type':'application/json',Authorization:authorization,apikey:anon},body:JSON.stringify(payload),signal:AbortSignal.timeout(90000)});
    const data=await r.json();return {ok:r.ok&&data.ok!==false,data,status:r.status};
   };
   const memory=await call('conversation-memory-engine',{message,conversation_id:body.conversation_id??null,organization_id:org,crm_record_type:body.crm_record_type??null,crm_record_id:body.crm_record_id??null,title:body.title??null});
   if(!memory.ok)return reply({ok:false,detail:'conversation_memory_failed'},memory.status===403?403:memory.status===409?409:memory.status===400?400:502);
   const cid=memory.data.conversation_id;const complexity=classifyComplexity(message,history.length);const tier=body.model_tier??complexity.tier;
   const admin=createClient(url,env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false,autoRefreshToken:false}});
   const persist=async(answer:string,persona:string,metadata:Record<string,unknown>)=>{
    const r=await admin.rpc('aiq_append_router_assistant_turn',{p_conversation_id:cid,p_target_user_id:identity.data.user.id,p_expected_version:memory.data.memory_version,p_content:answer,p_persona:persona,p_metadata:metadata});
    if(r.error)throw Object.assign(new Error('assistant_turn_failed'),{code:r.error.code});
   };
   const base={engine:'applianceiq-intelligence-router-us',conversation_id:cid,memory:memorySummary(memory.data)};
   if(complexity.deterministic&&complexity.deterministicType&&!body.persona_id&&body.mode!=='manual'){
    const evidence=await deterministicEvidence(complexity.deterministicType,message,db,country);
    const persona=['recall','contact','warranty','map_policy'].includes(complexity.deterministicType)?'Katrina':complexity.deterministicType==='installation'?'Asher':complexity.deterministicType==='selling_angles'?'TJ':'Natalie';
    await persist(evidence.data,persona,{tier:'deterministic',source:evidence.source,deterministic_type:complexity.deterministicType});
    return reply({...base,ok:evidence.ok,mode:'deterministic',answer:evidence.data,primary_persona:persona,complexity:{tier:'deterministic',auto_detected:complexity.tier,reason:complexity.reason,deterministic_type:complexity.deterministicType},model_used:{provider:'none',model:'deterministic'},cost_estimate_usd:0,data_source:evidence.source,recommendation_scoring_used:false,specialists:[]});
   }
   const personaResult=await db.from('ai_personas').select('id,persona_name,persona_role,organization_id').eq('active',true).limit(50);
   if(personaResult.error)return reply({...base,ok:false,detail:'personas_unavailable'},503);
   const personas=(personaResult.data??[]).filter((p:any)=>!p.organization_id||p.organization_id===org);
   const routing=route(message,max);const manual=body.mode==='manual'||!!body.persona_id;
   const selected=manual?personas.filter((p:any)=>body.persona_id?p.id===body.persona_id:p.persona_name===body.persona_name):routing.personas.map(name=>personas.find((p:any)=>p.persona_name===name)).filter(Boolean);
   if(!selected.length)return reply({...base,ok:false,detail:'persona_not_available'},403);
   let scoring:any=null;
   if(routing.productIntent&&memory.data.recommendation_ready){const scored=await call('recommendation-scoring-engine',{query:message,conversation_id:cid,profile:memory.data.profile,country,retailer_name:body.retailer_name??null,limit:5});if(!scored.ok)return reply({...base,ok:false,detail:'recommendation_scoring_failed'},503);scoring=scored.data;}
   const ecosystem=await crossAppContext(message,db,org,ctx.data.source_user_id,user);
   const reported=memoryContext(memory.data,scoring);
   const coachMessage=(message+'\n\n'+reported+'\n'+ecosystem);
   // Preserve the user's message and explicitly flag any bounded evidence preview.
   const bounded=coachMessage.length>16000?coachMessage.slice(0,15920)+'\n[Evidence preview truncated; do not infer omitted details.]':coachMessage;
   const results=await Promise.all(selected.map(async(p:any)=>{const r=await call('ai-team-coach',{organization_id:org,persona_id:p.id,message:bounded,history:history.slice(-10).map(h=>({role:h.role==='user'?'user':'assistant',text:String(h.text??h.content)})),model_tier:tier});return {persona:p.persona_name,role:p.persona_role,ok:r.ok,answer:r.data.answer??'',detail:r.ok?undefined:'specialist_unavailable',model_used:r.data.model_used??null,status:r.status};}));
   const good=results.filter(r=>r.ok&&r.answer);if(!good.length)return reply({...base,ok:false,detail:'all_specialists_failed',specialists:results},results.every(r=>r.status===503)?503:502);
   const answer=good.length===1?good[0].answer:good.map(r=>'**'+r.persona+'**\n'+r.answer).join('\n\n');
   await persist(answer,manual?good[0].persona:routing.primary,{tier,personas_used:good.map(r=>r.persona),source_app:String(body.metadata?.source_app??'unknown').slice(0,120)});
   return reply({...base,ok:true,mode:manual?'manual':'auto',answer,primary_persona:manual?good[0].persona:routing.primary,routed_personas:good.map(r=>r.persona),routing_reason:routing.reason,complexity:{tier,auto_detected:complexity.tier,reason:complexity.reason},model_used:good[0].model_used,cost_estimate_usd:null,recommendation_scoring_used:!!scoring,recommendation_scoring:scoring?{result_count:scoring.result_count,labelled_recommendations:scoring.labelled_recommendations,next_discovery_question:scoring.next_discovery_question}:null,specialists:results});
  }catch(e){return reply({ok:false,detail:(e as any)?.code==='40001'?'conversation_changed':'router_failed'},(e as any)?.code==='40001'?409:503);}
 };
}
