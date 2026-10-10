import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: "bad_json" }, 400);
  }

  const { invite_code, invited_email, org_name, role, inviter_email, site_origin } = payload || {};
  if (!invite_code || !invited_email || !org_name) {
    return json({ ok: false, error: "missing_fields" }, 400);
  }

  // Verify the caller is authenticated (JWT verified by platform since verify_jwt = true)
  // and that the invite actually exists and is pending — prevents using this as an open mailer.
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const vr = await fetch(
    `${SUPABASE_URL}/rest/v1/org_invites?invite_code=eq.${encodeURIComponent(invite_code)}&status=eq.pending&select=id,invited_email`,
    { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } },
  );
  const rows = await vr.json();
  if (!Array.isArray(rows) || rows.length === 0 || rows[0].invited_email?.toLowerCase() !== String(invited_email).toLowerCase()) {
    return json({ ok: false, error: "invite_not_found" }, 404);
  }

  const RESEND_KEY = Deno.env.get("RESEND_API_KEY");
  const origin = site_origin || "https://applianceiq-intelligence-group.netlify.app";
  const acceptUrl = `${origin}/admin.html#invite=${invite_code}`;

  if (!RESEND_KEY) {
    // No mail provider configured — tell the client so it can fall back to copy-link.
    return json({ ok: true, sent: false, reason: "no_mail_provider", accept_url: acceptUrl });
  }

  const FROM = Deno.env.get("INVITE_FROM_EMAIL") || "ApplianceIQ <onboarding@resend.dev>";
  const roleLabel = role === "owner" ? "Owner" : role === "admin" ? "Administrator" : "Team Member";

  const html = `
  <div style="font-family:Inter,system-ui,sans-serif;max-width:520px;margin:0 auto;padding:32px 24px">
    <div style="text-align:center;margin-bottom:28px">
      <div style="display:inline-block;width:48px;height:48px;line-height:48px;border-radius:12px;background:linear-gradient(135deg,#2563eb,#06b6d4);color:#fff;font-weight:800;font-size:18px;text-align:center">IQ</div>
    </div>
    <h1 style="font-size:20px;color:#0f1f3d;text-align:center;margin:0 0 8px">You're invited to join ${escapeHtml(org_name)}</h1>
    <p style="font-size:14px;color:#64748b;text-align:center;margin:0 0 24px">
      ${inviter_email ? escapeHtml(inviter_email) + " has invited you" : "You've been invited"} to join
      <b>${escapeHtml(org_name)}</b> on the ApplianceIQ platform as ${roleLabel === "Administrator" || roleLabel === "Owner" ? "an" : "a"} <b>${roleLabel}</b>.
    </p>
    <div style="text-align:center;margin:28px 0">
      <a href="${acceptUrl}" style="display:inline-block;background:#1a9e56;color:#fff;text-decoration:none;font-weight:600;font-size:14px;padding:13px 32px;border-radius:10px">Accept Invitation</a>
    </div>
    <p style="font-size:12px;color:#94a3b8;text-align:center">This invitation expires in 7 days. If the button doesn't work, paste this link into your browser:<br/>
      <a href="${acceptUrl}" style="color:#2563eb;word-break:break-all">${acceptUrl}</a></p>
    <hr style="border:none;border-top:1px solid #e2e8f0;margin:28px 0"/>
    <p style="font-size:11px;color:#cbd5e1;text-align:center">ApplianceIQ Intelligence Group \u2022 The Appliance Industry Intelligence Platform</p>
  </div>`;

  const mr = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${RESEND_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: FROM,
      to: [invited_email],
      subject: `You're invited to join ${org_name} on ApplianceIQ`,
      html,
    }),
  });

  if (!mr.ok) {
    const errText = await mr.text();
    return json({ ok: true, sent: false, reason: "mail_error", detail: errText.slice(0, 300), accept_url: acceptUrl });
  }

  return json({ ok: true, sent: true, accept_url: acceptUrl });
});

function escapeHtml(s: string) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c] as string,
  );
}
