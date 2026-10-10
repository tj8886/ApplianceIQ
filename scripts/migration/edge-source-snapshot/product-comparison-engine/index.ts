import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type Json = Record<string, any>;
const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:CORS});
  if(req.method!=="POST") return reply({error:"method_not_allowed"},405);
  const auth=req.headers.get("Authorization")??"";
  if(!auth.startsWith("Bearer ")) return reply({error:"authentication_required"},401);
  let body:Json; try{body=await req.json()}catch{return reply({error:"invalid_json"},400)}

  const url=Deno.env.get("SUPABASE_URL")??"", anon=Deno.env.get("SUPABASE_ANON_KEY")??"", service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
  const userRes=await fetch(`${url}/auth/v1/user`,{headers:{Authorization:auth,apikey:anon}});
  if(!userRes.ok) return reply({error:"invalid_session"},401);
  const user=await userRes.json();

  const conversationId=body.conversation_id?String(body.conversation_id):null;
  const organizationId=body.organization_id?String(body.organization_id):null;
  let profile:isJson={};
  if(conversationId){
    const rows=await rest(url,service,`ai_conversation_memory?conversation_id=eq.${enc(conversationId)}&user_id=eq.${user.id}&select=profile`);
    profile=rows?.[0]?.profile??{};
  }
  if(isObject(body.profile)) profile={...profile,...body.profile};

  const ids=unique((Array.isArray(body.product_ids)?body.product_ids:[]).map(String).filter(Boolean));
  const models=unique((Array.isArray(body.models)?body.models:[]).map(String).filter(Boolean));
  if(ids.length+models.length<2) return reply({error:"at_least_two_products_required"},400);

  const clauses=[] as string[];
  if(ids.length) clauses.push(`id.in.(${ids.map(enc).join(",")})`);
  if(models.length) clauses.push(`model.in.(${models.map(enc).join(",")})`);
  const products=await rest(url,service,`aiq_products?or=(${clauses.join(",")})&select=*`);
  if(!products||products.length<2) return reply({error:"products_not_found",found:products?.length??0},404);

  const productIds=products.map((p:Json)=>p.id);
  const inIds=productIds.map(enc).join(",");
  const [features,dimensions,documents,images,prices,crossRefs]=await Promise.all([
    rest(url,service,`pim_product_features?product_id=in.(${inIds})&select=*&order=display_order.asc.nullslast`),
    rest(url,service,`pim_product_dimensions?product_id=in.(${inIds})&select=*`),
    rest(url,service,`pim_product_documents?product_id=in.(${inIds})&approved=eq.true&select=id,product_id,doc_type,title,file_url,verification_status,manufacturer_verified`),
    rest(url,service,`pim_product_images?product_id=in.(${inIds})&approved=eq.true&select=id,product_id,image_type,file_url,cdn_url,alt_text,is_primary,verification_status`),
    rest(url,service,`pim_retailer_prices?product_id=in.(${inIds})&select=*&order=checked_at.desc.nullslast`),
    rest(url,service,`competitive_cross_reference?select=*`)
  ]);

  const rows=products.map((p:Json)=>buildProduct(p,features??[],dimensions??[],documents??[],images??[],prices??[],profile));
  const matrix=buildMatrix(rows);
  const labels=label(rows);
  const crossReferenceMatches=findCrossReferences(products,crossRefs??[]);
  const snapshot={
    engine:"applianceiq-product-comparison-v1",
    profile_used:profile,
    products:rows,
    comparison_matrix:matrix,
    labelled_results:labels,
    cross_reference_matches:crossReferenceMatches,
    warnings:unique(rows.flatMap((r:Json)=>r.missing_information)),
    generated_at:new Date().toISOString()
  };

  let comparisonId=body.comparison_id?String(body.comparison_id):null;
  if(body.save!==false){
    const payload={organization_id:organizationId,user_id:user.id,conversation_id:conversationId,crm_record_type:body.crm_record_type??null,crm_record_id:body.crm_record_id??null,title:body.title??products.map((p:Json)=>p.model).join(" vs "),status:"active",comparison_snapshot:snapshot,selected_product_ids:productIds,winner_product_id:labels.best_overall?.product_id??null,updated_at:new Date().toISOString()};
    if(comparisonId){
      const saved=await rest(url,service,`ai_product_comparisons?id=eq.${enc(comparisonId)}&user_id=eq.${user.id}`,"PATCH",payload,true);
      if(!saved?.length) return reply({error:"comparison_not_found"},404);
    }else{
      const saved=await rest(url,service,"ai_product_comparisons","POST",payload,true);
      comparisonId=saved?.[0]?.id??null;
    }
  }

  return reply({...snapshot,comparison_id:comparisonId,result_count:rows.length});
});

type isJson=Record<string,any>;
function buildProduct(p:Json,allF:Json[],allD:Json[],allDocs:Json[],allI:Json[],allP:Json[],profile:Json){
  const f=allF.filter(x=>x.product_id===p.id), d=allD.filter(x=>x.product_id===p.id), docs=allDocs.filter(x=>x.product_id===p.id), imgs=allI.filter(x=>x.product_id===p.id), prices=allP.filter(x=>x.product_id===p.id);
  const missing:string[]=[]; const strengths:string[]=[]; const tradeoffs:string[]=[];
  const fit=fitScore(p,profile,strengths,tradeoffs,missing), budget=budgetScore(p,prices,profile,strengths,tradeoffs,missing), feature=featureScore(p,f,profile,strengths,tradeoffs,missing), data=dataScore(p,f,d,docs,missing);
  const overall=Math.round(fit*.35+budget*.25+feature*.25+data*.15);
  return {product_id:p.id,brand:p.brand_name,model:p.model,category:p.category,description:p.short_description,finish:p.finish??p.color,dimensions:{width:p.width_inches,height:p.height_inches,depth:p.depth_inches,depth_with_handles:p.depth_with_handles,capacity_cu_ft:p.capacity_cu_ft},energy_star:p.energy_star,installation:{type:p.installation_type,voltage:p.voltage,amperage:p.amperage},pricing:{msrp:p.msrp,sale_price:p.sale_price,lowest_price:p.lowest_price,currency:p.price_currency??"CAD",retailer_prices:prices.slice(0,5)},image:imgs.sort((a,b)=>Number(b.is_primary)-Number(a.is_primary))[0]?.cdn_url??imgs[0]?.file_url??null,key_features:f.filter(x=>x.is_key_feature||x.is_differentiator).slice(0,12),documents:docs.slice(0,8),component_scores:{physical_fit:fit,budget_fit:budget,required_features:feature,data_confidence:data},overall_score:overall,strengths:unique(strengths),tradeoffs:unique(tradeoffs),missing_information:unique(missing)};
}
function fitScore(p:Json,x:Json,g:string[],b:string[],m:string[]){const c:[[string,number,number]]|any=[["width",num(p.width_inches),num(x.opening_width)],["height",num(p.height_inches),num(x.opening_height)],["depth",num(p.depth_inches),num(x.opening_depth)]];const asked=c.filter((z:any)=>Number.isFinite(z[2]));if(!asked.length){m.push("opening dimensions");return 70}for(const [n,a,max] of asked){if(!Number.isFinite(a)){m.push(`${n} dimension`);continue}if(a>max){b.push(`${n} exceeds stated opening`);return 0}else g.push(`${n} fits stated opening`)}return 100}
function budgetScore(p:Json,prices:Json[],x:Json,g:string[],b:string[],m:string[]){const max=num(x.budget_max),vals=[p.sale_price,p.lowest_price,...prices.map(z=>z.price),p.msrp].map(num).filter(Number.isFinite),price=vals.length?Math.min(...vals):NaN;if(!Number.isFinite(max)){m.push("maximum budget");return Number.isFinite(price)?75:50}if(!Number.isFinite(price)){m.push("verified price");return 45}if(price>max){b.push("price exceeds budget");return 0}g.push("within budget");return price/max<=.8?100:90}
function featureScore(p:Json,f:Json[],x:Json,g:string[],b:string[],m:string[]){const req=arr(x.must_have);if(!req.length){m.push("must-have features");return 75}const h=JSON.stringify({p,f}).toLowerCase(),yes=req.filter(v=>h.includes(v.toLowerCase())),no=req.filter(v=>!h.includes(v.toLowerCase()));yes.forEach(v=>g.push(`includes ${v}`));no.forEach(v=>b.push(`not verified: ${v}`));return yes.length?Math.round(100*yes.length/req.length):0}
function dataScore(p:Json,f:Json[],d:Json[],docs:Json[],m:string[]){let s=0;const core=[p.brand_name,p.model,p.category,p.width_inches,p.height_inches,p.depth_inches,p.short_description];s+=core.filter(v=>v!=null&&v!=="").length/core.length*55;if(f.length>=5)s+=20;else m.push("complete feature set");if(d.length)s+=10;else m.push("detailed dimensions");if(docs.length)s+=10;else m.push("approved documents");if(Number(p.source_confidence)>=.8)s+=5;return Math.round(Math.min(100,s))}
function buildMatrix(rows:Json[]){const featureNames=unique(rows.flatMap(r=>r.key_features.map((f:Json)=>f.feature_name))).slice(0,30);return {core:["brand","model","finish","overall_score","energy_star"],dimensions:["width","height","depth","capacity_cu_ft"],pricing:["msrp","sale_price","lowest_price"],features:featureNames.map(name=>({name,values:Object.fromEntries(rows.map(r=>[r.product_id,r.key_features.find((f:Json)=>f.feature_name===name)?.feature_value??null]))}))}}
function label(rows:Json[]){const sorted=[...rows].sort((a,b)=>b.overall_score-a.overall_score),value=[...rows].sort((a,b)=>(b.overall_score/(priceOf(b)||1))-(a.overall_score/(priceOf(a)||1))),fit=[...rows].sort((a,b)=>b.component_scores.physical_fit-a.component_scores.physical_fit);return{best_overall:sum(sorted[0]),best_value:sum(value[0]),best_installation_fit:sum(fit[0])}}
function findCrossReferences(products:Json[],refs:Json[]){const models=new Set(products.map(p=>String(p.model).toLowerCase()));return refs.filter(r=>[1,2,3,4,5,6].some(i=>models.has(String(r[`brand${i}_model`]??"").toLowerCase()))).slice(0,20)}
function sum(x:Json){return x?{product_id:x.product_id,brand:x.brand,model:x.model,overall_score:x.overall_score}:null}
function priceOf(x:Json){return [x.pricing.sale_price,x.pricing.lowest_price,x.pricing.msrp].map(num).filter(Number.isFinite).sort((a,b)=>a-b)[0]??NaN}
async function rest(url:string,key:string,path:string,method="GET",body?:unknown,returnRows=false){const r=await fetch(`${url}/rest/v1/${path}`,{method,headers:{apikey:key,Authorization:`Bearer ${key}`,"Content-Type":"application/json",Prefer:returnRows?"return=representation":"return=minimal"},body:body===undefined?undefined:JSON.stringify(body)});const t=await r.text();if(!r.ok)throw new Error(`${method} ${path}: ${r.status} ${t}`);return t?JSON.parse(t):null}
function enc(v:string){return encodeURIComponent(v)} function num(v:any){const n=Number(v);return Number.isFinite(n)?n:NaN} function arr(v:any){return Array.isArray(v)?v.map(String).filter(Boolean):v?[String(v)]:[]} function unique<T>(v:T[]):T[]{return[...new Set(v)]} function isObject(v:any){return!!v&&typeof v==="object"&&!Array.isArray(v)} function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}})}
