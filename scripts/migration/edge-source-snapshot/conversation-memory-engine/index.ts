import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json = Record<string, any>;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply({ error: "authentication_required" }, 401);

  let body: Json;
  try { body = await req.json(); } catch { return reply({ error: "invalid_json" }, 400); }

  const message = String(body.message ?? body.query ?? "").trim();
  if (!message) return reply({ error: "message_required" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const userRes = await fetch(`${url}/auth/v1/user`, { headers: { Authorization: auth, apikey: anonKey } });
  if (!userRes.ok) return reply({ error: "invalid_session" }, 401);
  const user = await userRes.json();
  const userId = user.id as string;

  let conversationId = body.conversation_id ? String(body.conversation_id) : null;
  let conversation: Json | null = null;

  if (conversationId) {
    const rows = await rest(url, serviceKey, `ai_conversations?id=eq.${encodeURIComponent(conversationId)}&user_id=eq.${userId}&select=*`);
    conversation = rows?.[0] ?? null;
    if (!conversation) return reply({ error: "conversation_not_found" }, 404);
  } else {
    const created = await rest(url, serviceKey, "ai_conversations", "POST", {
      user_id: userId,
      organization_id: body.organization_id ?? null,
      crm_record_type: body.crm_record_type ?? null,
      crm_record_id: body.crm_record_id ?? null,
      title: body.title ?? message.slice(0, 120),
      stage: "discovery",
      status: "active"
    }, true);
    conversation = created?.[0];
    conversationId = conversation.id;
  }

  const memoryRows = await rest(url, serviceKey, `ai_conversation_memory?conversation_id=eq.${conversationId}&select=*`);
  const current = memoryRows?.[0] ?? { profile: {}, contradictions: [], discussed_models: [], recommendations: [], outstanding_questions: [], memory_version: 0 };

  const extracted = await extractFacts(message, current.profile ?? {});
  const merged = mergeProfile(current.profile ?? {}, extracted.facts ?? {});
  const contradictions = [...(current.contradictions ?? []), ...merged.contradictions].slice(-50);
  const discovery = nextQuestion(merged.profile);
  const completeness = completenessScore(merged.profile);
  const stage = inferStage(merged.profile, body.stage ?? conversation.stage);

  await rest(url, serviceKey, "ai_conversation_turns", "POST", {
    conversation_id: conversationId,
    user_id: userId,
    role: "user",
    content: message,
    extracted_facts: extracted.facts ?? {}
  });

  await rest(url, serviceKey, "ai_conversation_memory?on_conflict=conversation_id", "POST", {
    conversation_id: conversationId,
    user_id: userId,
    profile: merged.profile,
    contradictions,
    discussed_models: unique([...(current.discussed_models ?? []), ...(extracted.discussed_models ?? [])]),
    recommendations: current.recommendations ?? [],
    outstanding_questions: discovery.missing,
    completeness_score: completeness,
    memory_version: Number(current.memory_version ?? 0) + 1,
    updated_at: new Date().toISOString()
  }, true, "resolution=merge-duplicates");

  await rest(url, serviceKey, `ai_conversations?id=eq.${conversationId}&user_id=eq.${userId}`, "PATCH", {
    stage,
    last_message_at: new Date().toISOString(),
    updated_at: new Date().toISOString()
  });

  return reply({
    engine: "applianceiq-conversation-memory-v1",
    conversation_id: conversationId,
    stage,
    profile: merged.profile,
    extracted_facts: extracted.facts ?? {},
    contradictions: merged.contradictions,
    completeness_score: completeness,
    next_discovery_question: discovery.question,
    missing_profile_fields: discovery.missing,
    recommendation_ready: completeness >= 55 && !!merged.profile.category,
    generated_at: new Date().toISOString()
  });
});

async function extractFacts(message: string, existing: Json) {
  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return heuristicExtract(message);
  const prompt = `Extract appliance-shopping facts from the message. Return only JSON with keys facts and discussed_models. Allowed fact keys: category, budget_max, budget_min, opening_width, opening_height, opening_depth, finish, household_size, must_have, deal_breakers, preferred_brands, excluded_brands, installation_type, fuel_type, energy_star, accessibility_needs, timeline, location, use_cases. Use numbers for dimensions in inches and money. Do not invent. Existing profile: ${JSON.stringify(existing)}\nMessage: ${message}`;
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "content-type": "application/json", "x-api-key": key, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: "claude-sonnet-4-20250514", max_tokens: 700, temperature: 0, messages: [{ role: "user", content: prompt }] })
    });
    const data = await r.json();
    const text = data?.content?.[0]?.text ?? "{}";
    return JSON.parse(text.replace(/^```json\s*|\s*```$/g, ""));
  } catch { return heuristicExtract(message); }
}

function heuristicExtract(message: string) {
  const t = message.toLowerCase();
  const facts: Json = {};
  const categories: Record<string,string> = { fridge: "refrigeration", refrigerator: "refrigeration", dishwasher: "dishwashers", range: "cooking", oven: "cooking", cooktop: "cooking", washer: "laundry", dryer: "laundry", microwave: "microwaves", hood: "ventilation", freezer: "refrigeration" };
  for (const [k,v] of Object.entries(categories)) if (t.includes(k)) { facts.category = v; break; }
  const budget = t.match(/(?:under|max(?:imum)?|budget(?: is)?|up to)\s*\$?([0-9,]+)/i);
  if (budget) facts.budget_max = Number(budget[1].replace(/,/g, ""));
  const width = t.match(/(?:width|wide|opening)\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (width) facts.opening_width = Number(width[1]);
  const height = t.match(/height\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (height) facts.opening_height = Number(height[1]);
  const depth = t.match(/depth\s*(?:is|of|at)?\s*(\d+(?:\.\d+)?)\s*(?:in|inch|inches|\")/i);
  if (depth) facts.opening_depth = Number(depth[1]);
  const household = t.match(/(?:family|household) of (\d+)/i);
  if (household) facts.household_size = Number(household[1]);
  for (const finish of ["stainless steel","black stainless","white","black","panel ready"]) if (t.includes(finish)) facts.finish = finish;
  if (t.includes("energy star")) facts.energy_star = true;
  const models = [...message.matchAll(/\b[A-Z]{2,5}[A-Z0-9-]{4,}\b/g)].map(m => m[0]);
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

async function rest(url: string, key: string, path: string, method = "GET", body?: unknown, returnRows = false, prefer?: string) {
  const headers: Record<string,string> = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  const prefs = [returnRows ? "return=representation" : "return=minimal", prefer].filter(Boolean).join(",");
  if (prefs) headers.Prefer = prefs;
  const r = await fetch(`${url}/rest/v1/${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text();
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
  return text ? JSON.parse(text) : null;
}

function unique<T>(v: T[]): T[] { return [...new Set(v)]; }
function reply(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } }); }
