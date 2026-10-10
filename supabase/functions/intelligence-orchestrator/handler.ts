type Json = Record<string, unknown>;
type State = {
  category?: string | null;
  intent?: string | null;
  constraints?: Json;
  preferences?: Json;
  answered?: string[];
  models?: string[];
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DISCOVERY: Record<string, Array<{key:string; question:string; required?:boolean}>> = {
  refrigeration: [
    {key:"max_width",question:"What is the maximum opening width in inches?",required:true},
    {key:"max_height",question:"What is the maximum opening height in inches?"},
    {key:"max_depth",question:"Do you need counter-depth, or what is the maximum depth?"},
    {key:"max_price",question:"What is the maximum budget?",required:true},
    {key:"configuration",question:"Which style do you prefer: French door, side-by-side, top freezer or bottom freezer?"},
    {key:"ice_water",question:"Do you want an ice maker or external water dispenser?"},
    {key:"household_size",question:"How many people will regularly use it?"},
  ],
  dishwashers: [
    {key:"max_width",question:"Is this a standard 24-inch opening or an 18-inch compact opening?",required:true},
    {key:"max_price",question:"What is the maximum budget?",required:true},
    {key:"noise_priority",question:"How important is quiet operation?"},
    {key:"third_rack",question:"Do you want a third rack?"},
    {key:"drying_priority",question:"Is strong plastic drying important?"},
    {key:"finish",question:"What finish do you need?"},
  ],
  cooking: [
    {key:"product_type",question:"Do you need a range, cooktop, rangetop, wall oven or microwave?",required:true},
    {key:"fuel_type",question:"Which fuel type is available: gas, electric, dual fuel or induction?",required:true},
    {key:"max_width",question:"What is the opening width in inches?",required:true},
    {key:"max_price",question:"What is the maximum budget?",required:true},
    {key:"ventilation",question:"What ventilation is installed or planned?"},
    {key:"cooking_style",question:"What do you cook most often?"},
  ],
  laundry: [
    {key:"product_type",question:"Do you need a washer, dryer, laundry pair or all-in-one?",required:true},
    {key:"installation",question:"Will the units be side-by-side, stacked or installed in a closet?",required:true},
    {key:"max_width",question:"What is the maximum available width?",required:true},
    {key:"max_depth",question:"Is there a maximum depth, including doors and hoses?"},
    {key:"max_price",question:"What is the total budget?",required:true},
    {key:"dryer_fuel",question:"For a dryer, is the connection electric or gas?"},
    {key:"household_size",question:"How large is the household and how often do you do laundry?"},
  ],
  ventilation: [
    {key:"product_type",question:"Do you need an under-cabinet hood, wall chimney, island hood, insert or downdraft?",required:true},
    {key:"max_width",question:"What width must the ventilation unit cover?",required:true},
    {key:"cooking_appliance",question:"What cooking appliance and fuel type will sit below it?",required:true},
    {key:"ducting",question:"Is the installation ducted outside or recirculating?"},
    {key:"max_price",question:"What is the maximum budget?"},
  ],
};

export function createHandler({ createClient, env, fetchImpl = fetch }: { createClient: any; env: (name: string) => string | undefined; fetchImpl?: typeof fetch }) {
return async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", {headers:CORS});
  if (req.method !== "POST") return out({error:"method_not_allowed"},405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return out({error:"authentication_required"},401);

  let body: Json;
  try { body = await req.json(); if (!isValidBody(body)) throw new Error("body"); } catch { return out({error:"invalid_json"},400); }
  const message = String(body.message ?? body.query ?? body.prompt ?? "").trim();
  if (message.length < 2) return out({error:"message_required"},400);

  const user = createClient(env("SUPABASE_URL") ?? "", env("SUPABASE_ANON_KEY") ?? "", { global: { headers: { Authorization: auth } }, auth: { persistSession: false, autoRefreshToken: false } });
  const { data: authData, error: authError } = await user.auth.getUser();
  if (authError || !authData?.user) return out({ error: "invalid_session" }, 401);
  const { data: context, error: contextError } = await user.rpc("tj_runtime_my_platform_context");
  if (contextError || !context?.organization_id) return out({ error: "active_mapped_organization_required" }, 403);
  const prior = isObj(body.state) ? body.state as State : {};
  if (message.length > 4000 || !validState(prior)) return out({ error: "invalid_message_or_state" }, 400);
  const extracted = extract(message);
  const state: State = {
    ...prior,
    category: extracted.category ?? prior.category ?? null,
    intent: extracted.intent ?? prior.intent ?? null,
    constraints: {...(prior.constraints ?? {}), ...(extracted.constraints ?? {})},
    preferences: {...(prior.preferences ?? {}), ...(extracted.preferences ?? {})},
    answered: [...new Set([...(prior.answered ?? []), ...Object.keys(extracted.constraints ?? {}), ...Object.keys(extracted.preferences ?? {})])],
    models: [...new Set([...(prior.models ?? []), ...(extracted.models ?? [])])],
  };

  const mode = chooseMode(message, state);
  if (mode === "discovery") {
    const next = nextQuestions(state, Math.max(1, Math.min(Number(body.question_limit ?? 2) || 2, 3)));
    return out({
      engine:"applianceiq-intelligence-orchestrator-v1",
      mode,
      state,
      questions:next,
      ready_to_search:next.length === 0,
      message: next.length ? "I need a little more information before recommending products." : "I have enough information to search.",
    });
  }

  const query = buildQuery(message, state);
  const filters = buildFilters(state);
  const response = await fetchImpl(`${env("SUPABASE_URL")}/functions/v1/product-intelligence`, {
    method:"POST",
    headers:{
      "Authorization":auth,
      "apikey":env("SUPABASE_ANON_KEY") ?? "",
      "Content-Type":"application/json",
    },
    body:JSON.stringify({query, filters, limit:body.limit ?? (mode === "compare" ? 8 : 5), country:body.country ?? "CA", retailer_name:body.retailer_name ?? null}),
  });
  const result = await response.json().catch(() => ({error:"invalid_product_engine_response"}));
  if (!response.ok) return out({engine:"applianceiq-intelligence-orchestrator-v1",mode,state,downstream:result},response.status);

  return out({
    engine:"applianceiq-intelligence-orchestrator-v1",
    mode,
    state,
    discovery_complete:true,
    result,
    next_actions: mode === "compare"
      ? ["select_winner","add_to_package","save_to_crm"]
      : ["compare_results","refine_requirements","add_to_package","save_to_crm"],
  });
};
}

function chooseMode(message:string,state:State):"discovery"|"recommend"|"compare" {
  const lower = message.toLowerCase();
  if ((state.models?.length ?? 0) >= 2 || /compare|versus|\bvs\b/.test(lower)) return "compare";
  if (/show|find|recommend|search|options|best/.test(lower) && hasMinimum(state)) return "recommend";
  if (hasMinimum(state) && /go ahead|that is all|search now|start/.test(lower)) return "recommend";
  return "discovery";
}
function hasMinimum(state:State):boolean {
  const c = state.constraints ?? {};
  if (!state.category) return false;
  const hasBudget = numberish(c.max_price);
  const dimensional = ["refrigeration","dishwashers","cooking","laundry","ventilation"].includes(String(state.category));
  return hasBudget && (!dimensional || numberish(c.max_width) || state.category === "laundry");
}
function nextQuestions(state:State,limit:number) {
  const list = DISCOVERY[String(state.category ?? "")] ?? [
    {key:"category",question:"Which appliance category are you shopping for?",required:true},
    {key:"max_price",question:"What is the maximum budget?",required:true},
    {key:"max_width",question:"Are there any width or installation limits?"},
  ];
  const answered = new Set(state.answered ?? []);
  if (state.category) answered.add("category");
  return list.filter(q => !answered.has(q.key)).sort((a,b)=>Number(Boolean(b.required))-Number(Boolean(a.required))).slice(0,limit);
}
function extract(message:string):State {
  const lower = message.toLowerCase();
  const state:State = {constraints:{},preferences:{},models:[]};
  const cats:Record<string,string[]> = {
    refrigeration:["fridge","refrigerator","freezer"], dishwashers:["dishwasher"],
    cooking:["range","stove","cooktop","rangetop","wall oven","oven"],
    laundry:["washer","dryer","laundry"], ventilation:["hood","ventilation","downdraft"]
  };
  for (const [cat,words] of Object.entries(cats)) if (words.some(w=>lower.includes(w))) state.category=cat;
  const money = [...message.matchAll(/(?:\$|budget\s*(?:of|is|under|:)?\s*)([0-9]{1,6}(?:,[0-9]{3})?)/gi)].map(m=>Number(m[1].replace(",","")));
  if (money.length) (state.constraints as Json).max_price=Math.max(...money);
  const width = lower.match(/(?:under|max(?:imum)?|opening|fit|fits?)?\s*(\d{2}(?:\.\d+)?)\s*(?:inch|inches|in\b|\")/i);
  if (width) (state.constraints as Json).max_width=Number(width[1]);
  const depth = lower.match(/(?:depth|deep)\D{0,12}(\d{2}(?:\.\d+)?)/i);
  if (depth) (state.constraints as Json).max_depth=Number(depth[1]);
  if (/counter[- ]?depth/.test(lower)) (state.preferences as Json).counter_depth=true;
  if (/stainless/.test(lower)) (state.preferences as Json).finish="stainless";
  if (/quiet|silent|low noise/.test(lower)) (state.preferences as Json).noise_priority="high";
  if (/third rack/.test(lower)) (state.preferences as Json).third_rack=true;
  if (/induction/.test(lower)) (state.preferences as Json).fuel_type="induction";
  else if (/dual fuel/.test(lower)) (state.preferences as Json).fuel_type="dual fuel";
  else if (/\bgas\b/.test(lower)) (state.preferences as Json).fuel_type="gas";
  else if (/electric/.test(lower)) (state.preferences as Json).fuel_type="electric";
  state.models = [...new Set((message.match(/\b[A-Z0-9][A-Z0-9\/-]{5,}\b/g) ?? []).filter(x=>/\d/.test(x)))];
  return state;
}
function buildFilters(state:State):Json {
  const c = state.constraints ?? {}, p = state.preferences ?? {};
  const f:Json = {category:state.category ?? null};
  for (const k of ["max_price","min_price","max_width","max_height","max_depth","min_capacity"]) if (c[k] != null) f[k]=c[k];
  if (p.finish) f.finish=p.finish;
  if (p.energy_star != null) f.energy_star=p.energy_star;
  const terms:string[]=[];
  for (const [k,v] of Object.entries(p)) if (!["finish","energy_star"].includes(k) && v != null) terms.push(`${k} ${String(v)}`);
  if (state.models?.length) terms.push(...state.models);
  if (terms.length) f.required_terms=terms;
  return f;
}
function buildQuery(message:string,state:State):string {
  return [message,state.category ? `category ${state.category}`:"", JSON.stringify(state.constraints ?? {}),JSON.stringify(state.preferences ?? {}),(state.models ?? []).join(" ")].filter(Boolean).join(" | ");
}
function numberish(v:unknown):boolean { return typeof v === "number" && Number.isFinite(v); }
function isObj(v:unknown):v is Json { return !!v && typeof v === "object" && !Array.isArray(v); }
function out(body:unknown,status=200){return new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json"}})}

function isValidBody(v: unknown): v is Json { return !!v && typeof v === "object" && !Array.isArray(v); }

function validState(s: State): boolean {
  if (s.category != null && (typeof s.category !== "string" || s.category.length > 100)) return false;
  if (s.constraints != null && !isObj(s.constraints)) return false;
  if (s.preferences != null && !isObj(s.preferences)) return false;
  return [s.answered,s.models].every(a => a == null || (Array.isArray(a) && a.length <= 30 && a.every(v => typeof v === "string" && v.length <= 120)));
}
