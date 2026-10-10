import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// Actions: status | create_checkout | create_portal | sync_subscription
// sync_subscription rebuilds the live Stripe subscription's items from the
// org's current entitlements (seat/tier changes flow to billing automatically).

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_json" }, 400); }
  const action = body?.action;

  const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY");
  if (action === "status") return json({ ok: true, configured: !!STRIPE_KEY });
  if (!STRIPE_KEY) return json({ ok: false, error: "stripe_not_configured" });

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sbHeaders = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };

  const auth = req.headers.get("authorization") || "";
  const jwt = auth.replace(/^Bearer\s+/i, "");
  let uid: string | null = null;
  try { uid = JSON.parse(atob(jwt.split(".")[1])).sub || null; } catch {}
  if (!uid) return json({ ok: false, error: "not_authenticated" }, 401);

  const orgId = body?.organization_id;
  if (!orgId) return json({ ok: false, error: "missing_organization_id" }, 400);

  const [adminRes, memRes] = await Promise.all([
    fetch(`${SUPABASE_URL}/rest/v1/platform_admins?user_id=eq.${uid}&select=id`, { headers: sbHeaders }),
    fetch(`${SUPABASE_URL}/rest/v1/organization_members?user_id=eq.${uid}&organization_id=eq.${orgId}&role=in.(owner,admin)&status=eq.active&select=id`, { headers: sbHeaders }),
  ]);
  const isAdmin = ((await adminRes.json())?.length || 0) > 0 || ((await memRes.json())?.length || 0) > 0;
  if (!isAdmin) return json({ ok: false, error: "forbidden" }, 403);

  const orgR = await fetch(`${SUPABASE_URL}/rest/v1/organizations?id=eq.${orgId}&select=*`, { headers: sbHeaders });
  const org = (await orgR.json())?.[0];
  if (!org) return json({ ok: false, error: "org_not_found" }, 404);
  const currency = org.billing_currency || "cad";

  const stripe = (path: string, params: Record<string, string>, method = "POST") =>
    fetch(`https://api.stripe.com/v1/${path}`, {
      method,
      headers: { Authorization: `Bearer ${STRIPE_KEY}`, "Content-Type": "application/x-www-form-urlencoded" },
      body: method === "GET" ? undefined : new URLSearchParams(params),
    });

  async function ensureCustomer(): Promise<string> {
    if (org.stripe_customer_id) return org.stripe_customer_id;
    const cr = await stripe("customers", {
      name: org.name,
      ...(org.billing_email ? { email: org.billing_email } : {}),
      "metadata[organization_id]": org.id,
    });
    const cust = await cr.json();
    if (!cr.ok) throw new Error(cust?.error?.message || "stripe_customer_failed");
    await fetch(`${SUPABASE_URL}/rest/v1/organizations?id=eq.${orgId}`, {
      method: "PATCH", headers: sbHeaders, body: JSON.stringify({ stripe_customer_id: cust.id }),
    });
    return cust.id;
  }

  async function activeEntitlements(): Promise<any[]> {
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/org_app_entitlements?organization_id=eq.${orgId}&status=eq.active&select=*`,
      { headers: sbHeaders });
    const ents = await r.json();
    return Array.isArray(ents) ? ents.filter((e: any) => (e.price_cents_monthly || 0) > 0) : [];
  }

  const itemName = (e: any) => `ApplianceIQ ${e.app_key} (${e.metadata?.tier_display || e.tier})`;

  try {
    if (action === "create_portal") {
      const customer = await ensureCustomer();
      const pr = await stripe("billing_portal/sessions", {
        customer, return_url: body.return_url || "https://applianceiq-intelligence-group.netlify.app/admin.html",
      });
      const sess = await pr.json();
      if (!pr.ok) return json({ ok: false, error: sess?.error?.message || "portal_failed" });
      return json({ ok: true, url: sess.url });
    }

    if (action === "create_checkout") {
      const ents = await activeEntitlements();
      if (!ents.length) return json({ ok: false, error: "no_active_entitlements" });
      const customer = await ensureCustomer();
      const params: Record<string, string> = {
        customer, mode: "subscription",
        success_url: body.success_url || "https://applianceiq-intelligence-group.netlify.app/admin.html?billing=success",
        cancel_url: body.cancel_url || "https://applianceiq-intelligence-group.netlify.app/admin.html?billing=canceled",
        "metadata[organization_id]": orgId,
        "subscription_data[metadata][organization_id]": orgId,
      };
      ents.forEach((e: any, i: number) => {
        params[`line_items[${i}][price_data][currency]`] = currency;
        params[`line_items[${i}][price_data][recurring][interval]`] = "month";
        params[`line_items[${i}][price_data][product_data][name]`] = itemName(e);
        params[`line_items[${i}][price_data][unit_amount]`] = String(e.price_cents_monthly || 0);
        params[`line_items[${i}][quantity]`] = "1";
      });
      const cr = await stripe("checkout/sessions", params);
      const sess = await cr.json();
      if (!cr.ok) return json({ ok: false, error: sess?.error?.message || "checkout_failed" });
      return json({ ok: true, url: sess.url });
    }

    if (action === "sync_subscription") {
      const subId = org.stripe_subscription_id;
      if (!subId) return json({ ok: false, error: "no_subscription" });
      const ents = await activeEntitlements();
      if (!ents.length) return json({ ok: false, error: "no_active_entitlements" });

      // Fetch existing items
      const ir = await stripe(`subscription_items?subscription=${subId}&limit=100`, {}, "GET");
      const items = (await ir.json())?.data || [];

      // Build update: add new price_data items, delete old ones
      const params: Record<string, string> = { proration_behavior: "create_prorations" };
      let idx = 0;
      ents.forEach((e: any) => {
        params[`items[${idx}][price_data][currency]`] = currency;
        params[`items[${idx}][price_data][recurring][interval]`] = "month";
        params[`items[${idx}][price_data][product]`] = "";
        delete params[`items[${idx}][price_data][product]`];
        params[`items[${idx}][price_data][product_data][name]`] = itemName(e);
        params[`items[${idx}][price_data][unit_amount]`] = String(e.price_cents_monthly || 0);
        params[`items[${idx}][quantity]`] = "1";
        idx++;
      });
      items.forEach((it: any) => {
        params[`items[${idx}][id]`] = it.id;
        params[`items[${idx}][deleted]`] = "true";
        idx++;
      });
      const ur = await stripe(`subscriptions/${subId}`, params);
      const sub = await ur.json();
      if (!ur.ok) return json({ ok: false, error: sub?.error?.message || "sync_failed" });
      const total = ents.reduce((s: number, e: any) => s + (e.price_cents_monthly || 0), 0);
      return json({ ok: true, synced: true, monthly_cents: total, items: ents.length });
    }

    return json({ ok: false, error: "unknown_action" }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as any)?.message || e).slice(0, 200) });
  }
});
