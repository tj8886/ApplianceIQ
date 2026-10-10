import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

// Reuse existing Resend setup from email-dispatcher
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL = Deno.env.get("EMAIL_FROM") ?? "ContractorHQ <onboarding@resend.dev>";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

async function sendEmail(to: string, subject: string, html: string) {
  if (!RESEND_API_KEY) {
    console.log(`[CHQ EMAIL - NO KEY] To: ${to} | Subject: ${subject}`);
    return { success: false, error: "no_api_key" };
  }
  
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${RESEND_API_KEY}` },
      body: JSON.stringify({ from: FROM_EMAIL, to: [to], subject, html }),
    });
    const data = await res.json().catch(() => ({}));
    console.log(`[CHQ EMAIL] To: ${to} | Subject: ${subject} | Status: ${res.status}`);
    return { success: res.ok, data };
  } catch (err) {
    console.error(`[CHQ EMAIL ERROR] To: ${to} | ${err}`);
    return { success: false, error: String(err) };
  }
}

function bookingEmail(booking: any, isContractor: boolean) {
  const c = "#f26522", n = "#0f1d2e";
  const greeting = isContractor ? "You have a new booking!" : "Your booking is confirmed!";
  return `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:${n};padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:${c}">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none">
<h2 style="color:${n};margin-bottom:16px">${greeting}</h2>
<div style="background:#f8fafc;border-radius:8px;padding:16px;margin-bottom:16px">
<table style="width:100%;font-size:14px;border-collapse:collapse">
<tr><td style="padding:6px 0;color:#64748b">Booking #</td><td style="padding:6px 0;font-weight:600;text-align:right;font-family:monospace">${booking.booking_number}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Service</td><td style="padding:6px 0;font-weight:600;text-align:right">${booking.service_name || 'Service'}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Date</td><td style="padding:6px 0;font-weight:600;text-align:right">${booking.booking_date}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Time</td><td style="padding:6px 0;font-weight:600;text-align:right">${booking.booking_time_start}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Address</td><td style="padding:6px 0;font-weight:600;text-align:right">${booking.address || ''}, ${booking.city || ''}</td></tr>
${booking.product_model_number ? `<tr><td style="padding:6px 0;color:#64748b">Model #</td><td style="padding:6px 0;font-weight:600;text-align:right">${booking.product_model_number}</td></tr>` : ''}
<tr style="border-top:2px solid #e2e5ea"><td style="padding:10px 0;font-weight:700;font-size:16px">Total</td><td style="padding:10px 0;font-weight:800;font-size:18px;text-align:right;color:${n}">$${Number(booking.total_price).toFixed(2)} CAD</td></tr>
</table></div>
${booking.notes ? `<div style="background:#fefce8;border:1px solid #fef08a;border-radius:8px;padding:12px;margin-bottom:16px"><strong>Notes:</strong> ${booking.notes}</div>` : ''}
${isContractor ? `<div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:12px"><strong style="color:#16a34a">Action Required:</strong> Contact the customer to confirm details and schedule.</div>` : `<div style="background:#eff6ff;border:1px solid #bfdbfe;border-radius:8px;padding:12px"><strong style="color:#2563eb">What's next:</strong> Your contractor will contact you to confirm. You'll receive reminders 24hrs and 3hrs before.</div>`}
</div>
<div style="padding:16px 24px;font-size:12px;color:#94a3b8;text-align:center;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px;background:#fafbfc">ContractorHQ &mdash; Payment held securely until you approve completed work.</div></div>`;
}

function openJobEmail(job: any) {
  return `<div style="font-family:system-ui,sans-serif;max-width:600px;margin:0 auto">
<div style="background:#0f1d2e;padding:20px 24px;border-radius:12px 12px 0 0"><span style="font-size:22px;font-weight:800;color:#fff">Contractor<span style="color:#f26522">HQ</span></span></div>
<div style="background:#fff;padding:24px;border:1px solid #e2e5ea;border-top:none;border-radius:0 0 12px 12px">
<div style="background:linear-gradient(135deg,#4c1d95,#7c3aed);color:#fff;padding:16px;border-radius:8px;margin-bottom:16px">
<h2 style="margin:0 0 4px">&#9889; New Job Available!</h2><p style="margin:0;opacity:0.8">First to accept wins this job</p></div>
<table style="width:100%;font-size:14px;border-collapse:collapse">
<tr><td style="padding:6px 0;color:#64748b">Service</td><td style="padding:6px 0;font-weight:600;text-align:right">${job.service_name || 'Service'}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Location</td><td style="padding:6px 0;font-weight:600;text-align:right">${job.city || ''}, ${job.province_state || ''}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Date</td><td style="padding:6px 0;font-weight:600;text-align:right">${job.preferred_date || 'Flexible'}</td></tr>
<tr><td style="padding:6px 0;color:#64748b">Time</td><td style="padding:6px 0;font-weight:600;text-align:right">${job.preferred_time_slot || 'Any'}</td></tr></table>
<a href="https://contractorhq-app.netlify.app/contractors" style="display:block;text-align:center;background:#7c3aed;color:#fff;padding:14px;border-radius:8px;font-weight:700;font-size:16px;text-decoration:none;margin-top:16px">Accept This Job</a>
<p style="font-size:12px;color:#94a3b8;text-align:center;margin-top:12px">Expires in 24 hours. First to accept gets it.</p></div></div>`;
}

Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    const type = payload.type;
    const record = payload.record;
    
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    
    // --- BOOKING CREATED ---
    if (type === "INSERT" && record?.booking_number) {
      const { data: customer } = await supabase.from("chq_customers").select("email,first_name,last_name").eq("id", record.customer_id).single();
      const { data: contractor } = await supabase.from("chq_contractors").select("email,company_name").eq("id", record.contractor_id).single();
      const { data: service } = await supabase.from("chq_services").select("name").eq("id", record.service_id).single();
      
      const bk = { ...record, service_name: service?.name || "Service" };
      const results: string[] = [];
      
      if (customer?.email) {
        await sendEmail(customer.email, `Booking Confirmed: ${bk.service_name} - ${record.booking_number}`, bookingEmail(bk, false));
        results.push(customer.email);
      }
      if (contractor?.email) {
        await sendEmail(contractor.email, `New Booking: ${bk.service_name} - ${record.booking_number}`, bookingEmail(bk, true));
        results.push(contractor.email);
      }
      
      return new Response(JSON.stringify({ ok: true, type: "booking", sent_to: results }), { headers: { "Content-Type": "application/json" } });
    }
    
    // --- OPEN JOB CREATED ---
    if (type === "open_job_created" && record) {
      const { data: service } = await supabase.from("chq_services").select("name").eq("id", record.service_id).single();
      const { data: eligible } = await supabase.from("chq_contractor_services").select("contractor:chq_contractors(id,email,company_name)").eq("service_id", record.service_id).eq("active", true);
      
      const job = { ...record, service_name: service?.name || "Service" };
      const sent: string[] = [];
      
      if (eligible) {
        for (const cs of eligible) {
          const c = (cs as any).contractor;
          if (c?.email) {
            await sendEmail(c.email, `New Job: ${job.service_name} in ${record.city || 'your area'}`, openJobEmail(job));
            sent.push(c.email);
            await supabase.from("chq_open_job_notifications").insert({ open_job_id: record.id, contractor_id: c.id }).catch(() => {});
          }
        }
      }
      
      return new Response(JSON.stringify({ ok: true, type: "open_job", notified: sent.length }), { headers: { "Content-Type": "application/json" } });
    }
    
    return new Response(JSON.stringify({ skipped: true }), { headers: { "Content-Type": "application/json" } });
  } catch (err) {
    console.error("chq-notify-booking error:", err);
    return new Response(JSON.stringify({ error: String(err) }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
