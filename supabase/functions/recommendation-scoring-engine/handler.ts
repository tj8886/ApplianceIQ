type Json = Record<string, any>;
const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const WEIGHTS={physical_fit:30,budget_fit:20,required_features:15,lifestyle_match:10,energy_efficiency:5,installation_complexity:5,service_confidence:5,data_confidence:5,availability_freshness:5};

export function createHandler({ env, fetchImpl = fetch }: { env: (name: string) => string | undefined; fetchImpl?: typeof fetch }) {
return async(req:Request)=>{
try {
 if(req.method==="OPTIONS") return new Response("ok",{headers:CORS});
 if(req.method!=="POST") return reply({error:"method_not_allowed"},405);
 const auth=req.headers.get("Authorization")??"";
 if(!auth.startsWith("Bearer ")) return reply({error:"authentication_required"},401);
 let body:Json; try{body=await req.json(); if(!isObject(body)) throw new Error("body")}catch{return reply({error:"invalid_json"},400)}
 const url=env("SUPABASE_URL")??"", anon=env("SUPABASE_ANON_KEY")??"";
 const userRes=await fetchImpl(`${url}/auth/v1/user`,{headers:{Authorization:auth,apikey:anon}});
 if(!userRes.ok) return reply({error:"invalid_session"},401);
 const user=await userRes.json();
 const call=async (url:string,key:string,auth:string,fn:string,payload:Json)=>{try{const r=await fetchImpl(`${url}/functions/v1/${fn}`,{method:"POST",headers:{"Content-Type":"application/json",Authorization:auth,apikey:key},body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});return{ok:r.ok,data:await r.json().catch(()=>({}))}}catch{return{ok:false,data:{error:"upstream_unavailable"}}}};


 const rest=async (_url:string,_key:string,path:string,method="GET",payload?:unknown,returnRows=false)=>{
  const r=await fetchImpl(`${url}/rest/v1/${path}`,{method,headers:{apikey:anon,Authorization:auth,"Content-Type":"application/json","Accept-Profile":"tj","Content-Profile":"tj",Prefer:"return=representation"},body:payload===undefined?undefined:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
  if(!r.ok) throw new Error("scoped_data_request_failed");return r.json();
 };
 const contextResponse=await fetchImpl(`${url}/rest/v1/rpc/tj_runtime_my_platform_context`,{method:"POST",headers:{apikey:anon,Authorization:auth,"Content-Type":"application/json"},body:"{}",signal:AbortSignal.timeout(20000)});
 const context=await contextResponse.json();
 if(JSON.stringify(body).length>50000) return reply({error:"request_too_large"},400);
 if(!contextResponse.ok || !context.organization_id) return reply({error:"active_mapped_organization_required"},403);
 if(body.organization_id && body.organization_id!==context.organization_id) return reply({error:"organization_access_denied"},403);
 if(body.crm_record_type || body.crm_record_id) return reply({error:"crm_link_requires_reviewed_workflow"},400);
 const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
 if((body.conversation_id && !uuid.test(String(body.conversation_id))) || (body.comparison_id && !uuid.test(String(body.comparison_id)))) return reply({error:"invalid_record_id"},400);

 let profile=isObject(body.profile)?body.profile:{};
 const conversationId=body.conversation_id?String(body.conversation_id):null;
 if(conversationId){
   const rows=await rest(url,anon,`ai_conversation_memory?conversation_id=eq.${encodeURIComponent(conversationId)}&select=profile,recommendations,completeness_score`);
   if(!rows?.length) return reply({error:"conversation_memory_not_found"},404);
   profile={...(rows[0].profile??{}),...profile};
 }
 const query=String(body.query??body.message??"").trim();
 if(!query&&!Object.keys(profile).length) return reply({error:"query_or_profile_required"},400);
 const country=String(body.country??"CA").toUpperCase(), retailer=body.retailer_name?String(body.retailer_name):null, limit=Math.max(1,Math.min(Number(body.limit??5)||5,10));
 if(isObject(body.weights) && (Object.keys(body.weights).some(k=>!(k in WEIGHTS)) || Object.values(body.weights).some(v=>typeof v!=="number" || !Number.isFinite(v) || v<0))) return reply({error:"invalid_weights"},400);
 const weights=normalizeWeights(isObject(body.weights)?body.weights:{});
 const upstream=await call(url,anon,auth,"product-intelligence",{query,country,retailer_name:retailer,limit:Math.max(limit*2,8),filters:profileToFilters(profile)});
 if(!upstream.ok) return reply({error:"product_intelligence_failed",detail:upstream.data},502);
 const products=Array.isArray(upstream.data.products)?upstream.data.products:[];
 const scored=products.map((r:Json)=>score(r,profile,weights)).sort((a:Json,b:Json)=>b.overall_score-a.overall_score).slice(0,limit);
 const labels=assignLabels(scored), discovery=buildDiscovery(profile,scored);
 if(conversationId){
   await rest(url,anon,`ai_conversation_memory?conversation_id=eq.${encodeURIComponent(conversationId)}`,"PATCH",{recommendations:scored.map((x:Json)=>({product_id:x.product?.id,model:x.product?.model,brand:x.product?.brand_name,overall_score:x.overall_score,status:x.recommendation_status})),outstanding_questions:discovery.missing,updated_at:new Date().toISOString()});
 }
 return reply({engine:"applianceiq-recommendation-scoring-v2",conversation_id:conversationId,profile_used:profile,query,country,weights,result_count:scored.length,recommendations:scored,labelled_recommendations:labels,next_discovery_question:discovery.question,missing_profile_fields:discovery.missing,product_intelligence:{parsed_filters:upstream.data.parsed_filters??{},confidence_notes:upstream.data.confidence_notes??[]},generated_at:new Date().toISOString()});
} catch { return reply({error:"product_workflow_unavailable"},502); }
};
}

function score(row:Json,pf:Json,w:Json){const p=row.product??{},f=row.features??[],pr=row.retailer_prices??[],d=row.documents??[],dm=row.dimensions??[],good:string[]=[],bad:string[]=[],miss:string[]=[];const cs={physical_fit:fit(p,pf,good,bad,miss),budget_fit:budget(p,pr,pf,good,bad,miss),required_features:features(p,f,pf,good,bad,miss),lifestyle_match:lifestyle(p,f,pf,good,miss),energy_efficiency:energy(p,pf,good,miss),installation_complexity:install(p,dm,good,bad,miss),service_confidence:service(p,d,good,miss),data_confidence:dataConf(p,f,dm,d,good,miss),availability_freshness:availability(p,pr,good,miss)};const overall=Object.entries(cs).reduce((s,[k,v])=>s+Number(v)*w[k]/100,0), hard=cs.physical_fit===0||cs.budget_fit===0||cs.required_features===0;return{product:p,overall_score:Math.round(overall),recommendation_status:hard?"not_recommended":overall>=85?"strong_match":overall>=70?"good_match":overall>=55?"possible_match":"weak_match",component_scores:cs,strengths:unique(good),tradeoffs:unique(bad),missing_information:unique(miss),confidence_score:Math.round(cs.data_confidence*.55+cs.availability_freshness*.25+cs.service_confidence*.2),retailer_prices:pr}}
function fit(p:Json,x:Json,g:string[],b:string[],m:string[]){const c=[["width",num(p.width_inches),num(x.opening_width??x.max_width)],["height",num(p.height_inches),num(x.opening_height??x.max_height)],["depth",num(p.depth_inches),num(x.opening_depth??x.max_depth)]];const r=c.filter(z=>Number.isFinite(z[2]));if(!r.length){m.push("opening dimensions");return 70}let pass=0;for(const [n,a,max] of r as any){if(!Number.isFinite(a)){m.push(`${n} dimension`);continue}if(a<=max){pass++;g.push(`${n} fits the stated limit`)}else b.push(`${n} exceeds the stated limit by ${(a-max).toFixed(2)} in`)}if(r.some((z:any)=>Number.isFinite(z[1])&&z[1]>z[2]))return 0;return Math.round(70+30*pass/r.length)}
function budget(p:Json,pr:Json[],x:Json,g:string[],b:string[],m:string[]){const max=num(x.budget_max??x.max_price),vals=[p.sale_price,p.lowest_price,...pr.map(z=>z.price),p.msrp].map(num).filter(Number.isFinite),price=vals.length?Math.min(...vals):NaN;if(!Number.isFinite(max)){m.push("maximum budget");return Number.isFinite(price)?75:55}if(!Number.isFinite(price)){m.push("verified price");return 45}if(price>max){b.push(`price exceeds budget by ${Math.round(price-max)}`);return 0}g.push("price is within budget");const r=price/max;return r<=.8?100:r<=.95?90:80}
function features(p:Json,f:Json[],x:Json,g:string[],b:string[],m:string[]){const req=arr(x.must_have??x.required_features);if(!req.length){m.push("must-have features");return 75}const h=JSON.stringify({p,f}).toLowerCase(),yes=req.filter(v=>h.includes(v.toLowerCase())),no=req.filter(v=>!h.includes(v.toLowerCase()));yes.forEach(v=>g.push(`includes requested feature: ${v}`));no.forEach(v=>b.push(`requested feature not verified: ${v}`));return yes.length?Math.round(100*yes.length/req.length):0}
function lifestyle(p:Json,f:Json[],x:Json,g:string[],m:string[]){const terms=arr(x.use_cases??x.preferences),hh=num(x.household_size),h=JSON.stringify({p,f}).toLowerCase();let s=65;if(!terms.length&&!Number.isFinite(hh))m.push("household or lifestyle needs");for(const t of terms)if(h.includes(t.toLowerCase())){s+=8;g.push(`supports lifestyle need: ${t}`)}if(Number.isFinite(hh)&&Number.isFinite(num(p.capacity_cu_ft))&&hh>=5&&num(p.capacity_cu_ft)>=24){s+=15;g.push("capacity suits a larger household")}return Math.min(100,s)}
function energy(p:Json,x:Json,g:string[],m:string[]){if(p.energy_star===true){g.push("ENERGY STAR certified");return 100}if(x.energy_star===true)return 35;if(p.energy_star==null)m.push("energy certification");return p.energy_star===false?60:50}
function install(p:Json,d:Json[],g:string[],b:string[],m:string[]){let s=75;if(p.voltage){s+=5;g.push("electrical requirement is documented")}else m.push("electrical requirement");if(p.installation_type){s+=5;g.push("installation type is documented")}else m.push("installation type");if(d.length){s+=10;g.push("detailed installation dimensions are available")}else m.push("detailed installation dimensions");if(Number(p.lead_time_days)>30){s-=10;b.push("long stated lead time")}return Math.max(0,Math.min(100,s))}
function service(p:Json,d:Json[],g:string[],m:string[]){const t=d.map(z=>String(z.doc_type??"").toLowerCase());let s=45;if(t.some(v=>v.includes("warranty"))){s+=25;g.push("approved warranty document is available")}else m.push("approved warranty document");if(t.some(v=>v.includes("service")||v.includes("parts")))s+=20;if(p.source_review_status==="approved")s+=10;return Math.min(100,s)}
function dataConf(p:Json,f:Json[],d:Json[],docs:Json[],g:string[],m:string[]){const core=[p.brand_name,p.model,p.category,p.width_inches,p.height_inches,p.depth_inches,p.short_description],complete=core.filter(v=>v!=null&&v!=="").length/core.length;let s=complete*60;if(f.length>=5)s+=15;else m.push("complete feature set");if(d.length)s+=10;if(docs.length)s+=10;if(Number(p.source_confidence)>=80){s+=5;g.push("source confidence is high")}return Math.round(Math.min(100,s))}
function availability(p:Json,pr:Json[],g:string[],m:string[]){if(!pr.length){m.push("retailer stock and current pricing");return 50}const stock=pr.some(z=>z.in_stock===true),dates=pr.map(z=>new Date(z.checked_at).getTime()).filter(Number.isFinite);let s=stock?80:50;if(stock)g.push("retailer stock is reported available");if(dates.length){const days=(Date.now()-Math.max(...dates))/86400000;s+=days<=3?20:days<=14?10:days>45?-20:0}return Math.max(0,Math.min(100,s))}
function assignLabels(a:Json[]){if(!a.length)return{};const q=a.filter(x=>x.recommendation_status!=="not_recommended");if(!q.length)return{};return{best_overall:summary(q[0]),best_value:summary(q.filter(x=>price(x)>0).sort((x,y)=>value(y)-value(x))[0]),best_installation_fit:summary(q.filter(x=>!x.missing_information.some((m:string)=>/dimension/.test(m))).sort((x,y)=>y.component_scores.physical_fit-x.component_scores.physical_fit)[0]),premium_choice:summary(q.filter(x=>price(x)>0).sort((x,y)=>price(y)-price(x))[0]),best_long_term_value:summary([...q].sort((x,y)=>longTerm(y)-longTerm(x))[0])}}
function buildDiscovery(p:Json,a:Json[]){const q=[["category","Which appliance category are you shopping for?"],["budget_max","What is the maximum budget for this appliance?"],["opening_width","What is the maximum opening width?"],["opening_height","What is the maximum opening height?"],["opening_depth","What is the maximum acceptable depth?"],["must_have","Which features are absolute must-haves?"],["finish","Which finish or colour is preferred?"],["household_size","How many people will regularly use this appliance?"]];const x=q.filter(([k])=>p[k]==null||p[k]===""||(Array.isArray(p[k])&&!p[k].length));return{question:x[0]?.[1]??null,missing:unique([...x.map(z=>z[0]),...a.flatMap(z=>z.missing_information??[])]).slice(0,15)}}
function profileToFilters(p:Json){return{category:p.category??null,brand:p.brand??p.preferred_brands?.[0]??null,max_price:p.budget_max??p.max_price??null,max_width:p.opening_width??p.max_width??null,max_height:p.opening_height??p.max_height??null,max_depth:p.opening_depth??p.max_depth??null,finish:p.finish??null,energy_star:p.energy_star??null,installation_type:p.installation_type??null,required_terms:arr(p.must_have),excluded_terms:arr(p.deal_breakers)}}

function normalizeWeights(raw:Json){const m={...WEIGHTS,...raw},t=Object.values(m).reduce((a:any,b:any)=>a+Number(b||0),0)||100;return Object.fromEntries(Object.entries(m).map(([k,v])=>[k,Number((Number(v||0)*100/t).toFixed(2))]))}
function value(x:Json){const p=price(x);return x.overall_score+(p>0?Math.max(0,25-Math.log10(p)*5):0)}function longTerm(x:Json){return x.overall_score*.5+x.component_scores.service_confidence*.25+x.component_scores.data_confidence*.15+x.component_scores.energy_efficiency*.1}function price(x:Json){const p=x.product??{},v=[p.sale_price,p.lowest_price,p.msrp].map(num).filter(Number.isFinite);return v.length?Math.min(...v):-1}function summary(x:Json){return x?{model:x.product?.model,brand:x.product?.brand_name,overall_score:x.overall_score,confidence_score:x.confidence_score,recommendation_status:x.recommendation_status}:null}function num(v:any){if(v==null || v==="" || typeof v==="boolean") return NaN;const n=Number(v);return Number.isFinite(n)?n:NaN}function arr(v:any){return Array.isArray(v)?v.map(String).filter(Boolean):v?[String(v)]:[]}function unique<T>(v:T[]):T[]{return[...new Set(v)]}function isObject(v:any):v is Json{return!!v&&typeof v==="object"&&!Array.isArray(v)}function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}})}
