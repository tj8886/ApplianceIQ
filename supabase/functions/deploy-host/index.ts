// Temporary deploy-host v3: serves the CRMAIIQ v3 app (activity capture layer) for Netlify import. Retired after deploy.
const B64_URL = "__SELF_CONTAINED__";
import { createClient } from "jsr:@supabase/supabase-js@2";
Deno.serve(async () => {
  const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  const { data, error } = await admin.from("app_bundles").select("content_b64").eq("key", "crmaiiq_v3").single();
  if (error || !data) return new Response("bundle_not_found: " + (error?.message ?? ""), { status: 404 });
  const bytes = Uint8Array.from(atob(data.content_b64), (c) => c.charCodeAt(0));
  return new Response(bytes, { headers: { "Content-Type": "text/html; charset=utf-8" } });
});
