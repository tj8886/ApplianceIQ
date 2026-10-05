// ai-team-coach v9 — embedQuery uses gemini-embedding-001 @ 1024 dims to match column + search function
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
const MODELS={fast:{provider:"openai",name:Deno.env.get("AI_MODEL_FAST")??"gpt-5.6-luna",maxTok:800},standard:{provider:"anthropic",name:Deno.env.get("AI_MODEL")??"claude-sonnet-4-6",maxTok:1500},strong:{provider:"anthropic",name:Deno.env.get("AI_MODEL_HEAVY")??"claude-sonnet-4-6",maxTok:2500}} as const;
const COST_PER_M:Record<string,{input:number;output:number}>={"gpt-5.6-luna":{input:0.20,output:1.20},"gpt-4.1-mini":{input:0.40,output:1.60},"gpt-4.1-nano":{input:0.10,output:0.40},"claude-sonnet-4-6":{input:3.00,output:15.00},"claude-haiku-4-5":{input:0.80,output:4.00},"claude-opus-4-8":{input:15.00,output:75.00}};
const ASSISTANT_KEY="aiq_team_coach",MAX_CHUNKS=16,MAX_BRANDS=3;
type Json=Record<string,unknown>;type SB=any;type ModelTier="fast"|"standard"|"strong";
const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const CATEGORY_MAP:Record<string,string[]>={"Ranges":["range","stove","oven range","slide-in","freestanding range","electric range","gas range","induction range","dual fuel"],"Dishwashers":["dishwasher","dishwash"],"Refrigerators":["fridge","refrigerator","french door","side-by-side","counter-depth","freezer"],"Laundry":["washer","dryer","laundry","washing machine","front load","top load"],"Cooktops":["cooktop","rangetop","induction cooktop","gas cooktop"],"Wall Ovens":["wall oven","double oven","single oven","speed oven"],"Ventilation":["hood","vent hood","range hood","ventilation"],"Microwaves":["microwave","over-the-range"]};
function detectCategory(text:string):string|null{const l=text.toLowerCase();for(const[cat,kws]of Object.entries(CATEGORY_MAP)){if(kws.some(k=>l.includes(k)))return cat}return null}
function detectComplexity(msg:string,hLen:number):ModelTier{
  const l=msg.toLowerCase(),w=msg.split(/\s+/).length;
  const strong=["analyze","analysis","coaching session","score my","evaluate my","role-play","roleplay","transcript","performance review","post-mortem","lost the sale","won the sale","management coaching","training module","compare my performance","what did i do wrong","deep dive","seven steps","11 steps","steps of selling"];
  if(strong.some(s=>l.includes(s)))return"strong";
  const std=["explain why","help me understand","what should i say","objection","how do i handle","how would you","difficult customer","recommend","suggestion","which is better","compare","comparison","versus","vs "," vs.","pros and cons","write me","draft a","create a","what's the difference","difference between","should i","side by side","head to head","which one","better for","good better best","step up","upgrade from","model comparison","sell against","selling point","how to sell","pitch for","closing","follow up","follow-up","email for","script for"];
  if(std.some(s=>l.includes(s)))return"standard";
  if(w>80||hLen>8)return"standard";
  if(hLen>2)return"standard";
  return"fast";
}
async function embedQuery(text:string):Promise<number[]|null>{
  const apiKey=Deno.env.get("GOOGLE_API_KEY")??"";
  if(!apiKey)return null;
  try{
    const r=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent?key=${apiKey}`,{
      method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({model:"models/gemini-embedding-001",content:{parts:[{text:text.slice(0,7000)}]},outputDimensionality:1024})
    });
    if(!r.ok)return null;
    const d=await r.json();
    return d.embedding?.values??null;
  }catch{return null}
}
Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
  if(req.method!=="POST")return json({ok:false,detail:"method_not_allowed"},405);
  const authHeader=req.headers.get("Authorization")??"";
  if(!authHeader.startsWith("Bearer "))return json({ok:false,detail:"authentication_required"},401);
  let body:Json;try{body=await req.json()}catch{return json({ok:false,detail:"invalid_json_body"},400)}
  const organizationId=body.organization_id?String(body.organization_id):null;
  const personaId=body.persona_id?String(body.persona_id):null;
  const message=String(body.message??"").trim();
  const history=Array.isArray(body.history)?body.history as Array<{role:string;text:string}>:[];
  if(!personaId||message.length<1)return json({ok:false,detail:"persona_id_and_message_required"},400);
  const requestedTier=body.model_tier?String(body.model_tier) as ModelTier:null;
  const autoTier=detectComplexity(message,history.length);
  const primaryTier:ModelTier=requestedTier&&(requestedTier in MODELS)?requestedTier:autoTier;
  const supabaseUrl=Deno.env.get("SUPABASE_URL")??"",serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"",anonKey=Deno.env.get("SUPABASE_ANON_KEY")??"";
  const userClient=createClient(supabaseUrl,anonKey,{global:{headers:{Authorization:authHeader}}});
  const admin=createClient(supabaseUrl,serviceKey);
  const{data:persona}=await admin.from("ai_personas").select("id,persona_name,persona_role,avatar_emoji,tone,specialization,personality_traits,prompt_prefix,active,organization_id").eq("id",personaId).eq("active",true).maybeSingle();
  if(!persona)return json({ok:false,detail:"persona_not_found"},404);
  const{data:gov,error:govErr}=await userClient.rpc("ai_submit_request",{p_organization_id:organizationId,p_assistant_key:ASSISTANT_KEY,p_prompt:message,p_context:{persona_id:personaId,persona_name:persona.persona_name,history_length:history.length,model_tier:primaryTier}});
  if(govErr){const msg=govErr.message??"governance_rejected";return json({ok:false,detail:msg},/denied|Authentication/i.test(msg)?403:400)}
  const requestId=gov?.request_id as string,orgId=gov?.organization_id as string;

  let rankedChunks:Json[]=[];
  let retrievalMode="keyword";
  const queryVec=await embedQuery(message+" "+history.slice(-2).filter(h=>h.role==="user").map(h=>h.text).join(" "));
  if(queryVec){
    try{
      const{data:semChunks}=await admin.rpc("search_knowledge_semantic",{query_embedding:JSON.stringify(queryVec),match_count:MAX_CHUNKS,org_filter:orgId});
      if(semChunks?.length){rankedChunks=semChunks.map((c:Json)=>({...c,score:Math.round(((c.similarity as number)??0)*10)}));retrievalMode="semantic"}
    }catch{}
  }
  if(!rankedChunks.length){
    const{data:chunks}=await admin.from("ai_knowledge_chunks").select("chunk_key,title,content,citation,organization_id,metadata").eq("status","active").or(`organization_id.eq.${orgId},organization_id.is.null`).limit(500);
    const terms=new Set(message.toLowerCase().split(/[^a-z0-9]+/).filter(t=>t.length>3));
    for(const h of history.slice(-3)){if(h.role==="user")for(const t of h.text.toLowerCase().split(/[^a-z0-9]+/).filter(t=>t.length>3))terms.add(t)}
    const personaName=String(persona.persona_name).toLowerCase();
    rankedChunks=(chunks??[]).map((c:Json)=>{
      const text=`${c.title??""} ${c.content??""}`.toLowerCase();
      let score=0;for(const t of terms)if(text.includes(t))score++;
      const meta=c.metadata as Record<string,any>??{};
      if(meta.persona&&String(meta.persona).toLowerCase()===personaName)score+=2;
      if(meta.priority==="critical")score+=1;
      const isCompareQ=[...terms].some(t=>["compare","comparison","versus","difference","better"].includes(t));
      if(isCompareQ&&(meta.category==="competitive_comparison"||meta.category==="methodology"))score+=3;
      return{...c,score};
    }).sort((a:Json,b:Json)=>(b.score as number)-(a.score as number)).slice(0,MAX_CHUNKS);
  }

  const livePimData=await fetchLivePimContext(admin,message,history);
  const systemPrompt=buildSystemPrompt(persona,livePimData,rankedChunks,primaryTier);
  const conversationMessages=[...history.slice(-10).map(h=>({role:h.role==="user"?"user" as const:"assistant" as const,content:String(h.text??"")})),{role:"user" as const,content:message}];
  const modelCfg=MODELS[primaryTier];
  const result=await callWithFailover(primaryTier,modelCfg.maxTok,systemPrompt,conversationMessages);
  if(!result.ok){await admin.from("ai_requests").update({error_message:result.error?.slice(0,500)}).eq("id",requestId);return json({ok:false,detail:result.error},502)}
  const totalTokens=(result.usage.input_tokens??0)+(result.usage.output_tokens??0);
  const costEstimate=estimateCost(result.model_name,result.usage);
  await admin.from("ai_requests").update({output:{mode:"model",answer:result.answer,persona:persona.persona_name,model:{provider:result.provider,name:result.model_name},tier_requested:primaryTier,tier_auto_detected:autoTier,failover_used:result.failover_used,cost_estimate_usd:costEstimate,retrieval_mode:retrievalMode},explanation:`${persona.persona_name} (${persona.persona_role}) via ${result.provider}/${result.model_name} [${retrievalMode}]`+(result.failover_used?" [failover]":""),model_provider:result.provider,model_name:result.model_name,token_estimate:totalTokens>0?totalTokens:undefined,completed_at:new Date().toISOString()}).eq("id",requestId);
  if(totalTokens>0){await admin.from("ai_usage_meter").insert({organization_id:orgId,assistant_key:ASSISTANT_KEY,request_id:requestId,usage_kind:"token",quantity:totalTokens,limit_key:"ai.tokens.monthly",metadata:{source:`${result.provider}_actual`,persona:persona.persona_name,model:result.model_name,tier:primaryTier,failover:result.failover_used,cost_estimate_usd:costEstimate,retrieval:retrievalMode}})}
  return json({ok:true,answer:result.answer,primary_persona:persona.persona_name,live_pim_brands_matched:livePimData.matchedBrands,retrieval_mode:retrievalMode,chunk_keys_used:rankedChunks.filter((c:Json)=>(c.score as number)>0).map((c:Json)=>c.chunk_key),model_used:{provider:result.provider,model:result.model_name,tier_requested:primaryTier,tier_auto_detected:autoTier,failover_used:result.failover_used},token_usage:result.usage,cost_estimate_usd:costEstimate});
});
function buildSystemPrompt(persona:Json,livePimData:LivePimContext,rankedChunks:Json[],tier:ModelTier):string{
  const parts:string[]=[];
  parts.push(`You are ${persona.persona_name}, the ${persona.persona_role} on the Appliance IQ coaching team. ${persona.avatar_emoji??""}`.trim());
  if(persona.tone)parts.push(`Tone: ${persona.tone}`);
  if(persona.personality_traits)parts.push(`Personality: ${persona.personality_traits}`);
  if(persona.specialization)parts.push(`Your specialization: ${persona.specialization}. Stay focused \u2014 if the question is another persona's area, say so briefly and suggest who would know best.`);
  if(persona.prompt_prefix)parts.push(String(persona.prompt_prefix));
  parts.push(`TEAM HANDOFF PROTOCOL:\n- Your team: TJ (sales coaching), Natalie (product knowledge), Leah (design fit), Caden (training), Asher (installation), Katrina (service/warranty).\n- If the question clearly belongs to a teammate, answer briefly from your angle, then hand off: "For the full picture on [topic], ask [Name] \u2014 that is their specialty."\n- Never give detailed advice outside your specialization when a teammate owns it \u2014 a wrong installation spec or warranty claim causes real damage.`);
  parts.push(`GOVERNANCE (non-negotiable):\n- Advisory only. Never fabricate specific prices or warranty terms.\n- PIM DATA below is authoritative when available. Use it.\n- If PIM has model numbers but sparse specs, STILL LIST THE MODELS. Say "specs are being loaded" not "not available."\n- Use your appliance industry knowledge for standard dimensions and common features. Do NOT ask the rep for information you should know (like a 30" range being standard residential width).\n- A 30" range is always 30" wide. A 24" dishwasher is always 24" wide. A 27" washer is always 27" wide. These are industry standards \u2014 never ask for them.`);
  parts.push(`PRODUCT DISCUSSIONS AND COMPARISONS:\n- Use the FAB method: Feature \u2192 Advantage \u2192 Benefit. Connect every feature to what it means for the CUSTOMER.\n- Structure comparisons: what they share, then 3-4 key differentiators using FAB.\n- Include SELLING RECOMMENDATION: which customer profile each product fits, how to step up or step down.\n- For step-up: explain price difference as cost-per-year over product lifespan.\n- For lineups: good-better-best with WHO each tier is for.\n- End with: "Here is what I would say to the customer:" and a 2-3 sentence floor pitch.\n- When PIM data is sparse, use your training knowledge about the brand's lineup, typical features at each price tier, and known model families. Be honest about what is verified PIM data vs general knowledge.\n- ALWAYS stay within the brand the customer asked about. If they asked about LG, give them LG options. Do not redirect to other brands unless they specifically have no products in the category.`);
  if(tier==="fast")parts.push("RESPONSE MODE: Quick answer. Concise and direct. Still use FAB for product mentions.");
  else if(tier==="strong")parts.push("RESPONSE MODE: Deep coaching. Thorough analysis, specific examples, actionable coaching.");
  else parts.push("RESPONSE MODE: Standard. Clear, detailed, actionable. Include selling scripts and FAB framing.");
  if(livePimData.text)parts.push(`LIVE PIM DATA:\n${livePimData.text}`);
  const relevant=rankedChunks.filter((c:Json)=>(c.score as number)>0);
  if(relevant.length)parts.push("KNOWLEDGE BASE (cite [chunk_key]):\n"+relevant.map((c:Json)=>`[${c.chunk_key}] ${c.title??""}\n${String(c.content??"").slice(0,2000)}`).join("\n---\n"));
  return parts.join("\n\n");
}
interface ModelResult{ok:boolean;answer:string;provider:string;model_name:string;usage:{input_tokens?:number;output_tokens?:number};failover_used:boolean;error?:string}
async function callWithFailover(tier:ModelTier,maxTok:number,sys:string,msgs:Array<{role:"user"|"assistant";content:string}>):Promise<ModelResult>{const primary=MODELS[tier];const r=await callModel(primary.provider,primary.name,maxTok,sys,msgs);if(r.ok)return{...r,failover_used:false};const fb=primary.provider==="openai"?{p:"anthropic",n:MODELS.standard.name,m:MODELS.standard.maxTok}:{p:"openai",n:MODELS.fast.name,m:MODELS.fast.maxTok};const r2=await callModel(fb.p,fb.n,fb.m,sys,msgs);if(r2.ok)return{...r2,failover_used:true};return{ok:false,answer:"",provider:primary.provider,model_name:primary.name,usage:{},failover_used:true,error:`Primary: ${r.error}. Fallback: ${r2.error}`}}
async function callModel(provider:string,model:string,maxTok:number,sys:string,msgs:Array<{role:"user"|"assistant";content:string}>):Promise<ModelResult>{try{return provider==="openai"?await callOpenAI(model,maxTok,sys,msgs):await callAnthropic(model,maxTok,sys,msgs)}catch(e){return{ok:false,answer:"",provider,model_name:model,usage:{},failover_used:false,error:String(e).slice(0,500)}}}
async function callOpenAI(model:string,maxTok:number,sys:string,msgs:Array<{role:"user"|"assistant";content:string}>):Promise<ModelResult>{const k=Deno.env.get("OPENAI_API_KEY")??"";if(!k)return{ok:false,answer:"",provider:"openai",model_name:model,usage:{},failover_used:false,error:"OPENAI_API_KEY missing"};const body:any={model,messages:[{role:"system",content:sys},...msgs]};if(model.startsWith("gpt-5")||model.startsWith("o1")||model.startsWith("o3")||model.startsWith("o4")){body.max_completion_tokens=Math.max(maxTok,1000);if(model.startsWith("gpt-5"))body.reasoning_effort="none"}else{body.max_tokens=maxTok;body.temperature=0.3}const r=await fetch("https://api.openai.com/v1/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:`Bearer ${k}`},body:JSON.stringify(body)});if(!r.ok)return{ok:false,answer:"",provider:"openai",model_name:model,usage:{},failover_used:false,error:`openai_${r.status}: ${(await r.text()).slice(0,300)}`};const d=await r.json();return{ok:true,answer:d.choices?.[0]?.message?.content??"",provider:"openai",model_name:model,usage:{input_tokens:d.usage?.prompt_tokens,output_tokens:d.usage?.completion_tokens},failover_used:false}}
async function callAnthropic(model:string,maxTok:number,sys:string,msgs:Array<{role:"user"|"assistant";content:string}>):Promise<ModelResult>{const k=Deno.env.get("ANTHROPIC_API_KEY")??"";if(!k)return{ok:false,answer:"",provider:"anthropic",model_name:model,usage:{},failover_used:false,error:"ANTHROPIC_API_KEY missing"};const r=await fetch("https://api.anthropic.com/v1/messages",{method:"POST",headers:{"Content-Type":"application/json","x-api-key":k,"anthropic-version":"2023-06-01"},body:JSON.stringify({model,max_tokens:maxTok,system:sys,messages:msgs})});if(!r.ok)return{ok:false,answer:"",provider:"anthropic",model_name:model,usage:{},failover_used:false,error:`anthropic_${r.status}: ${(await r.text()).slice(0,300)}`};const d=await r.json();return{ok:true,answer:(d.content??[]).filter((b:{type:string})=>b.type==="text").map((b:{text:string})=>b.text).join("\n"),provider:"anthropic",model_name:model,usage:d.usage??{},failover_used:false}}
function estimateCost(model:string,usage:{input_tokens?:number;output_tokens?:number}):number{const r=COST_PER_M[model];if(!r)return 0;return Number((((usage.input_tokens??0)/1e6)*r.input+((usage.output_tokens??0)/1e6)*r.output).toFixed(6))}
interface LivePimContext{matchedBrands:string[];text:string}
async function fetchLivePimContext(admin:SB,prompt:string,history?:Array<{role:string;text:string}>):Promise<LivePimContext>{
  let searchText=prompt.toLowerCase();
  if(history?.length){for(const h of history.slice(-3)){if(h.role==="user")searchText+=" "+h.text.toLowerCase()}}
  const{data:brandRows}=await admin.from("brand_catalog").select("brand_name").eq("is_active",true);
  const allBrandNames:string[]=(brandRows??[]).map((b:{brand_name:string})=>b.brand_name).filter(Boolean);
  const matched=allBrandNames.filter(n=>searchText.includes(n.toLowerCase())).sort((a,b)=>b.length-a.length).slice(0,MAX_BRANDS);
  if(!matched.length)return{matchedBrands:[],text:""};
  const category=detectCategory(searchText);
  const sections:string[]=[];
  for(const brand of matched){
    const bs:string[]=[];
    let productQuery=admin.from("aiq_products").select("id,model,series,category,short_description,msrp,sale_price,width_inches,height_inches,depth_inches,capacity_cu_ft,energy_star,installation_type,voltage,finish").ilike("brand_name",brand);
    if(category)productQuery=productQuery.ilike("category",`%${category}%`);
    const{data:products}=await productQuery.limit(20);
    if(products?.length){
      const withSpecs=products.filter((p:any)=>p.short_description||p.msrp);
      const modelOnly=products.filter((p:any)=>!p.short_description&&!p.msrp);
      if(withSpecs.length){
        bs.push(`PRODUCTS (${brand}${category?" \u2014 "+category:""}) with specs:`);
        for(const p of withSpecs){bs.push(`  ${p.model}${p.series?" ("+p.series+")":""} \u2014 ${p.category??""} | ${p.short_description??""} | MSRP: $${p.msrp??"?"} | ${p.width_inches??"30"}\"W${p.capacity_cu_ft?" | "+p.capacity_cu_ft+" cu ft":""}${p.finish?" | "+p.finish:""}`)}
      }
      if(modelOnly.length){
        bs.push(`ADDITIONAL MODELS (${brand}${category?" \u2014 "+category:""}) \u2014 model numbers available, detailed specs loading:`);
        bs.push(`  ${modelOnly.map((p:any)=>p.model).join(", ")}`);
      }
      const productIds=products.map((p:any)=>p.id).filter(Boolean).slice(0,10);
      if(productIds.length){
        const{data:features}=await admin.from("pim_product_features").select("product_id,feature_text").in("product_id",productIds).limit(60);
        if(features?.length){
          const byProduct=new Map<string,string[]>();
          for(const f of features){if(!byProduct.has(f.product_id))byProduct.set(f.product_id,[]);byProduct.get(f.product_id)!.push(f.feature_text)}
          bs.push(`KEY FEATURES (${brand}):`);
          for(const p of products.filter((p:any)=>byProduct.has(p.id)).slice(0,6)){
            const feats=byProduct.get(p.id)!.slice(0,8).join(", ");
            bs.push(`  ${p.model}: ${feats}`);
          }
        }
      }
    }
    const{data:contacts}=await admin.from("aiq_vendor_contacts").select("country,customer_service_phone,customer_service_phone_label,customer_service_hours,support_email,service_portal_url").ilike("brand_name",brand);
    for(const c of contacts??[]){const bits=[];if(c.customer_service_phone)bits.push(`${c.customer_service_phone_label??"CS"}: ${c.customer_service_phone}`);if(c.support_email)bits.push(`Email: ${c.support_email}`);if(bits.length)bs.push(`CONTACT (${brand}): ${bits.join(" | ")}`)}
    const{data:warranties}=await admin.from("aiq_warranty_policies").select("category,full_coverage_years,full_coverage_notes,component_warranties").ilike("brand_name",brand);
    for(const w of warranties??[]){let comp="";try{const cs=typeof w.component_warranties==="string"?JSON.parse(w.component_warranties):(w.component_warranties??[]);if(Array.isArray(cs)&&cs.length)comp=" Extended: "+cs.map((c:any)=>`${c.component} ${c.years}yr`).join(", ")}catch{}bs.push(`WARRANTY (${brand}, ${w.category}): ${w.full_coverage_years}yr${w.full_coverage_notes?" "+w.full_coverage_notes:""}${comp}`)}
    if(bs.length)sections.push(bs.join("\n"));
  }
  return sections.length?{matchedBrands:matched,text:sections.join("\n\n")}:{matchedBrands:matched,text:`No records for ${matched.join(", ")}. Do not fabricate.`};
}
function json(body:unknown,status=200):Response{return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}})}
