// ai-feedback v1 — Explicit feedback collection + learning triggers
//
// Called by client apps when a user:
//   - Thumbs up/down a response
//   - Submits a correction
//   - Reports a wrong answer
//
// Side effects:
//   - Logs to ai_feedback_signals
//   - Updates ai_user_preferences (aggregate counters)
//   - Auto-detects knowledge gaps from negative feedback
//   - Updates ai_routing_weights success/failure counts

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

type Json = Record<string, unknown>;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const VALID_SIGNALS = new Set([
  "thumbs_up", "thumbs_down", "correction", "persona_switch",
  "tier_override", "follow_up_clarification", "rephrase",
  "abandoned", "deterministic_escalation", "outcome_positive",
  "outcome_negative", "custom",
]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ ok: false, detail: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply({ ok: false, detail: "authentication_required" }, 401);

  let body: Json;
  try { body = await req.json(); } catch { return reply({ ok: false, detail: "invalid_json" }, 400); }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const userRes = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: anon },
  });
  if (!userRes.ok) return reply({ ok: false, detail: "invalid_session" }, 401);
  const user = await userRes.json();
  const userId = user.id as string;

  const admin = createClient(url, service);

  const signals = Array.isArray(body.signals) ? body.signals as Json[] : [body];
  const results: Json[] = [];

  for (const signal of signals) {
    const signalType = String(signal.signal_type ?? "").trim();
    if (!VALID_SIGNALS.has(signalType)) {
      results.push({ ok: false, detail: `invalid signal_type: ${signalType}` });
      continue;
    }

    const conversationId = signal.conversation_id ? String(signal.conversation_id) : null;
    const turnId = signal.turn_id ? String(signal.turn_id) : null;
    const organizationId = signal.organization_id ? String(signal.organization_id) : null;
    const routingSnapshot = isObject(signal.routing_snapshot) ? signal.routing_snapshot : {};
    const correctionText = signal.correction_text ? String(signal.correction_text) : null;
    const metadata = isObject(signal.metadata) ? signal.metadata : {};

    const { error: insertErr } = await admin.from("ai_feedback_signals").insert({
      conversation_id: conversationId, turn_id: turnId, user_id: userId,
      organization_id: organizationId, signal_type: signalType,
      routing_snapshot: routingSnapshot, correction_text: correctionText, metadata,
    });

    if (insertErr) { results.push({ ok: false, detail: insertErr.message }); continue; }

    updateUserPreferences(admin, userId, organizationId, signalType).catch(() => {});

    if (routingSnapshot && (routingSnapshot as Json).tier) {
      updateRoutingWeights(admin, signalType, routingSnapshot as Json, organizationId, userId).catch(() => {});
    }

    if (["thumbs_down", "correction"].includes(signalType) && conversationId) {
      detectKnowledgeGap(admin, conversationId, turnId, correctionText, organizationId).catch(() => {});
    }

    results.push({ ok: true, signal_type: signalType });
  }

  return reply({ ok: results.every((r) => r.ok), results, signals_processed: results.length });
});

async function updateUserPreferences(
  admin: ReturnType<typeof createClient>, userId: string, organizationId: string | null, signalType: string,
) {
  const { data: existing } = await admin.from("ai_user_preferences").select("*").eq("user_id", userId).maybeSingle();
  const now = new Date().toISOString();
  if (existing) {
    const updates: Json = { last_active_at: now, updated_at: now };
    if (signalType === "thumbs_up") updates.total_thumbs_up = (existing.total_thumbs_up ?? 0) + 1;
    else if (signalType === "thumbs_down") updates.total_thumbs_down = (existing.total_thumbs_down ?? 0) + 1;
    else if (signalType === "correction") updates.total_corrections = (existing.total_corrections ?? 0) + 1;
    await admin.from("ai_user_preferences").update(updates).eq("user_id", userId);
  } else {
    await admin.from("ai_user_preferences").insert({
      user_id: userId, organization_id: organizationId,
      total_conversations: 0,
      total_thumbs_up: signalType === "thumbs_up" ? 1 : 0,
      total_thumbs_down: signalType === "thumbs_down" ? 1 : 0,
      total_corrections: signalType === "correction" ? 1 : 0,
      last_active_at: now,
    });
  }
}

async function updateRoutingWeights(
  admin: ReturnType<typeof createClient>, signalType: string, routingSnapshot: Json,
  organizationId: string | null, _userId: string,
) {
  const tier = String(routingSnapshot.tier ?? routingSnapshot.auto_detected ?? "");
  const reason = String(routingSnapshot.reason ?? "");
  if (!tier || !reason) return;
  const keyword = reason.split("_")[0] || reason;
  const isSuccess = ["thumbs_up", "outcome_positive"].includes(signalType);
  const isFailure = ["thumbs_down", "correction", "rephrase", "deterministic_escalation"].includes(signalType);
  if (!isSuccess && !isFailure) return;

  const { data: existing } = await admin.from("ai_routing_weights")
    .select("id,success_count,failure_count")
    .eq("signal_keyword", keyword).eq("current_tier", tier)
    .filter("organization_id", organizationId ? "eq" : "is", organizationId ?? null as unknown as string)
    .filter("user_id", "is", null as unknown as string)
    .maybeSingle();

  const now = new Date().toISOString();
  if (existing) {
    const successCount = (existing.success_count ?? 0) + (isSuccess ? 1 : 0);
    const failureCount = (existing.failure_count ?? 0) + (isFailure ? 1 : 0);
    const total = successCount + failureCount;
    const successRate = total > 0 ? successCount / total : 0.5;
    let recommendedTier: string | null = null;
    let confidence = 0;
    if (total >= 10 && successRate < 0.5) {
      recommendedTier = tier === "fast" ? "standard" : tier === "standard" ? "strong" : null;
      confidence = Math.min(1, (total - 10) / 50) * (1 - successRate);
    }
    await admin.from("ai_routing_weights").update({
      success_count: successCount, failure_count: failureCount,
      success_rate: Number(successRate.toFixed(4)),
      recommended_tier: recommendedTier, confidence: Number(confidence.toFixed(4)),
      last_computed_at: now, updated_at: now,
    }).eq("id", existing.id);
  } else {
    await admin.from("ai_routing_weights").insert({
      signal_keyword: keyword, current_tier: tier, organization_id: organizationId,
      user_id: null, success_count: isSuccess ? 1 : 0, failure_count: isFailure ? 1 : 0,
      success_rate: isSuccess ? 1 : 0, last_computed_at: now,
    });
  }
}

async function detectKnowledgeGap(
  admin: ReturnType<typeof createClient>, conversationId: string,
  turnId: string | null, correctionText: string | null, organizationId: string | null,
) {
  let turnContent = "";
  let userMessage = "";
  if (turnId) {
    const { data: turn } = await admin.from("ai_conversation_turns").select("content,metadata").eq("id", turnId).maybeSingle();
    turnContent = String(turn?.content ?? "");
  }
  const { data: turns } = await admin.from("ai_conversation_turns").select("content,role")
    .eq("conversation_id", conversationId).eq("role", "user").order("created_at", { ascending: false }).limit(1);
  userMessage = String(turns?.[0]?.content ?? "");
  if (!userMessage) return;

  const gapIndicators = ["don't have", "no data", "not found", "couldn't find", "no records", "check product iq", "no warranty", "no recall", "no contact", "not in", "unavailable"];
  const hasGapIndicator = gapIndicators.some((g) => turnContent.toLowerCase().includes(g));
  const hasCorrection = correctionText && correctionText.length > 10;
  if (!hasGapIndicator && !hasCorrection) return;

  const brandMatch = userMessage.match(/\b(Bosch|Samsung|LG|Whirlpool|KitchenAid|GE|Frigidaire|Maytag|Miele|Sub-Zero|Wolf|Thermador|Viking|JennAir|Fisher & Paykel|Bertazzoni|Dacor|Electrolux|AGA|Smeg|Liebherr|Gaggenau|Blomberg|Beko|Haier|Caf\u00e9|Monogram|Profile|Speed Queen|Asko|Broan|Zephyr|Best|Faber|Cove)\b/i);
  const modelMatch = userMessage.match(/\b[A-Z]{2,5}[A-Z0-9-]{4,}\b/);
  let category = "general";
  const lower = userMessage.toLowerCase();
  if (lower.includes("warranty")) category = "warranty";
  else if (lower.includes("recall")) category = "recall";
  else if (lower.includes("spec") || lower.includes("dimension")) category = "specs";
  else if (lower.includes("contact") || lower.includes("phone")) category = "contact";
  else if (lower.includes("install")) category = "installation";
  else if (lower.includes("price")) category = "pricing";

  const brandName = brandMatch?.[1] ?? null;
  if (brandName) {
    const { data: existingGap } = await admin.from("ai_knowledge_gaps")
      .select("id,occurrence_count,sample_conversation_ids")
      .eq("brand_name", brandName).eq("query_category", category).eq("status", "open").maybeSingle();
    if (existingGap) {
      const sampleIds = Array.isArray(existingGap.sample_conversation_ids) ? existingGap.sample_conversation_ids : [];
      if (!sampleIds.includes(conversationId) && sampleIds.length < 10) sampleIds.push(conversationId);
      await admin.from("ai_knowledge_gaps").update({
        occurrence_count: (existingGap.occurrence_count ?? 1) + 1,
        last_seen_at: new Date().toISOString(), sample_conversation_ids: sampleIds,
        updated_at: new Date().toISOString(),
      }).eq("id", existingGap.id);
      return;
    }
  }
  await admin.from("ai_knowledge_gaps").insert({
    query_text: userMessage.slice(0, 500), query_category: category,
    brand_name: brandName, model_number: modelMatch?.[0] ?? null,
    topic: correctionText ? correctionText.slice(0, 200) : category,
    occurrence_count: 1, sample_conversation_ids: [conversationId],
    organization_id: organizationId, status: "open",
  });
}

function isObject(v: unknown): v is Json { return !!v && typeof v === "object" && !Array.isArray(v); }
function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
