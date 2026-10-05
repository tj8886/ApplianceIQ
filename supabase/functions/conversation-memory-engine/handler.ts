type Json = Record<string, any>;
const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
export function createHandler({env,fetchImpl=fetch}:{env:(name:string)=>string|undefined;fetchImpl?:typeof fetch}) {
 return async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:CORS});
  if(req.method!=="POST") return reply({error:"method_not_allowed"},405);
  const auth=req.headers.get("Authorization")??"";
  if(!auth.startsWith("Bearer ")) return reply({error:"authentication_required"},401);
  let body:Json;try{body=await req.json();if(!body||typeof body!=="object"||Array.isArray(body))throw new Error("body");}catch{return reply({error:"invalid_json"},400);}
  const message=String(body.message??body.query??"").trim();
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if(!message||message.length>4000||JSON.stringify(body).length>10000 || (body.conversation_id&&!uuid.test(String(body.conversation_id))) || (body.organization_id&&!uuid.test(String(body.organization_id)))) return reply({error:"invalid_message_or_identity"},400);
  if(body.crm_record_id||body.crm_record_type) return reply({error:"crm_link_requires_reviewed_workflow"},400);
  if(body.stage && !["discovery","qualification","product_selection","comparison","installation_review","quote_preparation","objection_handling","close","follow_up","post_sale"].includes(body.stage)) return reply({error:"invalid_stage"},400);
  const url=env("SUPABASE_URL")??"", key=env("SUPABASE_ANON_KEY")??"";
  try{
   const headers={Authorization:auth,apikey:key,"Content-Type":"application/json"};
   const userResponse=await fetchImpl(`${url}/auth/v1/user`,{headers,signal:AbortSignal.timeout(20000)});
   if(!userResponse.ok) return reply({error:"invalid_session"},401);
   const rpc=async(name:string,payload:Json)=>{
    const r=await fetchImpl(`${url}/rest/v1/rpc/${name}`,{method:"POST",headers,body:JSON.stringify(payload),signal:AbortSignal.timeout(20000)});
    return {ok:r.ok,data:await r.json()};
   };
   const context=await rpc("tj_runtime_my_platform_context",{});
   if(!context.ok||!context.data.organization_id) return reply({error:"active_mapped_organization_required"},403);
   const organization=body.organization_id??context.data.organization_id;
   const state=await rpc("tj_product_conversation_state",{p_conversation_id:body.conversation_id??null,p_organization_id:organization,p_title:String(body.title??message).slice(0,120)});
   if(!state.ok) return reply({error:"conversation_access_failed"},state.data.code==="42501"?403:400);
   const extracted=await extractFacts(message,state.data.profile??{},env,fetchImpl);
   const saved=await rpc("tj_commit_product_conversation",{p_conversation_id:state.data.conversation_id,p_expected_version:state.data.memory_version,p_message:message,p_facts:extracted.facts,p_models:extracted.discussed_models??[],p_stage:body.stage??null});
   if(!saved.ok) return reply({error:saved.data.code==="40001"?"conversation_changed_reload_required":"conversation_save_failed"},saved.data.code==="40001"?409:saved.data.code==="42501"?403:400);
   const discovery=nextQuestion(saved.data.profile);
   return reply({engine:"applianceiq-conversation-memory-v1",...saved.data,extracted_facts:extracted.facts,next_discovery_question:discovery.question,missing_profile_fields:discovery.missing,recommendation_ready:saved.data.completeness_score>=55&&!!saved.data.profile.category,generated_at:new Date().toISOString()});
  }catch{return reply({error:"conversation_workflow_unavailable"},502);}
 };
}
async function extractFacts(message: string, existing: Json, env: (name:string)=>string|undefined, fetchImpl:typeof fetch) {
  const key = env("ANTHROPIC_API_KEY");
  const model=env("AI_MODEL_LIGHT") || env("AI_MODEL_STANDARD");
  if (!key || !model) return heuristicExtract(message);
  const prompt = `Extract appliance-shopping facts from the message. Return only JSON with keys facts and discussed_models. Allowed fact keys: category, budget_max, budget_min, opening_width, opening_height, opening_depth, finish, household_size, must_have, deal_breakers, preferred_brands, excluded_brands, installation_type, fuel_type, energy_star, accessibility_needs, timeline, location, use_cases. Use numbers for dimensions in inches and money. Do not invent. Existing profile: ${JSON.stringify(existing)}\nMessage: ${message}`;
  try {
    const r = await fetchImpl("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
      signal:AbortSignal.timeout(15000),
      body: JSON.stringify({ model, max_tokens: 700, temperature: 0, messages: [{ role: "user", content: prompt }] })
    });
    if(!r.ok) return heuristicExtract(message);
    const data = await r.json();
    const text = data?.content?.[0]?.text ?? "{}";
    const result=JSON.parse(text.replace(/^```json\s*|\s*```$/g, ""));
    return validExtraction(result) ? result : heuristicExtract(message);
  } catch { return heuristicExtract(message); }
}

function heuristicExtract(message: string) {
  const t = message.toLowerCase();
  const facts: Json = {};
  const categories: Record<string,string> = { fridge: "refrigeration", refrigerator: "refrigeration", dishwasher: "dishwashers", range: "cooking", oven: "cooking", cooktop: "cooking", washer: "laundry", dryer: "laundry", microwave: "microwaves", hood: "ventilation", freezer: "refrigeration" };
  for (const [k,v] of Object.entries(categories)) if (t.includes(k)) { facts.category = v; break; }
  const budget = t.match(/(?:\$|budget\s*(?:is|of|under|:)?\s*\$?)([0-9,]+)/i);
  if (budget) facts.budget_max = Number(budget[1].replace(/,/g, ""));
  const width = t.match(/(?:width|wide|opening)\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (width) facts.opening_width = Number(width[1]);
  const height = t.match(/height\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (height) facts.opening_height = Number(height[1]);
  const depth = t.match(/depth\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (depth) facts.opening_depth = Number(depth[1]);
  const household = t.match(/(?:family|household) of (\d+)/i);
  if (household) facts.household_size = Number(household[1]);
  for (const finish of ["black stainless","stainless steel","panel ready","white","black"]) if (t.includes(finish)) { facts.finish = finish; break; }
  if (t.includes("energy star")) facts.energy_star = true;
  const models = [...message.matchAll(/\b[A-Z]{2,5}[A-Z0-9-]{4,}\b/g)].map(m => m[0]).filter(m=>/\d/.test(m)).slice(0,30);
  return { facts, discussed_models: models };
}

function mergeProfile(oldProfile: Json, facts: Json) {
  const profile = { ...oldProfile };
  const contradictions: Json[] = [];
  for (const [key, value] of Object.entries(facts)) {
    if (value == null || value === "" || (Array.isArray(value) && !value.length)) continue;
    const old = profile[key];
    if (old != null && JSON.stringify(old) !== JSON.stringify(value)) contradictions.push({ field: key, previous: old, current: value, detected_at: new Date().toISOString() });
    profile[key] = Array.isArray(value) ? unique([...(Array.isArray(old) ? old : []), ...value]) : value;
  }
  return { profile, contradictions };
}

function nextQuestion(p: Json) {
  const category = p.category ?? "appliance";
  const questions: [string,string][] = [
    ["category", "Which appliance category are you shopping for?"],
    ["budget_max", `What is the maximum budget for the ${category}?`],
    ["opening_width", "What is the maximum opening width in inches?"],
    ["opening_height", "What is the maximum opening height in inches?"],
    ["opening_depth", "What is the maximum acceptable depth in inches?"],
    ["must_have", "Which features are absolute must-haves?"],
    ["finish", "Which finish or colour is preferred?"],
    ["household_size", "How many people will regularly use this appliance?"],
    ["timeline", "When does the appliance need to be delivered?"]
  ];
  const missing = questions.filter(([k]) => p[k] == null || p[k] === "" || (Array.isArray(p[k]) && !p[k].length));
  return { question: missing[0]?.[1] ?? null, missing: missing.map(([k]) => k) };
}

function completenessScore(p: Json) {
  const weighted: Record<string,number> = { category: 18, budget_max: 16, opening_width: 14, opening_height: 10, opening_depth: 10, must_have: 12, finish: 6, household_size: 6, timeline: 4, installation_type: 4 };
  return Math.round(Object.entries(weighted).reduce((sum,[k,w]) => sum + (p[k] != null && p[k] !== "" && (!Array.isArray(p[k]) || p[k].length) ? w : 0), 0));
}

function inferStage(p: Json, requested: string) {
  if (requested && requested !== "discovery") return requested;
  const score = completenessScore(p);
  if (score >= 80) return "product_selection";
  if (score >= 55) return "qualification";
  return "discovery";
}


function validExtraction(x:Json):boolean {
 if(!x || typeof x!=="object" || !x.facts || typeof x.facts!=="object" || Array.isArray(x.facts))return false;
 const numbers=["budget_max","budget_min","opening_width","opening_height","opening_depth","household_size"];
 const arrays=["must_have","deal_breakers","preferred_brands","excluded_brands","accessibility_needs","use_cases"];
 const text=["category","finish","installation_type","fuel_type","timeline","location"];
 for(const [k,v] of Object.entries(x.facts)) {
  if(v==null)continue;
  if(numbers.includes(k)){if(typeof v!=="number"||!Number.isFinite(v)||v<=0||v>1000000)return false;}
  else if(arrays.includes(k)){if(!Array.isArray(v)||v.length>30||v.some(t=>typeof t!=="string"||t.length>120))return false;}
  else if(text.includes(k)){if(typeof v!=="string"||v.length>200)return false;}
  else if(k!=="energy_star"||typeof v!=="boolean")return false;
 }
 return x.discussed_models==null || (Array.isArray(x.discussed_models)&&x.discussed_models.length<=30&&x.discussed_models.every((m:unknown)=>typeof m==="string"&&m.length<=120));
}
function unique<T>(v:T[]):T[]{return [...new Set(v)];}
function reply(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}});}
