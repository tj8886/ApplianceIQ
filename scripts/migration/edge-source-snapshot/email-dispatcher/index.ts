// email-dispatcher — outbound CRM email via Resend.
// Auth: user JWT; membership verified against organization_members through RLS.
// Chain: crm_emails row (queued) -> Resend send -> status sent/failed -> activity row.
// Secrets: RESEND_API_KEY (required), EMAIL_FROM (optional; defaults to Resend onboarding sender).

import { createClient } from "jsr:@supabase/supabase-js@2";

const MAX_BODY_CHARS = 50_000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const orgId = String(body.organization_id ?? "");
  const toEmail = String(body.to_email ?? "").trim();
  const subject = String(body.subject ?? "").trim().slice(0, 300);
  const text = String(body.body ?? "").trim().slice(0, MAX_BODY_CHARS);
  const recordType = body.crm_record_type ? String(body.crm_record_type) : null;
  const recordId = body.crm_record_id ? String(body.crm_record_id) : null;
  const recordLabel = body.record_label ? String(body.record_label).slice(0, 200) : null;

  if (!orgId || !toEmail || !subject || !text) return json({ error: "organization_id_to_subject_body_required" }, 400);
  if (!EMAIL_RE.test(toEmail)) return json({ error: "invalid_recipient_email" }, 400);
  if (recordType && !["deal", "contact", "company"].includes(recordType)) return json({ error: "invalid_crm_record_type" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey);

  // Tenant check: caller must be a member of the org (verified as the user, through RLS)
  const { data: userData } = await userClient.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return json({ error: "authentication_required" }, 401);
  const { data: membership } = await userClient
    .from("organization_members").select("user_id")
    .eq("organization_id", orgId).eq("user_id", userId).maybeSingle();
  if (!membership) return json({ error: "not_a_member_of_organization" }, 403);

  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const fromEmail = Deno.env.get("EMAIL_FROM") ?? "ApplianceIQ <onboarding@resend.dev>";

  // 1. Log the email first (queued) so nothing is lost on transport failure
  const { data: emailRow, error: insErr } = await admin.from("crm_emails").insert({
    organization_id: orgId, user_id: userId,
    to_email: toEmail, from_email: fromEmail, subject, body: text,
    status: "queued", sent_at: new Date().toISOString(),
    metadata: { crm_record_type: recordType, crm_record_id: recordId, transport: "resend" },
  }).select("id").single();
  if (insErr || !emailRow) return json({ error: "email_log_failed", detail: insErr?.message }, 500);

  if (!resendKey) {
    await admin.from("crm_emails").update({ status: "failed", metadata: { last_error: "resend_api_key_not_configured" } }).eq("id", emailRow.id);
    return json({ error: "resend_api_key_not_configured", detail: "Add RESEND_API_KEY to Supabase Edge Function secrets (resend.com → API Keys)." }, 503);
  }

  // 2. Send via Resend
  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${resendKey}` },
    body: JSON.stringify({ from: fromEmail, to: [toEmail], subject, text }),
  });
  const respBody = await resp.json().catch(() => ({}));

  if (!resp.ok) {
    const detail = String(respBody?.message ?? JSON.stringify(respBody)).slice(0, 400);
    await admin.from("crm_emails").update({
      status: "failed",
      metadata: { crm_record_type: recordType, crm_record_id: recordId, transport: "resend", last_error: detail },
    }).eq("id", emailRow.id);
    return json({ error: "send_failed", detail, email_id: emailRow.id }, 502);
  }

  const providerId = String(respBody?.id ?? "");
  await admin.from("crm_emails").update({ status: "sent", provider_message_id: providerId, sent_at: new Date().toISOString() }).eq("id", emailRow.id);

  // 3. CRM activity (timeline entry; enables later AI review via activity-analyzer)
  const { data: act } = await admin.from("activities").insert({
    organization_id: orgId, user_id: userId, actor_user_id: userId,
    entity_type: recordType ?? "unattached", entity_id: recordId,
    activity_type: "email", source: "email_integration",
    title: `Email — ${recordLabel ?? toEmail}: ${subject.slice(0, 80)}`,
    related_email_id: emailRow.id, metadata: {},
  }).select("id").single();

  await admin.from("ai_audit_events").insert({
    organization_id: orgId, event_type: "crm.email.sent",
    event_payload: { email_id: emailRow.id, activity_id: act?.id, to: toEmail, provider_message_id: providerId },
  });

  return json({ ok: true, email_id: emailRow.id, activity_id: act?.id, provider_message_id: providerId });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
