// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify enabled
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY
// NON-DEPLOYABLE: depends on missing schema objects:
//   - signed_url_nonces (table)
//   - file_access_events (table)
//   - consume_signed_url_nonce (RPC)
// These tables/RPCs do not exist in the current production migration set.
// See docs/reconciliation/PROPOSED_FILE_SECURITY_SCHEMA.sql for the required schema.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { normalizeSignedUrlPurpose } from "../_shared/file-governance.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" } });
}

async function resolveUser(request: Request) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, { auth: { persistSession: false, autoRefreshToken: false }, global: { headers: { Authorization: authHeader } } });
  const { data: { user }, error } = await userClient.auth.getUser();
  return (error || !user) ? null : user;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const user = await resolveUser(request);
  if (!user) return json({ error: "missing_or_invalid_auth" }, 401);
  let payload: { nonce?: string; expires_in_seconds?: number };
  try { payload = await request.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const nonce = typeof payload.nonce === "string" ? payload.nonce.trim() : "";
  if (!nonce) return json({ error: "missing_nonce" }, 400);
  const { data: nonceData, error: consumeError } = await serviceClient.rpc("consume_signed_url_nonce", { p_nonce: nonce, p_user_id: user.id });
  if (consumeError || !nonceData) return json({ error: "nonce_consume_failed", detail: consumeError?.message ?? "Nonce could not be consumed." }, 403);
  const nonceRecord = nonceData as { bucket: string; path: string; filename: string; purpose: string; expires_at: string; organization_id: string; file_asset_id: string };
  const expiresIn = Math.min(Math.max(payload.expires_in_seconds ?? 300, 30), 3600);
  const signedUrlResult = await serviceClient.storage.from(nonceRecord.bucket).createSignedUrl(nonceRecord.path, expiresIn, { download: normalizeSignedUrlPurpose(nonceRecord.purpose) === "download" ? nonceRecord.filename : false });
  if (signedUrlResult.error || !signedUrlResult.data) return json({ error: "signed_url_failed", detail: signedUrlResult.error?.message ?? "Storage signed URL could not be created." }, 500);
  await serviceClient.from("file_access_events").insert({ organization_id: nonceRecord.organization_id, file_asset_id: nonceRecord.file_asset_id, actor_user_id: user.id, access_type: "signed_url_minted", success: true, context: { purpose: normalizeSignedUrlPurpose(nonceRecord.purpose), expires_in_seconds: expiresIn } });
  return json({ signed_url: signedUrlResult.data.signedUrl, filename: nonceRecord.filename, purpose: nonceRecord.purpose, expires_in_seconds: expiresIn, organization_id: nonceRecord.organization_id });
});
