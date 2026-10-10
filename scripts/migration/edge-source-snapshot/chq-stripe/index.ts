import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// ── CONTAINMENT 2026-08-20 (v6) ──────────────────────────────────────────
// v4 ran with verify_jwt=false and NO authentication of any kind. STRIPE_SECRET_KEY
// is currently NOT configured (probe returned 503), so no Stripe call was reachable
// in practice - but the code path is live the moment that secret is set.
// v5 added the gate; v6 moves it ABOVE the stripe_not_configured check so that
// configuration state is not disclosed pre-auth and the gate is observable.
// Business logic is byte-for-byte v4. Original preserved at
// tj-preservation/edge/sources/chq-stripe.v4.ORIGINAL.ts (sha256 53bb9a7a44c8...).
//
//   FINANCIAL actions -> service_role only
//   CUSTOMER actions  -> authenticated end user (or service_role)
//   anonymous         -> nothing

const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SITE = "https://contractorhq-app.netlify.app";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const FINANCIAL = new Set(["connect_onboarding", "connect_status", "process_payout", "process_all_payouts"]);
const CUSTOMER = new Set(["create_checkout", "contractor_subscription"]);

function bearer(req: Request): string {
  const h = req.headers.get("authorization") ?? "";
  return h.toLowerCase().startsWith("bearer ") ? h.slice(7).trim() : "";
}

function isServiceRole(req: Request): boolean {
  const t = bearer(req);
  return t.length > 0 && SERVICE_KEY.length > 0 && t === SERVICE_KEY;
}

async function isAuthenticatedUser(req: Request): Promise<boolean> {
  const t = bearer(req);
  if (!t || !ANON_KEY) return false;
  if (t === ANON_KEY) return false; // the anon key is public - it is not a user
  try {
    const c = createClient(SUPABASE_URL, ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await c.auth.getUser(t);
    return !!data?.user && !error;
  } catch { return false; }
}

function stripeAPI(path: string, params: Record<string, string>, method = "POST") {
  return fetch(`https://api.stripe.com/v1/${path}`, {
    method,
    headers: { Authorization: `Bearer ${STRIPE_KEY}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: method === "GET" ? undefined : new URLSearchParams(params),
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const action = body?.action;

  // ── auth gate: FIRST, before any configuration or Stripe state is revealed ──────
  if (!FINANCIAL.has(action) && !CUSTOMER.has(action)) return json({ error: "unknown_action" }, 400);
  const svc = isServiceRole(req);
  if (FINANCIAL.has(action)) {
    if (!svc) return json({ error: "forbidden", detail: "this action requires service-role credentials" }, 403);
  } else if (!svc && !(await isAuthenticatedUser(req))) {
    return json({ error: "unauthorized", detail: "sign-in required" }, 401);
  }
  // ───────────────────────────────────────────────────────────────────

  if (!STRIPE_KEY) return json({ error: "stripe_not_configured" }, 503);

  const admin = createClient(SUPABASE_URL, SERVICE_KEY);

  try {
    if (action === "create_checkout") {
      const b = body.booking;
      if (!b) return json({ error: "missing_booking" }, 400);
      const params: Record<string, string> = {
        mode: "payment",
        success_url: `${SITE}?booking=success&id=${b.booking_number}`,
        cancel_url: `${SITE}?booking=canceled`,
        "metadata[booking_id]": b.id || "",
        "metadata[booking_number]": b.booking_number || "",
        "metadata[type]": "chq_booking",
        "line_items[0][price_data][currency]": b.currency || "cad",
        "line_items[0][price_data][product_data][name]": b.service_name || "Service",
        "line_items[0][price_data][product_data][description]": `ContractorHQ Booking ${b.booking_number}`,
        "line_items[0][price_data][unit_amount]": String(Math.round((b.retail_price || 0) * 100)),
        "line_items[0][quantity]": "1",
        "automatic_tax[enabled]": "true",
      };
      if (b.rush_fee && b.rush_fee > 0) {
        params["line_items[1][price_data][currency]"] = b.currency || "cad";
        params["line_items[1][price_data][product_data][name]"] = "Rush Booking Fee";
        params["line_items[1][price_data][unit_amount]"] = String(Math.round(b.rush_fee * 100));
        params["line_items[1][quantity]"] = "1";
      }
      if (b.job_protection_fee && b.job_protection_fee > 0) {
        const idx = b.rush_fee > 0 ? 2 : 1;
        params[`line_items[${idx}][price_data][currency]`] = b.currency || "cad";
        params[`line_items[${idx}][price_data][product_data][name]`] = "Job Protection";
        params[`line_items[${idx}][price_data][unit_amount]`] = String(Math.round(b.job_protection_fee * 100));
        params[`line_items[${idx}][quantity]`] = "1";
      }
      if (b.customer_email) params.customer_email = b.customer_email;
      const res = await stripeAPI("checkout/sessions", params);
      const sess = await res.json();
      if (!res.ok) return json({ error: sess?.error?.message || "checkout_failed" }, 400);
      if (b.id) {
        await admin.from("chq_bookings").update({ stripe_payment_intent_id: sess.payment_intent }).eq("id", b.id);
      }
      return json({ ok: true, url: sess.url, session_id: sess.id });
    }

    if (action === "connect_onboarding") {
      const contractorId = body.contractor_id;
      if (!contractorId) return json({ error: "missing_contractor_id" }, 400);
      const { data: contractor } = await admin.from("chq_contractors").select("*").eq("id", contractorId).single();
      if (!contractor) return json({ error: "contractor_not_found" }, 404);
      let accountId = contractor.stripe_account_id;
      if (!accountId) {
        const acctRes = await stripeAPI("accounts", {
          type: "express",
          country: contractor.currency === "USD" ? "US" : "CA",
          email: contractor.email,
          "capabilities[card_payments][requested]": "true",
          "capabilities[transfers][requested]": "true",
          "business_profile[name]": contractor.company_name,
          "metadata[contractor_id]": contractorId,
          "metadata[type]": "chq_contractor",
        });
        const acct = await acctRes.json();
        if (!acctRes.ok) return json({ error: acct?.error?.message || "account_failed" }, 400);
        accountId = acct.id;
        await admin.from("chq_contractors").update({ stripe_account_id: accountId }).eq("id", contractorId);
      }
      const linkRes = await stripeAPI("account_links", {
        account: accountId,
        refresh_url: `${SITE}/contractors?stripe=retry`,
        return_url: `${SITE}/contractors?stripe=complete`,
        type: "account_onboarding",
      });
      const link = await linkRes.json();
      if (!linkRes.ok) return json({ error: link?.error?.message || "link_failed" }, 400);
      return json({ ok: true, url: link.url, account_id: accountId });
    }

    if (action === "connect_status") {
      const contractorId = body.contractor_id;
      const { data: contractor } = await admin.from("chq_contractors").select("stripe_account_id").eq("id", contractorId).single();
      if (!contractor?.stripe_account_id) return json({ ok: true, connected: false });
      const res = await stripeAPI(`accounts/${contractor.stripe_account_id}`, {}, "GET");
      const acct = await res.json();
      const ready = acct.charges_enabled && acct.payouts_enabled;
      if (ready) {
        await admin.from("chq_contractors").update({
          stripe_onboarding_complete: true,
          stripe_payouts_enabled: true,
        }).eq("id", contractorId);
      }
      return json({ ok: true, connected: ready, charges_enabled: acct.charges_enabled, payouts_enabled: acct.payouts_enabled });
    }

    if (action === "process_payout") {
      const bookingId = body.booking_id;
      const { data: booking } = await admin.from("chq_bookings").select("*").eq("id", bookingId).single();
      if (!booking) return json({ error: "booking_not_found" }, 404);
      if (!booking.payout_eligible_at) return json({ error: "payout_not_eligible" }, 400);
      if (new Date(booking.payout_eligible_at) > new Date()) return json({ error: "payout_hold_not_expired", eligible_at: booking.payout_eligible_at }, 400);
      const { data: contractor } = await admin.from("chq_contractors").select("stripe_account_id").eq("id", booking.contractor_id).single();
      if (!contractor?.stripe_account_id) return json({ error: "contractor_not_connected" }, 400);
      const amount = Math.round(booking.contractor_price * 100);
      const xferRes = await stripeAPI("transfers", {
        amount: String(amount),
        currency: booking.currency?.toLowerCase() || "cad",
        destination: contractor.stripe_account_id,
        "metadata[booking_id]": bookingId,
        "metadata[booking_number]": booking.booking_number,
        "metadata[type]": "chq_contractor_payout",
      });
      const xfer = await xferRes.json();
      if (!xferRes.ok) return json({ error: xfer?.error?.message || "transfer_failed" }, 400);
      await admin.from("chq_payouts").insert({
        booking_id: bookingId,
        payee_type: "contractor",
        payee_id: booking.contractor_id,
        amount: booking.contractor_price,
        currency: booking.currency || "CAD",
        status: "paid",
        stripe_transfer_id: xfer.id,
        paid_at: new Date().toISOString(),
        payout_method: "stripe_connect",
      });
      const platformAmount = booking.retail_price * (booking.platform_pct / 100);
      await admin.from("chq_payouts").insert({
        booking_id: bookingId,
        payee_type: "platform",
        payee_id: bookingId,
        amount: platformAmount,
        currency: booking.currency || "CAD",
        status: "paid",
        paid_at: new Date().toISOString(),
        payout_method: "stripe_connect",
      });
      if (booking.retailer_pct > 0 && booking.retailer_id) {
        await admin.from("chq_payouts").insert({
          booking_id: bookingId,
          payee_type: "retailer",
          payee_id: booking.retailer_id,
          amount: booking.retail_price * (booking.retailer_pct / 100),
          currency: booking.currency || "CAD",
          status: "pending",
          payout_method: "manual",
        });
      }
      if (booking.rep_pct > 0 && booking.rep_id) {
        await admin.from("chq_payouts").insert({
          booking_id: bookingId,
          payee_type: "rep",
          payee_id: booking.rep_id,
          amount: booking.retail_price * (booking.rep_pct / 100),
          currency: booking.currency || "CAD",
          status: "pending",
          payout_method: "manual",
        });
      }
      return json({ ok: true, transfer_id: xfer.id, contractor_paid: booking.contractor_price });
    }

    if (action === "process_all_payouts") {
      const now = new Date().toISOString();
      const { data: eligible } = await admin.from("chq_bookings")
        .select("id")
        .lte("payout_eligible_at", now)
        .eq("status", "completed")
        .is("stripe_charge_id", null);
      if (!eligible || eligible.length === 0) return json({ ok: true, processed: 0 });
      let processed = 0;
      for (const b of eligible) {
        try {
          // CONTAINMENT: the self-call must carry service-role credentials, or the
          // new gate rejects it (v4 sent no Authorization header at all).
          const res = await fetch(req.url, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${SERVICE_KEY}`,
              "apikey": SERVICE_KEY,
            },
            body: JSON.stringify({ action: "process_payout", booking_id: b.id }),
          });
          if (res.ok) processed++;
        } catch (e) {
          console.error(`Payout failed for ${b.id}:`, e);
        }
      }
      return json({ ok: true, processed, total_eligible: eligible.length });
    }

    if (action === "contractor_subscription") {
      const contractorId = body.contractor_id;
      const tier = body.tier || "pro";
      const { data: contractor } = await admin.from("chq_contractors").select("*").eq("id", contractorId).single();
      if (!contractor) return json({ error: "contractor_not_found" }, 404);
      const prices: Record<string, number> = { pro: 4900, elite: 14900 };
      const names: Record<string, string> = { pro: "ContractorHQ Pro", elite: "ContractorHQ Elite" };
      if (!prices[tier]) return json({ error: "invalid_tier" }, 400);
      const params: Record<string, string> = {
        mode: "subscription",
        success_url: `${SITE}/contractors?subscription=success`,
        cancel_url: `${SITE}/contractors?subscription=canceled`,
        customer_email: contractor.email,
        "metadata[contractor_id]": contractorId,
        "metadata[tier]": tier,
        "metadata[type]": "chq_subscription",
        "line_items[0][price_data][currency]": "usd",
        "line_items[0][price_data][recurring][interval]": "month",
        "line_items[0][price_data][product_data][name]": names[tier],
        "line_items[0][price_data][product_data][description]": tier === "pro" ? "Unlimited bids, analytics, verified badge, direct booking link" : "Priority listing, commercial access, CRM tools, all Pro features",
        "line_items[0][price_data][unit_amount]": String(prices[tier]),
        "line_items[0][quantity]": "1",
      };
      const res = await stripeAPI("checkout/sessions", params);
      const sess = await res.json();
      if (!res.ok) return json({ error: sess?.error?.message || "checkout_failed" }, 400);
      return json({ ok: true, url: sess.url });
    }

    return json({ error: "unknown_action" }, 400);
  } catch (e) {
    console.error("chq-stripe error:", e);
    return json({ error: String((e as any)?.message || e).slice(0, 300) }, 500);
  }
});
