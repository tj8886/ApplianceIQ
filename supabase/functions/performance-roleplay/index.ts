import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json = Record<string, unknown>;
type SB = ReturnType<typeof createClient>;

type Scenario = {
  id: string;
  code: string;
  title: string;
  difficulty: number;
  persona: string | null;
  context: string;
  objectives: unknown;
  competency_weights: Record<string, number>;
  customer_profile: Json;
  hidden_facts: unknown;
  objections: unknown;
  success_criteria: unknown;
  opening_line: string | null;
};

type RoleplaySession = {
  id: string;
  organization_id: string;
  user_id: string;
  scenario_type: string;
  status: string;
  mode: string | null;
  difficulty_level: number | null;
  transcript: Array<{ role: string; content: string; timestamp?: string }> | null;
  scoring_breakdown: Json | null;
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  const model = Deno.env.get("AI_MODEL_STANDARD") ?? Deno.env.get("AI_MODEL") ?? "";

  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "server_not_configured" }, 503);
  if (!anthropicKey || !model) return json({ error: "ai_not_configured" }, 503);

  const sb = createClient(supabaseUrl, anonKey, { global: { headers: { authorization: auth } } });
  const admin = createClient(supabaseUrl, serviceKey);
  const { data: { user }, error: userErr } = await sb.auth.getUser();
  if (userErr || !user) return json({ error: "auth_failed" }, 401);

  let body: Json;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const action = String(body.action ?? "");
  const sessionId = String(body.session_id ?? "");
  if (!sessionId) return json({ error: "session_id_required" }, 400);

  const loaded = await loadSessionAndScenario(admin, sessionId, user.id);
  if (loaded.error) return json({ error: loaded.error }, loaded.status ?? 400);
  const session = loaded.session!;
  const scenario = loaded.scenario!;

  if (action === "opening") {
    if (session.status !== "active") return json({ error: "session_not_active" }, 400);
    const transcript = Array.isArray(session.transcript) ? [...session.transcript] : [];
    if (transcript.length) return json({ ok: true, customer_response: transcript[0]?.content ?? "", scenario: publicScenario(scenario, session) });

    const mode = session.mode ?? "you_sell";
    let opening = scenario.opening_line?.trim() || "Hi, I need some help today.";
    if (mode === "bot_sells") {
      const prompt = botSellerSystem(scenario);
      opening = await callAnthropic(anthropicKey, model, prompt, [{ role: "user", content: "Begin the interaction as the expert salesperson. Keep the first turn concise." }]);
    } else if (!scenario.opening_line) {
      opening = await callAnthropic(anthropicKey, model, customerSystem(scenario), [{ role: "user", content: "Open the roleplay naturally as the customer. Do not reveal hidden facts." }]);
    }

    const role = mode === "bot_sells" ? "ai_rep" : "customer";
    transcript.push({ role, content: opening, timestamp: new Date().toISOString() });
    await admin.from("ai_roleplay_sessions").update({ transcript }).eq("id", sessionId);

    return json({ ok: true, customer_response: opening, scenario: publicScenario(scenario, session) });
  }

  if (action === "message") {
    if (session.status !== "active") return json({ error: "session_not_active" }, 400);
    const message = String(body.message ?? body.rep_message ?? "").trim();
    if (!message) return json({ error: "message_required" }, 400);

    const mode = session.mode ?? "you_sell";
    const transcript = Array.isArray(session.transcript) ? [...session.transcript] : [];
    transcript.push({ role: mode === "bot_sells" ? "customer" : "rep", content: message, timestamp: new Date().toISOString() });

    const aiMessages = transcriptToAnthropic(transcript, mode);
    const system = mode === "bot_sells" ? botSellerSystem(scenario) : customerSystem(scenario);
    const responseText = await callAnthropic(anthropicKey, model, system, aiMessages);
    transcript.push({ role: mode === "bot_sells" ? "ai_rep" : "customer", content: responseText, timestamp: new Date().toISOString() });

    await admin.from("ai_roleplay_sessions").update({
      transcript,
      total_turns: Math.max(0, Math.floor(transcript.length / 2)),
    }).eq("id", sessionId);

    return json({ ok: true, response: responseText, customer_response: responseText, turn_count: transcript.length });
  }

  if (action === "end") {
    if (session.status !== "active") {
      const { data: completed } = await admin.from("ai_roleplay_sessions")
        .select("session_score,scoring_breakdown,feedback,coach_summary")
        .eq("id", sessionId).single();
      return json({ ok: true, already_completed: true, ...completed });
    }

    const transcript = Array.isArray(session.transcript) ? session.transcript : [];
    const mode = session.mode ?? "you_sell";

    if (mode === "bot_sells") {
      const learning = await scoreBotSells(anthropicKey, model, scenario, transcript);
      await admin.from("ai_roleplay_sessions").update({
        status: "completed",
        completed_at: new Date().toISOString(),
        feedback: learning.summary,
        coach_summary: learning,
        scoring_breakdown: {},
        session_score: null,
      }).eq("id", sessionId);
      return json({ ok: true, mode, learning_summary: learning, scenario: revealScenario(scenario) });
    }

    const result = await scoreRep(anthropicKey, model, scenario, transcript, mode === "beat_the_expert");
    const scores = result.scores ?? {};
    const numeric = Object.values(scores).filter((v): v is number => typeof v === "number" && Number.isFinite(v));
    const overall = numeric.length ? numeric.reduce((a, b) => a + b, 0) / numeric.length : 0;

    const coachSummary = {
      strongest_moment: result.strongest_moment ?? "",
      weakest_moment: result.weakest_moment ?? "",
      missed_opportunities: result.missed_opportunities ?? [],
      better_wording: result.better_wording ?? [],
      customer_secrets: result.customer_secrets ?? scenario.hidden_facts,
      expert_comparison: result.expert_comparison ?? null,
      target_competency: result.target_competency ?? null,
      recommended_next_action: result.recommended_next_action ?? "Repeat the prescribed scenario and improve the weakest competency.",
      scoring_version: "performance_brain_v2",
    };

    const { error: updateErr } = await admin.from("ai_roleplay_sessions").update({
      status: "completed",
      completed_at: new Date().toISOString(),
      session_score: Number(overall.toFixed(2)),
      scoring_breakdown: scores,
      kpi_scores: scores,
      feedback: result.feedback ?? "",
      coach_summary: coachSummary,
      scoring_version: "performance_brain_v2",
    }).eq("id", sessionId);
    if (updateErr) return json({ error: "session_update_failed", detail: updateErr.message }, 500);

    // The completed-session trigger writes these scores into performance_observations
    // and updates rolling skill state. Read the post-trigger skill state for the UI.
    const { data: skillRows } = await admin.from("performance_skill_state")
      .select("rolling_score,confidence,sample_size,trend,competency_id")
      .eq("organization_id", session.organization_id)
      .eq("user_id", user.id);
    const competencyIds = (skillRows ?? []).map((r) => r.competency_id);
    const { data: competencies } = competencyIds.length
      ? await admin.from("performance_competencies").select("id,code,name").in("id", competencyIds)
      : { data: [] as Array<{ id: string; code: string; name: string }> };
    const competencyMap = new Map((competencies ?? []).map((c) => [c.id, c]));
    const salesDna = (skillRows ?? []).map((r) => ({
      code: competencyMap.get(r.competency_id)?.code ?? r.competency_id,
      name: competencyMap.get(r.competency_id)?.name ?? "Competency",
      score: r.rolling_score,
      confidence: r.confidence,
      sample_size: r.sample_size,
      trend: r.trend,
    })).sort((a, b) => Number(a.score) - Number(b.score));

    const next = await getNextScenario(admin, session.organization_id, user.id);

    return json({
      ok: true,
      mode,
      session_score: Number(overall.toFixed(1)),
      scores,
      feedback: result.feedback ?? "",
      coach_summary: coachSummary,
      scenario: revealScenario(scenario),
      sales_dna: salesDna,
      next_prescription: next,
    });
  }

  return json({ error: "invalid_action" }, 400);
});

async function loadSessionAndScenario(admin: SB, sessionId: string, userId: string) {
  const { data: session, error } = await admin.from("ai_roleplay_sessions")
    .select("id,organization_id,user_id,scenario_type,status,mode,difficulty_level,transcript,scoring_breakdown")
    .eq("id", sessionId).maybeSingle();
  if (error || !session) return { error: "session_not_found", status: 404 };
  if (session.user_id !== userId) return { error: "forbidden", status: 403 };

  const { data: link } = await admin.from("performance_roleplay_links")
    .select("scenario_id")
    .eq("ai_roleplay_session_id", sessionId)
    .order("created_at", { ascending: false })
    .limit(1).maybeSingle();
  if (!link?.scenario_id) return { error: "performance_scenario_not_linked", status: 409 };

  const { data: scenario, error: scenarioErr } = await admin.from("performance_scenarios")
    .select("id,code,title,difficulty,persona,context,objectives,competency_weights,customer_profile,hidden_facts,objections,success_criteria,opening_line")
    .eq("id", link.scenario_id).maybeSingle();
  if (scenarioErr || !scenario) return { error: "scenario_not_found", status: 404 };
  return { session: session as RoleplaySession, scenario: scenario as Scenario };
}

function publicScenario(s: Scenario, session: RoleplaySession) {
  return {
    id: s.id,
    code: s.code,
    title: s.title,
    difficulty: s.difficulty,
    persona: s.persona,
    context: s.context,
    objectives: s.objectives,
    target_competencies: Object.keys(s.competency_weights ?? {}),
    mode: session.mode ?? "you_sell",
  };
}

function revealScenario(s: Scenario) {
  return {
    ...publicScenario(s, { mode: "you_sell" } as RoleplaySession),
    customer_profile: s.customer_profile,
    hidden_facts: s.hidden_facts,
    objections: s.objections,
    success_criteria: s.success_criteria,
  };
}

function customerSystem(s: Scenario): string {
  return `You are the CUSTOMER in an ApplianceIQ sales-training simulation.
Stay in character. Never coach the salesperson during the simulation.
Scenario: ${s.title}
Difficulty: ${s.difficulty}/10
Context: ${s.context}
Customer profile: ${JSON.stringify(s.customer_profile)}
PRIVATE FACTS: ${JSON.stringify(s.hidden_facts)}
Likely objections: ${JSON.stringify(s.objections)}
Success criteria for the rep: ${JSON.stringify(s.success_criteria)}

RULES:
- Never volunteer private facts unless the salesperson earns them with good discovery questions.
- Be realistic, sometimes vague, distracted, skeptical, or contradictory according to the profile.
- Do not become easy just because the salesperson asks to buy.
- Keep each response conversational and usually 1-4 sentences.
- Do not fabricate exact product specs, prices, rebates, inventory, warranty terms, or codes.
- If the rep makes an unsupported factual claim, challenge it naturally rather than accepting it.
- The objective is a realistic sale, not a scripted happy ending.`;
}

function botSellerSystem(s: Scenario): string {
  return `You are an elite appliance salesperson demonstrating excellent selling behaviour to a trainee who is acting as the customer.
Scenario theme: ${s.title}
Context: ${s.context}
Objectives: ${JSON.stringify(s.objectives)}

Demonstrate strong discovery, active listening, value building, product-fit reasoning, objection handling, closing, and attachment selling without sounding robotic.
Do not invent exact specs, prices, rebates, inventory, warranty terms, or codes. Ask for missing facts instead.
Keep turns concise and natural. Do not add coaching notes inside the conversation.`;
}

function transcriptToAnthropic(transcript: Array<{ role: string; content: string }>, mode: string) {
  if (mode === "bot_sells") {
    return transcript.map((t) => ({
      role: t.role === "customer" ? "user" : "assistant",
      content: t.content,
    }));
  }
  return transcript.map((t) => ({
    role: t.role === "rep" ? "user" : "assistant",
    content: t.content,
  }));
}

async function scoreRep(apiKey: string, model: string, s: Scenario, transcript: Array<{ role: string; content: string }>, compareExpert: boolean) {
  const system = `You are ApplianceIQ Performance Brain, a rigorous appliance-retail sales evaluator.
Score observable behaviour, not personality. Evidence before claims.
Use exactly these competency keys and 0-100 integer scores:
discovery, product_knowledge, recommendation, value_building, objection_handling, closing, attachment, communication, trust, process_discipline.

Scenario: ${s.title}
Context: ${s.context}
Customer profile: ${JSON.stringify(s.customer_profile)}
Hidden facts the rep could have discovered: ${JSON.stringify(s.hidden_facts)}
Expected objections: ${JSON.stringify(s.objections)}
Success criteria: ${JSON.stringify(s.success_criteria)}
Competency weights: ${JSON.stringify(s.competency_weights)}

Do not reward unsupported appliance facts. Penalize fabricated specifications, prices, warranties, stock, rebates, or installation claims.
Return JSON only with this shape:
{
 "scores":{"discovery":0,"product_knowledge":0,"recommendation":0,"value_building":0,"objection_handling":0,"closing":0,"attachment":0,"communication":0,"trust":0,"process_discipline":0},
 "feedback":"2-4 sentence coaching summary",
 "strongest_moment":"specific observed moment",
 "weakest_moment":"specific observed moment",
 "missed_opportunities":["..."],
 "better_wording":[{"instead_of":"...","try":"...","why":"..."}],
 "customer_secrets":["facts the rep did or did not uncover"],
 "target_competency":"one competency key",
 "recommended_next_action":"one concrete practice action",
 "expert_comparison":${compareExpert ? "{\"expert_approach\":\"brief better approach\",\"biggest_gap\":\"specific difference\"}" : "null"}
}`;

  const user = `Transcript:\n${transcript.map((t) => `${t.role.toUpperCase()}: ${t.content}`).join("\n")}`;
  const raw = await callAnthropic(apiKey, model, system, [{ role: "user", content: user }], 1800);
  return parseJson(raw, { scores: {}, feedback: raw.slice(0, 400) });
}

async function scoreBotSells(apiKey: string, model: string, s: Scenario, transcript: Array<{ role: string; content: string }>) {
  const system = `You are ApplianceIQ Performance Brain. Review an expert-salesperson demonstration and explain what a trainee should copy.
Scenario: ${s.title}
Return JSON only: {"summary":"2-4 sentences","techniques":["..."],"turning_points":["..."],"questions_to_copy":["..."]}`;
  const user = transcript.map((t) => `${t.role.toUpperCase()}: ${t.content}`).join("\n");
  const raw = await callAnthropic(apiKey, model, system, [{ role: "user", content: user }], 1200);
  return parseJson(raw, { summary: raw.slice(0, 500), techniques: [], turning_points: [], questions_to_copy: [] });
}

async function getNextScenario(admin: SB, organizationId: string, userId: string) {
  // Service-role clients do not carry auth.uid(), so reproduce the read-only selector here.
  const { data: states } = await admin.from("performance_skill_state")
    .select("rolling_score,confidence,last_observed_at,competency_id")
    .eq("organization_id", organizationId)
    .eq("user_id", userId)
    .order("rolling_score", { ascending: true })
    .limit(10);

  let targetCode = "discovery";
  let targetName = "Discovery";
  let targetScore: number | null = null;
  if (states?.length) {
    const first = states[0];
    const { data: competency } = await admin.from("performance_competencies")
      .select("code,name").eq("id", first.competency_id).maybeSingle();
    if (competency) {
      targetCode = competency.code;
      targetName = competency.name;
      targetScore = Number(first.rolling_score);
    }
  }

  const targetDifficulty = targetScore === null || targetScore < 55 ? 2 : targetScore < 75 ? 3 : 4;
  const { data: scenarios } = await admin.from("performance_scenarios")
    .select("id,code,title,difficulty,competency_weights")
    .eq("active", true);
  const eligible = (scenarios ?? []).filter((x) => Object.prototype.hasOwnProperty.call(x.competency_weights ?? {}, targetCode));
  eligible.sort((a, b) => {
    const d = Math.abs(Number(a.difficulty) - targetDifficulty) - Math.abs(Number(b.difficulty) - targetDifficulty);
    if (d !== 0) return d;
    return Number((b.competency_weights ?? {})[targetCode] ?? 0) - Number((a.competency_weights ?? {})[targetCode] ?? 0);
  });
  const chosen = eligible[0];
  return chosen ? {
    scenario_id: chosen.id,
    scenario_code: chosen.code,
    title: chosen.title,
    difficulty: chosen.difficulty,
    target_competency_code: targetCode,
    target_competency_name: targetName,
    target_score: targetScore,
    reason: targetScore === null ? "Baseline assessment targets core discovery behaviour." : `Adaptive practice targets ${targetName}, currently ${targetScore.toFixed(1)}/100.`,
  } : null;
}

async function callAnthropic(apiKey: string, model: string, system: string, messages: Array<{ role: string; content: string }>, maxTokens = 900): Promise<string> {
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({ model, max_tokens: maxTokens, temperature: 0.5, system, messages }),
  });
  if (!resp.ok) {
    const detail = await resp.text();
    throw new Error(`AI request failed (${resp.status}): ${detail.slice(0, 200)}`);
  }
  const data = await resp.json();
  return (data.content ?? []).filter((b: { type: string }) => b.type === "text").map((b: { text: string }) => b.text).join("").trim();
}

function parseJson(raw: string, fallback: Json) {
  try {
    return JSON.parse(raw.replace(/```json|```/g, "").trim());
  } catch {
    return fallback;
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
