import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

// admin-provision: lets an existing platform admin create a user account
// and grant super admin in one step. Only callable by platform admins.
// action: create_admin { email, full_name } -> { ok, temp_password }

function tempPassword(): string {
  const words = ["Maple", "Harbor", "Summit", "Cedar", "Aurora", "Falcon", "Granite", "Meadow"];
  const w = words[Math.floor(Math.random() * words.length)];
  const n = Math.floor(1000 + Math.random() * 9000);
  const s = "!@#$%"[Math.floor(Math.random() * 5)];
  return `${w}${n}${s}IQ`;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad_json" }, 400); }
  if (body?.action !== "create_admin") return json({ ok: false, error: "unknown_action" }, 400);

  const email = String(body.email || "").trim().toLowerCase();
  const fullName = String(body.full_name || "").trim();
  if (!email || !email.includes("@")) return json({ ok: false, error: "invalid_email" }, 400);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const h = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };

  // Caller must be a platform admin
  const auth = req.headers.get("authorization") || "";
  let uid: string | null = null;
  try { uid = JSON.parse(atob(auth.replace(/^Bearer\s+/i, "").split(".")[1])).sub || null; } catch {}
  if (!uid) return json({ ok: false, error: "not_authenticated" }, 401);
  const ar = await fetch(`${SUPABASE_URL}/rest/v1/platform_admins?user_id=eq.${uid}&select=id`, { headers: h });
  if (!(((await ar.json())?.length || 0) > 0)) return json({ ok: false, error: "forbidden" }, 403);

  // Does the account already exist? (GoTrue admin lookup by email)
  let userId: string | null = null;
  let created = false;
  let password: string | null = null;
  const lookup = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?page=1&per_page=1&filter=${encodeURIComponent(email)}`, { headers: h });
  if (lookup.ok) {
    const lr = await lookup.json();
    const match = (lr?.users || []).find((u: any) => (u.email || "").toLowerCase() === email);
    if (match) userId = match.id;
  }

  if (!userId) {
    password = tempPassword();
    const cr = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
      method: "POST", headers: h,
      body: JSON.stringify({ email, password, email_confirm: true, user_metadata: { full_name: fullName } }),
    });
    const cu = await cr.json();
    if (!cr.ok) return json({ ok: false, error: cu?.msg || cu?.error_description || "user_create_failed" });
    userId = cu.id;
    created = true;
  }

  // Ensure profile
  await fetch(`${SUPABASE_URL}/rest/v1/profiles`, {
    method: "POST",
    headers: { ...h, Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({ id: userId, user_id: userId, email, full_name: fullName || email.split("@")[0] }),
  });

  // Grant platform admin (idempotent)
  const gr = await fetch(`${SUPABASE_URL}/rest/v1/platform_admins`, {
    method: "POST",
    headers: { ...h, Prefer: "resolution=ignore-duplicates" },
    body: JSON.stringify({ user_id: userId, email, full_name: fullName || null, role: "super_admin", created_by: uid }),
  });
  if (!gr.ok) {
    const ge = await gr.text();
    if (!/duplicate/i.test(ge)) return json({ ok: false, error: "grant_failed: " + ge.slice(0, 160) });
  }

  return json({ ok: true, created_account: created, user_id: userId, temp_password: password });
});
