// ai-roleplay: Practice sales scenarios against AI customer
// Turns: rep sends message → AI customer responds → rep gets KPI feedback
// Scores rep against org's custom KPIs

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401);
  const token = auth.slice(7);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const sb = createClient(url, anonKey, { global: { headers: { authorization: auth } } });
  const serviceRole = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");

  const body = await req.json() as any;
  const { session_id, action, rep_message } = body;

  // Verify user + org
  const { data: { user }, error: userErr } = await sb.auth.getUser();
  if (userErr || !user) return json({ error: "auth_failed" }, 401);

  let session = null;
  if (action === "start") {
    const { scenario_type, organization_id } = body;
    const { data: sess, error: sessErr } = await serviceRole.from("ai_roleplay_sessions").insert({
      organization_id,
      user_id: user.id,
      scenario_type,
      transcript: [],
    }).select("id").single();
    if (sessErr || !sess) return json({ error: "session_creation_failed" }, 500);
    session = sess;
  } else if (action === "message" && session_id) {
    // Fetch session
    const { data: sess, error: sessErr } = await sb.from("ai_roleplay_sessions").select("*").eq("id", session_id).single();
    if (sessErr || !sess) return json({ error: "session_not_found" }, 404);
    session = sess;

    // Append rep message to transcript
    let transcript = sess.transcript || [];
    transcript.push({ role: "rep", content: rep_message, timestamp: new Date().toISOString() });

    // Fetch org KPIs to contextualize scoring
    const { data: kpis } = await sb.from("org_kpis").select("id, kpi_name").eq("organization_id", sess.organization_id).eq("active", true);
    const kpiList = kpis?.map((k: any) => k.kpi_name) || [];

    // Fetch knowledge base
    const { data: knowledge } = await sb.from("ai_knowledge_chunks").select("content").eq("organization_id", sess.organization_id).limit(5);
    const knowledgeContext = knowledge?.map((k: any) => k.content).join("\n") || "";

    // Call Claude to generate AI customer response + KPI scoring
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) return json({ error: "anthropic_key_not_configured" }, 503);

    const prompt = `You are an AI roleplay partner in a ${sess.scenario_type} sales scenario.

The rep just said: "${rep_message}"

Company knowledge base:
${knowledgeContext}

Your job:
1. Generate a realistic customer response (2-3 sentences, conversational)
2. Score the rep's last message on these KPIs (1-10 scale): ${kpiList.join(", ")}
3. Provide a one-sentence coaching tip

Respond ONLY in this JSON format:
{"customer_response": "...", "kpi_scores": {"Discovery": 7, "Objection Handling": 8, ...}, "coaching_tip": "..."}`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": anthropicKey, "content-type": "application/json" },
      body: JSON.stringify({
        model: "claude-sonnet-4-6",
        max_tokens: 500,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      console.error("Claude error:", err);
      return json({ error: "claude_error" }, 502);
    }

    const msg = await res.json() as any;
    const responseText = msg.content?.[0]?.text ?? "";
    let aiData = {};
    try { aiData = JSON.parse(responseText); } catch { return json({ error: "parse_error" }, 500); }

    // Add AI customer response to transcript
    transcript.push({ role: "customer", content: (aiData as any).customer_response, timestamp: new Date().toISOString() });

    // Update session
    await serviceRole.from("ai_roleplay_sessions").update({
      total_turns: (session.total_turns || 0) + 1,
      transcript,
      kpi_scores: { ...(session.kpi_scores || {}), ...((aiData as any).kpi_scores || {}) },
    }).eq("id", session_id);

    return json({
      ok: true,
      customer_response: (aiData as any).customer_response,
      kpi_scores: (aiData as any).kpi_scores,
      coaching_tip: (aiData as any).coaching_tip,
    });
  } else if (action === "end" && session_id) {
    // Calculate final session score as weighted average of KPI scores
    const { data: sess } = await sb.from("ai_roleplay_sessions").select("kpi_scores").eq("id", session_id).single();
    const kpiScores = (sess as any)?.kpi_scores || {};
    const scores = Object.values(kpiScores) as number[];
    const avgScore = scores.length ? scores.reduce((a, b) => a + b, 0) / scores.length : 0;

    await serviceRole.from("ai_roleplay_sessions").update({
      status: "completed",
      session_score: parseFloat(avgScore.toFixed(2)),
      completed_at: new Date().toISOString(),
    }).eq("id", session_id);

    return json({ ok: true, session_score: avgScore });
  }

  return json({ ok: true, session_id: session?.id });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
