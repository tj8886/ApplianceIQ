import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// Stripe webhook: keeps org_app_entitlements + organizations in sync with billing.
// Set STRIPE_WEBHOOK_SECRET (whsec_...) in Edge Function Secrets, and point a
// Stripe webhook endpoint at this function's URL with events:
//   checkout.session.completed, invoice.payment_failed,
//   invoice.payment_succeeded, customer.subscription.deleted

const enc = new TextEncoder();

async function verifyStripeSig(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  try {
    const parts = Object.fromEntries(sigHeader.split(",").map((p) => p.split("=") as [string, string]));
    const t = parts["t"]; const v1 = parts["v1"];
    if (!t || !v1) return false;
    // reject stale events (>10 min) to prevent replay
    if (Math.abs(Date.now() / 1000 - Number(t)) > 600) return false;
    const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const mac = await crypto.subtle.sign("HMAC", key, enc.encode(`${t}.${payload}`));
    const hex = Array.from(new Uint8Array(mac)).map((b) => b.toString(16).padStart(2, "0")).join("");
    return hex === v1;
  } catch { return false; }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok");

  const SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const payload = await req.text();

  if (SECRET) {
    const ok = await verifyStripeSig(payload, req.headers.get("stripe-signature") || "", SECRET);
    if (!ok) return new Response(JSON.stringify({ error: "bad_signature" }), { status: 400 });
  } else {
    // No secret configured: refuse to act rather than trust unsigned input.
    return new Response(JSON.stringify({ error: "webhook_secret_not_configured" }), { status: 503 });
  }

  let event: any;
  try { event = JSON.parse(payload); } catch { return new Response("bad json", { status: 400 }); }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const h = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };
  const obj = event?.data?.object || {};
  const orgId = obj?.metadata?.organization_id
    || obj?.subscription_details?.metadata?.organization_id
    || obj?.lines?.data?.[0]?.metadata?.organization_id
    || null;

  // Resolve org by customer id if metadata missing
  async function resolveOrg(): Promise<string | null> {
    if (orgId) return orgId;
    const cust = obj?.customer;
    if (!cust) return null;
    const r = await fetch(`${SUPABASE_URL}/rest/v1/organizations?stripe_customer_id=eq.${cust}&select=id`, { headers: h });
    const rows = await r.json();
    return rows?.[0]?.id || null;
  }

  const type = event?.type;
  const oid = await resolveOrg();
  if (!oid) return new Response(JSON.stringify({ received: true, note: "no_org_resolved" }), { headers: { "Content-Type": "application/json" } });

  const patchOrg = (body: unknown) =>
    fetch(`${SUPABASE_URL}/rest/v1/organizations?id=eq.${oid}`, { method: "PATCH", headers: h, body: JSON.stringify(body) });
  const patchEnts = (from: string[], to: string) =>
    fetch(`${SUPABASE_URL}/rest/v1/org_app_entitlements?organization_id=eq.${oid}&status=in.(${from.join(",")})`,
      { method: "PATCH", headers: h, body: JSON.stringify({ status: to }) });

  if (type === "checkout.session.completed") {
    await patchOrg({ subscription_status: "active", stripe_subscription_id: obj.subscription || null });
    await patchEnts(["suspended", "trial"], "active");
  } else if (type === "invoice.payment_succeeded") {
    await patchOrg({ subscription_status: "active" });
    await patchEnts(["suspended"], "active");
  } else if (type === "invoice.payment_failed") {
    await patchOrg({ subscription_status: "past_due" });
    await patchEnts(["active"], "suspended");
  } else if (type === "customer.subscription.deleted") {
    await patchOrg({ subscription_status: "canceled", stripe_subscription_id: null });
    await patchEnts(["active", "trial", "suspended"], "canceled");
  }

  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
