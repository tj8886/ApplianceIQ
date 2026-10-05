// brief-email-sender — Sends executive briefs (morning/eod/weekly) via Resend.
// Called by the Command Centre UI or a scheduled cron.
// Auth: user JWT; must be org member.
// Secrets: RESEND_API_KEY, EMAIL_FROM (optional)

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "auth_required" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const orgId = String(body.organization_id ?? "");
  const briefId = body.brief_id ? String(body.brief_id) : null;
  const recipientEmails = Array.isArray(body.recipients) ? body.recipients.map(String) : [];

  if (!orgId) return json({ error: "organization_id_required" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resendKey = Deno.env.get("RESEND_API_KEY") ?? "";
  const fromEmail = Deno.env.get("EMAIL_FROM") ?? "ApplianceIQ <onboarding@resend.dev>";

  if (!resendKey) return json({ error: "resend_api_key_not_configured" }, 503);

  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: auth } } });
  const admin = createClient(url, serviceKey);

  // Auth check
  const { data: userData } = await userClient.auth.getUser();
  const userId = userData?.user?.id;
  if (!userId) return json({ error: "auth_required" }, 401);
  const { data: membership } = await userClient
    .from("organization_members").select("user_id")
    .eq("organization_id", orgId).eq("user_id", userId).maybeSingle();
  if (!membership) return json({ error: "not_authorized" }, 403);

  // Get brief
  let brief: Record<string, unknown> | null = null;
  if (briefId) {
    const { data } = await admin.from("ai_manager_briefs")
      .select("*").eq("id", briefId).eq("organization_id", orgId).single();
    brief = data;
  } else {
    // Get latest brief for org
    const { data } = await admin.from("ai_manager_briefs")
      .select("*").eq("organization_id", orgId)
      .order("generated_at", { ascending: false }).limit(1).single();
    brief = data;
  }
  if (!brief) return json({ error: "no_brief_found" }, 404);

  // Resolve recipients: if none provided, get org admins/managers
  let recipients = recipientEmails;
  if (recipients.length === 0) {
    const { data: members } = await admin
      .from("organization_members").select("user_id")
      .eq("organization_id", orgId).in("role", ["admin", "owner", "manager"])
      .eq("status", "active");
    if (members && members.length > 0) {
      const userIds = members.map((m: { user_id: string }) => m.user_id);
      const { data: users } = await admin.auth.admin.listUsers();
      if (users?.users) {
        recipients = users.users
          .filter(u => userIds.includes(u.id) && u.email)
          .map(u => u.email!);
      }
    }
  }
  if (recipients.length === 0) return json({ error: "no_recipients", detail: "No admin/manager emails found" }, 400);

  // Build email
  const briefType = String(brief.brief_type ?? "daily");
  const briefDate = String(brief.brief_date ?? new Date().toISOString().slice(0, 10));
  const headline = String(brief.headline ?? "Executive Brief");
  const summary = String(brief.executive_summary ?? "");
  const priorities = brief.priorities as unknown[] ?? [];
  const risks = brief.risks as unknown[] ?? [];
  const wins = brief.wins as unknown[] ?? [];
  const workload = brief.workload as Record<string, unknown> ?? {};
  const financial = Number(brief.financial_exposure_cad ?? 0);

  const subject = `[ApplianceIQ] ${briefType === 'morning' ? 'Morning Brief' : briefType === 'eod' ? 'End of Day' : 'Weekly Review'} — ${briefDate}`;

  const priorityList = priorities.map((p: any) =>
    `• ${p.title} (${p.severity}, C$${Number(p.financial_impact_cad ?? 0).toLocaleString()})`
  ).join('\n') || '(none)';

  const riskList = risks.map((r: any) =>
    `• ${r.title} — ${r.status}${r.due_at ? ', due ' + String(r.due_at).slice(0, 10) : ''}`
  ).join('\n') || '(none)';

  const winList = wins.map((w: any) =>
    `• ${w.title}${w.completed_at ? ' (' + String(w.completed_at).slice(0, 10) + ')' : ''}`
  ).join('\n') || '(none)';

  const text = [
    `APPLIANCEIQ ${briefType.toUpperCase()} BRIEF — ${briefDate}`,
    '',
    `HEADLINE: ${headline}`,
    '',
    summary,
    '',
    `WORKLOAD: ${Number(workload.open ?? 0)} active, ${Number(workload.blocked ?? 0)} blocked, ${Number(workload.overdue ?? 0)} overdue, ${Number(workload.completed_7d ?? 0)} completed this week`,
    `FINANCIAL EXPOSURE: C$${financial.toLocaleString()}`,
    '',
    'TOP PRIORITIES:',
    priorityList,
    '',
    'RISKS & BLOCKERS:',
    riskList,
    '',
    'RECENT WINS:',
    winList,
    '',
    '---',
    'View full brief: https://applianceiq-command-center.netlify.app/briefs.html',
    'ApplianceIQ Intelligence Group',
  ].join('\n');

  // Send
  let sent = 0;
  let failed = 0;
  const errors: string[] = [];

  for (const to of recipients) {
    try {
      const resp = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${resendKey}` },
        body: JSON.stringify({ from: fromEmail, to: [to], subject, text }),
      });
      if (resp.ok) { sent++; } else {
        const err = await resp.json().catch(() => ({}));
        failed++;
        errors.push(`${to}: ${err?.message ?? resp.status}`);
      }
    } catch (e) {
      failed++;
      errors.push(`${to}: ${(e as Error).message}`);
    }
  }

  // Mark delivered
  const channels = ['in_app'];
  if (sent > 0) channels.push('email');
  await admin.from("ai_manager_briefs").update({
    delivery_status: sent > 0 ? 'delivered' : 'failed',
    delivery_channels: channels,
    delivered_at: sent > 0 ? new Date().toISOString() : null,
  }).eq("id", brief.id);

  return json({ ok: true, sent, failed, errors: errors.length > 0 ? errors : undefined });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
