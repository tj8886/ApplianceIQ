// contact-form v2 — uses onboarding@resend.dev until applianceiq.com domain is verified in Resend
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const { name, email, company, role, message, source } = await req.json();
    if (!name || !email) return json({ error: "Name and email are required" }, 400);
    if (!email.includes("@")) return json({ error: "Invalid email" }, 400);

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data, error } = await sb.from("contact_submissions").insert({
      full_name: name, email, company: company || null, role: role || null,
      message: message || null, source: source || "intelligence-group",
    }).select().single();
    if (error) return json({ error: "Failed to save: " + error.message }, 500);

    const resendKey = Deno.env.get("RESEND_API_KEY");
    if (resendKey) {
      try {
        // FROM_EMAIL: set secret to notifications@applianceiq.com AFTER verifying the domain in Resend.
        // Until then, onboarding@resend.dev works (can only deliver to the account owner's email).
        const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "ApplianceIQ <onboarding@resend.dev>";
        await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": "Bearer " + resendKey },
          body: JSON.stringify({
            from: fromEmail,
            to: ["tjrobar5@gmail.com"],
            subject: `🔔 New Demo Request: ${name} from ${company || "Unknown Company"}`,
            html: `<div style="font-family:Inter,sans-serif;max-width:600px;margin:0 auto">
              <div style="background:#0f1f3d;color:white;padding:20px 24px;border-radius:12px 12px 0 0"><h2 style="margin:0;font-size:18px">New Demo Request</h2></div>
              <div style="padding:24px;background:#fff;border:1px solid #e2e8f0;border-top:none;border-radius:0 0 12px 12px">
                <p><strong>Name:</strong> ${name}</p>
                <p><strong>Email:</strong> <a href="mailto:${email}">${email}</a></p>
                <p><strong>Company:</strong> ${company || "Not provided"}</p>
                <p><strong>Role:</strong> ${role || "Not specified"}</p>
                <p><strong>Message:</strong></p>
                <div style="background:#f8fafc;padding:16px;border-radius:8px;margin-top:8px">${message || "No message provided"}</div>
                <hr style="margin:24px 0;border:none;border-top:1px solid #e2e8f0">
                <p style="font-size:12px;color:#64748b">Submitted ${new Date().toLocaleString("en-US", { timeZone: "America/Toronto" })} — Intelligence Group website</p>
              </div></div>`,
          }),
        });
      } catch (e) { console.error("Email failed:", e); }
    }

    return json({ success: true, id: data.id });
  } catch (err: any) {
    return json({ error: err.message || "Unknown error" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
