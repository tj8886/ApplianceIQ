import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL = Deno.env.get("EMAIL_FROM") ?? "ContractorHQ <onboarding@resend.dev>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) { console.log(`[CHQ NO KEY] ${to}: ${subject}`); return; }
  await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { "Content-Type": "application/json", "Authorization": `Bearer ${RESEND_API_KEY}` },
    body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html }),
  }).then(r => console.log(`[CHQ REMINDER] ${to}: ${subject} (${r.status})`)).catch(e => console.error(e));
}

function reminderHtml(b: any, hours: number) {
  const urgent = hours <= 3;
  return `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:#0f1d2e;padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:#f26522">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px">
<div style="background:${urgent?'#fef2f2':'#fef3c7'};border:1px solid ${urgent?'#fecaca':'#fde68a'};border-radius:8px;padding:16px;margin-bottom:16px">
<h2 style="color:${urgent?'#dc2626':'#f59e0b'};margin:0">&#9200; Your appointment is in ${hours} hours</h2></div>
<table style="width:100%;font-size:14px;border-collapse:collapse">
<tr><td style="padding:8px 0;color:#64748b">Booking #</td><td style="padding:8px 0;font-weight:600;text-align:right;font-family:monospace">${b.booking_number}</td></tr>
<tr><td style="padding:8px 0;color:#64748b">Date</td><td style="padding:8px 0;font-weight:600;text-align:right">${b.booking_date}</td></tr>
<tr><td style="padding:8px 0;color:#64748b">Time</td><td style="padding:8px 0;font-weight:600;text-align:right">${b.booking_time_start}</td></tr>
<tr><td style="padding:8px 0;color:#64748b">Address</td><td style="padding:8px 0;font-weight:600;text-align:right">${b.address||''}, ${b.city||''}</td></tr>
</table></div></div>`;
}

function insuranceHtml(c: any, days: number) {
  return `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:#0f1d2e;padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:#f26522">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px">
<div style="background:#fef2f2;border:1px solid #fecaca;border-radius:8px;padding:16px;margin-bottom:16px">
<h2 style="color:#dc2626;margin:0">&#9888;&#65039; Insurance Expiring in ${days} Days</h2></div>
<p style="font-size:14px;color:#64748b;line-height:1.6">Your policy <strong>${c.insurance_policy_number||''}</strong> with <strong>${c.insurance_provider||''}</strong> expires on <strong>${c.insurance_expiry_date}</strong>. Please renew and upload the updated certificate.</p>
<a href="https://contractorhq-app.netlify.app/contractors" style="display:block;text-align:center;background:#f26522;color:#fff;padding:14px;border-radius:8px;font-weight:700;text-decoration:none;margin-top:16px">Update Insurance</a></div></div>`;
}

Deno.serve(async (_req: Request) => {
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const now = new Date();
  const r = { r24: 0, r3: 0, ins: 0 };
  
  // 24h reminders
  const tmrw = new Date(now.getTime()+24*3600000).toISOString().split('T')[0];
  const { data: b24 } = await supabase.from("chq_bookings").select("*,customer:chq_customers(email,first_name)").eq("booking_date",tmrw).in("status",["confirmed","pending"]);
  if (b24) for (const b of b24) { const e=(b as any).customer?.email; if(e){await sendEmail(e,`Reminder: ${b.booking_number} is tomorrow`,reminderHtml(b,24));r.r24++} }
  
  // 3h reminders
  const today = now.toISOString().split('T')[0];
  const t3 = new Date(now.getTime()+3*3600000).toTimeString().substring(0,5);
  const tn = now.toTimeString().substring(0,5);
  const { data: b3 } = await supabase.from("chq_bookings").select("*,customer:chq_customers(email)").eq("booking_date",today).gte("booking_time_start",tn).lte("booking_time_start",t3).in("status",["confirmed"]);
  if (b3) for (const b of b3) { const e=(b as any).customer?.email; if(e){await sendEmail(e,`Appointment in 3 hours - ${b.booking_number}`,reminderHtml(b,3));r.r3++} }
  
  // Insurance expiry (30/14/7 days)
  for (const d of [30,14,7]) {
    const dt = new Date(now.getTime()+d*86400000).toISOString().split('T')[0];
    const { data: exp } = await supabase.from("chq_contractors").select("*").eq("insurance_expiry_date",dt).eq("status","approved");
    if (exp) for (const c of exp) { if(c.email){await sendEmail(c.email,`Insurance Expiring in ${d} Days`,insuranceHtml(c,d));r.ins++} }
  }
  
  console.log(`[CHQ REMINDERS] 24h:${r.r24} 3h:${r.r3} ins:${r.ins}`);
  return new Response(JSON.stringify({ ok:true,...r,ran:now.toISOString() }), { headers:{"Content-Type":"application/json"} });
});
