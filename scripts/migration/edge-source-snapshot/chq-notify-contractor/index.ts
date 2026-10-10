import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL = Deno.env.get("EMAIL_FROM") ?? "ContractorHQ <onboarding@resend.dev>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) { console.log(`[CHQ NO KEY] ${to}: ${subject}`); return { success: false }; }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${RESEND_API_KEY}` },
    body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html }),
  });
  console.log(`[CHQ EMAIL] ${to}: ${subject} (${res.status})`);
  return { success: res.ok };
}

Deno.serve(async (req: Request) => {
  try {
    const { type, record, old_record } = await req.json();
    const n = "#0f1d2e", c = "#f26522";
    
    // --- STATUS CHANGE (approved/rejected) ---
    if (type === "UPDATE" && record?.status !== old_record?.status && record?.email) {
      const approved = record.status === "approved";
      const html = `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:${n};padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:${c}">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px">
<div style="background:${approved?'#f0fdf4':'#fef2f2'};border:1px solid ${approved?'#bbf7d0':'#fecaca'};border-radius:8px;padding:20px;text-align:center;margin-bottom:16px">
<div style="font-size:48px;margin-bottom:8px">${approved?'&#9989;':'&#10060;'}</div>
<h2 style="color:${approved?'#16a34a':'#dc2626'};margin:0">Application ${approved?'Approved!':'Not Approved'}</h2>
<p style="color:#64748b;margin:4px 0 0">${record.company_name}</p></div>
${approved?`<h3 style="color:${n}">Welcome to ContractorHQ!</h3><p style="font-size:14px;color:#64748b;line-height:1.6">Your account is approved. Log in, set up Stripe Connect for payments, and start receiving bookings!</p><a href="https://contractorhq-app.netlify.app/contractors" style="display:block;text-align:center;background:${c};color:#fff;padding:14px;border-radius:8px;font-weight:700;font-size:16px;text-decoration:none;margin-top:16px">Go to Dashboard</a>`:`<p style="font-size:14px;color:#64748b">Your application was not approved. This may be due to incomplete documentation. Contact us to review.</p>`}
</div></div>`;
      
      await sendEmail(record.email, approved ? `Welcome! Your ContractorHQ account is approved` : `ContractorHQ Application Update`, html);
      return new Response(JSON.stringify({ ok: true, status: record.status }), { headers: { "Content-Type": "application/json" } });
    }
    
    // --- NEW REGISTRATION ---
    if (type === "INSERT" && record?.status === "pending" && record?.email) {
      const html = `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:${n};padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:${c}">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px">
<h2 style="color:${n};margin-bottom:12px">Application Received!</h2>
<p style="font-size:14px;color:#64748b;line-height:1.6">Thank you for registering <strong>${record.company_name}</strong>. We're reviewing your application and you'll hear back within 24-48 hours.</p>
<div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;padding:12px;margin-top:16px">
<strong style="color:#2563eb">What we're reviewing:</strong>
<ul style="font-size:14px;color:#64748b;margin:8px 0 0;padding-left:20px"><li>Business license</li><li>Insurance documentation</li><li>Service area coverage</li></ul></div></div></div>`;
      
      await sendEmail(record.email, `Application Received - ${record.company_name}`, html);
      return new Response(JSON.stringify({ ok: true, type: "registration" }), { headers: { "Content-Type": "application/json" } });
    }
    
    return new Response(JSON.stringify({ skipped: true }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("chq-notify-contractor error:", err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
