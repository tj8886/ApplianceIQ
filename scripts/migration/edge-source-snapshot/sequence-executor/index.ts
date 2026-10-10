// sequence-executor — Cron-triggered auto-execution of sequence steps.
// Finds due enrollments, sends emails via Resend, advances step.
// Call via cron or manual trigger. No JWT (webhook-style).

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  // Optional auth via shared secret for cron security
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret) {
    const auth = req.headers.get("Authorization") ?? "";
    if (auth !== `Bearer ${cronSecret}`) return json({ error: "unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const fromEmail = Deno.env.get("EMAIL_FROM") ?? "ApplianceIQ <onboarding@resend.dev>";
  const admin = createClient(url, serviceKey);

  if (!resendKey) return json({ error: "RESEND_API_KEY not configured" }, 503);

  // Get all orgs with active enrollments
  const { data: orgs } = await admin
    .from("aicrm_sequence_enrollments")
    .select("organization_id")
    .eq("status", "active")
    .limit(100);
  const orgIds = [...new Set((orgs ?? []).map(o => o.organization_id))];

  let totalSent = 0;
  let totalErrors = 0;
  const results: Record<string, unknown>[] = [];

  for (const orgId of orgIds) {
    const { data: dueSteps } = await admin.rpc("get_due_sequence_steps", { p_org_id: orgId });
    if (!dueSteps?.length) continue;

    for (const step of dueSteps) {
      try {
        // Get contact details for merge fields
        const { data: contact } = await admin
          .from("contacts")
          .select("first_name,last_name,email")
          .eq("id", step.contact_id)
          .single();
        if (!contact?.email) continue;

        // Simple merge field replacement
        const merge = (tpl: string) => tpl
          .replace(/\{\{first_name\}\}/g, contact.first_name ?? "")
          .replace(/\{\{last_name\}\}/g, contact.last_name ?? "")
          .replace(/\{\{email\}\}/g, contact.email ?? "");

        const subject = merge(step.subject_template ?? "Follow-up");
        const body = merge(step.body_template ?? "");

        if (!body) continue;

        // Send via Resend
        const resp = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${resendKey}` },
          body: JSON.stringify({ from: fromEmail, to: [contact.email], subject, text: body }),
        });
        const respBody = await resp.json().catch(() => ({}));

        if (!resp.ok) {
          totalErrors++;
          results.push({ enrollment: step.enrollment_id, error: respBody?.message ?? "send_failed" });
          continue;
        }

        // Log email
        const { data: emailRow } = await admin.from("crm_emails").insert({
          organization_id: orgId,
          to_email: contact.email,
          from_email: fromEmail,
          subject,
          body,
          status: "sent",
          provider_message_id: respBody?.id ?? "",
          contact_id: step.contact_id,
          channel: "email",
          metadata: { sequence_step: step.step_number, campaign_id: step.campaign_id },
        }).select("id").single();

        // Log activity
        await admin.from("activities").insert({
          organization_id: orgId,
          entity_type: "contact",
          entity_id: step.contact_id,
          activity_type: "email",
          source: "email_integration",
          title: `Sequence email — Step ${step.step_number}: ${subject.slice(0, 60)}`,
          related_email_id: emailRow?.id,
          metadata: { auto_sequence: true, campaign_id: step.campaign_id },
        });

        // Get total steps in campaign
        const { count } = await admin
          .from("aicrm_sequence_steps")
          .select("id", { count: "exact", head: true })
          .eq("campaign_id", step.campaign_id);
        const totalSteps = count ?? 0;

        // Advance enrollment
        if (step.step_number >= totalSteps) {
          // Final step — complete the enrollment
          await admin.from("aicrm_sequence_enrollments").update({
            status: "completed",
            completed_at: new Date().toISOString(),
            last_contacted_at: new Date().toISOString(),
          }).eq("id", step.enrollment_id);
        } else {
          // Advance to next step
          await admin.from("aicrm_sequence_enrollments").update({
            current_step: step.step_number + 1,
            last_contacted_at: new Date().toISOString(),
          }).eq("id", step.enrollment_id);
        }

        // Update contact last communication
        await admin.from("contacts").update({
          last_communication_at: new Date().toISOString(),
          last_contact_method: "email",
        }).eq("id", step.contact_id);

        totalSent++;
        results.push({ enrollment: step.enrollment_id, step: step.step_number, sent: true });
      } catch (e) {
        totalErrors++;
        results.push({ enrollment: step.enrollment_id, error: String(e) });
      }
    }
  }

  return json({ ok: true, sent: totalSent, errors: totalErrors, results });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
