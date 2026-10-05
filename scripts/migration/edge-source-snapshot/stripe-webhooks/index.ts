// stripe-webhooks — handle Stripe subscription and invoice events.
// Secret: STRIPE_WEBHOOK_SECRET (from Stripe dashboard -> Webhooks)
// Events: customer.subscription.created/updated/deleted, invoice.paid, invoice.payment_failed

import { createClient } from "jsr:@supabase/supabase-js@2";

const TIER_LIMITS: Record<string, { name: string; monthly_tokens: number }> = {
  starter: { name: "Starter", monthly_tokens: 100_000 },
  pro: { name: "Pro", monthly_tokens: 1_000_000 },
  enterprise: { name: "Enterprise", monthly_tokens: 10_000_000 },
  demo: { name: "Demo", monthly_tokens: 10_000 },
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const signature = req.headers.get("stripe-signature") ?? "";
  const body = await req.text();
  const secret = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";

  if (!secret) return json({ error: "stripe_webhook_secret_not_configured" }, 503);

  // Verify Stripe signature
  const parts = signature.split(",").reduce((acc: Record<string, string>, part) => {
    const [key, val] = part.split("=");
    acc[key] = val;
    return acc;
  }, {});
  const ts = parts.t ?? "";
  const sig = parts.v1 ?? "";
  const toSign = `${ts}.${body}`;
  const encoder = new TextEncoder();
  const msgBytes = encoder.encode(toSign);
  const keyBytes = encoder.encode(secret);

  try {
    const hmac = await crypto.subtle.importKey("raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const computed = await crypto.subtle.sign("HMAC", hmac, msgBytes);
    const computedHex = Array.from(new Uint8Array(computed)).map((b) => b.toString(16).padStart(2, "0")).join("");
    if (computedHex !== sig) return json({ error: "invalid_signature" }, 401);
  } catch (e) {
    return json({ error: String(e) }, 401);
  }

  let event: { id: string; type: string; data: { object: Record<string, any> } };
  try { event = JSON.parse(body); } catch { return json({ error: "invalid_json" }, 400); }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, serviceKey);

  const obj = event.data.object;
  let orgId: string | null = null;

  // Map Stripe customer to org
  if (obj.customer) {
    const { data: org } = await admin.from("organizations").select("id").eq("stripe_customer_id", obj.customer).single();
    orgId = org?.id ?? null;
  }

  // Log the event
  await admin.from("stripe_events").insert({
    organization_id: orgId,
    event_type: event.type,
    event_id: event.id,
    object_id: obj.id,
    payload: obj,
  });

  // Handle subscription events
  if (event.type === "customer.subscription.created" || event.type === "customer.subscription.updated") {
    if (!orgId) return json({ ok: true, note: "subscription event but no org mapping" }, 200);

    const subId = obj.id;
    const priceId = obj.items?.data?.[0]?.price?.id ?? "";
    const status = obj.status;

    // Map Stripe price ID to tier (you'll set these in Stripe dashboard)
    // For now, infer from metadata or default to starter
    const tier = obj.metadata?.tier ?? "starter";
    const limits = TIER_LIMITS[tier];

    await admin.from("organizations").update({
      stripe_subscription_id: subId,
      subscription_status: status,
      tier: tier,
      trial_ends_at: obj.trial_end ? new Date(obj.trial_end * 1000).toISOString() : null,
    }).eq("id", orgId);

    await admin.from("ai_token_limits").upsert({
      organization_id: orgId,
      tier: tier,
      monthly_limit: limits.monthly_tokens,
      tokens_used_this_month: 0,
      reset_date: new Date(Date.now() + 30 * 86400000).toISOString().split("T")[0],
    });
  }

  if (event.type === "customer.subscription.deleted") {
    if (!orgId) return json({ ok: true, note: "subscription deleted but no org mapping" }, 200);
    await admin.from("organizations").update({
      subscription_status: "canceled",
      canceled_at: new Date().toISOString(),
    }).eq("id", orgId);
  }

  if (event.type === "invoice.payment_failed") {
    if (!orgId) return json({ ok: true, note: "payment failed but no org mapping" }, 200);
    await admin.from("organizations").update({ subscription_status: "past_due" }).eq("id", orgId);
  }

  if (event.type === "invoice.paid") {
    if (!orgId) return json({ ok: true, note: "invoice paid but no org mapping" }, 200);
    await admin.from("organizations").update({ subscription_status: "active" }).eq("id", orgId);
  }

  return json({ ok: true, event_id: event.id });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
