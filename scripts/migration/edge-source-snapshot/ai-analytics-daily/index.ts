// ai-analytics-daily v1 — Daily rollup of bot usage, cost, quality signals
// Run via cron or manual trigger. Aggregates yesterday's data into ai_daily_analytics.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service);

  // Default to yesterday, allow override
  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* empty body ok */ }
  const targetDate = body.date
    ? String(body.date)
    : new Date(Date.now() - 86400000).toISOString().split("T")[0];

  const dayStart = targetDate + "T00:00:00Z";
  const dayEnd = targetDate + "T23:59:59.999Z";

  // Get all orgs that had activity
  const { data: turns } = await admin
    .from("ai_conversation_turns")
    .select("conversation_id,role,persona_name,metadata,created_at")
    .gte("created_at", dayStart)
    .lte("created_at", dayEnd);

  if (!turns?.length) {
    return new Response(JSON.stringify({ ok: true, date: targetDate, message: "no_activity" }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  // Get conversations for org mapping
  const convIds = [...new Set(turns.map((t: any) => t.conversation_id).filter(Boolean))];
  const { data: convs } = await admin
    .from("ai_conversations")
    .select("id,organization_id,user_id")
    .in("id", convIds.slice(0, 500));
  const convMap = new Map((convs ?? []).map((c: any) => [c.id, c]));

  // Get feedback signals for the day
  const { data: feedback } = await admin
    .from("ai_feedback_signals")
    .select("signal_type,organization_id,routing_snapshot")
    .gte("created_at", dayStart)
    .lte("created_at", dayEnd);

  // Get knowledge gaps detected
  const { data: gaps } = await admin
    .from("ai_knowledge_gaps")
    .select("id")
    .gte("last_seen_at", dayStart)
    .lte("last_seen_at", dayEnd);

  // Aggregate by org
  const orgStats: Record<string, any> = {};

  for (const turn of turns) {
    if (turn.role !== "assistant") continue;
    const conv = convMap.get(turn.conversation_id);
    const orgId = conv?.organization_id ?? "global";
    if (!orgStats[orgId]) {
      orgStats[orgId] = {
        total: 0, deterministic: 0, fast: 0, standard: 0, strong: 0,
        failover: 0, cost: 0, fast_cost: 0, standard_cost: 0, strong_cost: 0,
        up: 0, down: 0, corrections: 0, personas: {} as Record<string, number>,
        users: new Set(),
      };
    }
    const s = orgStats[orgId];
    s.total++;
    const meta = turn.metadata ?? {};
    const tier = meta.tier ?? "unknown";
    if (tier === "deterministic") s.deterministic++;
    else if (tier === "fast") { s.fast++; s.fast_cost += (meta.total_cost_usd ?? 0); }
    else if (tier === "standard") { s.standard++; s.standard_cost += (meta.total_cost_usd ?? 0); }
    else if (tier === "strong") { s.strong++; s.strong_cost += (meta.total_cost_usd ?? 0); }
    s.cost += (meta.total_cost_usd ?? 0);
    if (meta.failover_used) s.failover++;
    const pn = turn.persona_name ?? "unknown";
    s.personas[pn] = (s.personas[pn] ?? 0) + 1;
    if (conv?.user_id) s.users.add(conv.user_id);
  }

  // Add feedback counts
  for (const fb of (feedback ?? [])) {
    const orgId = fb.organization_id ?? "global";
    if (!orgStats[orgId]) continue;
    if (fb.signal_type === "thumbs_up") orgStats[orgId].up++;
    if (fb.signal_type === "thumbs_down") orgStats[orgId].down++;
    if (fb.signal_type === "correction") orgStats[orgId].corrections++;
  }

  // Upsert daily analytics
  const upserts = [];
  for (const [orgId, s] of Object.entries(orgStats) as [string, any][]) {
    const total_fb = s.up + s.down;
    upserts.push({
      analytics_date: targetDate,
      organization_id: orgId === "global" ? null : orgId,
      total_requests: s.total,
      deterministic_requests: s.deterministic,
      fast_tier_requests: s.fast,
      standard_tier_requests: s.standard,
      strong_tier_requests: s.strong,
      failover_count: s.failover,
      total_cost_usd: Number(s.cost.toFixed(6)),
      fast_cost_usd: Number(s.fast_cost.toFixed(6)),
      standard_cost_usd: Number(s.standard_cost.toFixed(6)),
      strong_cost_usd: Number(s.strong_cost.toFixed(6)),
      thumbs_up_count: s.up,
      thumbs_down_count: s.down,
      correction_count: s.corrections,
      satisfaction_rate: total_fb > 0 ? Number((s.up / total_fb).toFixed(4)) : 0,
      persona_distribution: s.personas,
      knowledge_gaps_detected: gaps?.length ?? 0,
      active_users: s.users.size,
      updated_at: new Date().toISOString(),
    });
  }

  for (const row of upserts) {
    // Check if exists
    const orgFilter = row.organization_id
      ? admin.from("ai_daily_analytics").select("id").eq("analytics_date", targetDate).eq("organization_id", row.organization_id).maybeSingle()
      : admin.from("ai_daily_analytics").select("id").eq("analytics_date", targetDate).is("organization_id", null).maybeSingle();
    const { data: existing } = await orgFilter;
    if (existing) {
      await admin.from("ai_daily_analytics").update(row).eq("id", existing.id);
    } else {
      await admin.from("ai_daily_analytics").insert(row);
    }
  }

  return new Response(JSON.stringify({
    ok: true,
    date: targetDate,
    orgs_processed: Object.keys(orgStats).length,
    total_turns_processed: turns.length,
  }), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
