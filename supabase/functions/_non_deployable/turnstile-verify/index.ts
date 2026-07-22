// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify disabled (public CAPTCHA endpoint)
// Env: TURNSTILE_SECRET_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Schema deps: check_turnstile_rate_limit RPC, log_turnstile_verification RPC
// Status: DEPLOYABLE — references RPCs that may or may not exist in production
//         (function is active in production regardless)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { buildTurnstileFailure, normalizeTurnstileRequest } from "../_shared/turnstile.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const TURNSTILE_SECRET_KEY = Deno.env.get("TURNSTILE_SECRET_KEY");
const RATE_LIMIT_WINDOW_MIN = parseInt(Deno.env.get("TURNSTILE_RATE_LIMIT_WINDOW_MINUTES") ?? "10", 10);
const RATE_LIMIT_MAX_FAILURES = parseInt(Deno.env.get("TURNSTILE_RATE_LIMIT_MAX_FAILURES") ?? "30", 10);
const SITEVERIFY_URL = "https://challenges.cloudflare.com/turnstile/v0/siteverify";
const SITEVERIFY_TIMEOUT_MS = 8000;
const ALLOWED_ORIGIN_REGEX = /^https?:\/\/(localhost(:\d+)?|([\w-]+\.)?applianceiq\.com|[\w-]+\.netlify\.app)$/i;

function corsHeaders(origin: string | null): Record<string, string> {
  const allow = origin && ALLOWED_ORIGIN_REGEX.test(origin) ? origin : "*";
  return { "Access-Control-Allow-Origin": allow, "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "content-type, authorization", "Access-Control-Max-Age": "86400", Vary: "Origin" };
}

function json(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...corsHeaders(origin) } });
}

function extractIp(req: Request): string | null {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0].trim();
  const cf = req.headers.get("cf-connecting-ip");
  if (cf) return cf.trim();
  return req.headers.get("x-real-ip")?.trim() ?? null;
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

async function verifyWithCloudflare(token: string, ip: string | null, idempotencyKey?: string) {
  if (!TURNSTILE_SECRET_KEY) throw new Error("TURNSTILE_SECRET_KEY not configured");
  const body: Record<string, string> = { secret: TURNSTILE_SECRET_KEY, response: token };
  if (ip) body.remoteip = ip;
  if (idempotencyKey) body.idempotency_key = idempotencyKey;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), SITEVERIFY_TIMEOUT_MS);
  try {
    const res = await fetch(SITEVERIFY_URL, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), signal: controller.signal });
    return (await res.json()) as { success: boolean; challenge_ts?: string; hostname?: string; "error-codes"?: string[]; action?: string; cdata?: string };
  } finally { clearTimeout(timer); }
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin");
  const startedAt = Date.now();
  const requestId = crypto.randomUUID();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (request.method !== "POST") return json(405, { ok: false, code: "method_not_allowed" }, origin);
  let payload: Record<string, unknown>;
  try { payload = await request.json(); } catch { return json(400, { ok: false, code: "invalid_json", message: "Body must be JSON" }, origin); }
  const { token, action, idempotencyKey } = normalizeTurnstileRequest(payload);
  const userAgent = request.headers.get("user-agent");
  const ip = extractIp(request);
  if (!token) return json(400, buildTurnstileFailure("missing_token", "token is required"), origin);
  if (ip) {
    const { data: rateData } = await supabase.rpc("check_turnstile_rate_limit", { p_ip: ip, p_window_minutes: RATE_LIMIT_WINDOW_MIN, p_max_failures: RATE_LIMIT_MAX_FAILURES });
    if (rateData?.throttled) {
      await supabase.rpc("log_turnstile_verification", { p_payload: { action, success: false, error_codes: ["rate_limited"], ip_address: ip, user_agent: userAgent, request_id: requestId, duration_ms: Date.now() - startedAt, metadata: { rate_limit_state: rateData } } });
      return json(429, { ok: false, code: "rate_limited", hint: `Too many failed attempts. Try again in ${RATE_LIMIT_WINDOW_MIN} minutes.`, retry_after_minutes: RATE_LIMIT_WINDOW_MIN }, origin);
    }
  }
  let cfResult;
  try { cfResult = await verifyWithCloudflare(token, ip, idempotencyKey ?? undefined); } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    await supabase.rpc("log_turnstile_verification", { p_payload: { action, success: false, error_codes: ["siteverify_unreachable"], ip_address: ip, user_agent: userAgent, request_id: requestId, duration_ms: Date.now() - startedAt, metadata: { error_message: message } } });
    return json(503, { ok: false, code: "verification_unavailable", message: "Could not reach the verification service. Please try again." }, origin);
  }
  const elapsed = Date.now() - startedAt;
  await supabase.rpc("log_turnstile_verification", { p_payload: { action, hostname: cfResult.hostname ?? null, success: cfResult.success === true, error_codes: cfResult["error-codes"] ?? [], ip_address: ip, user_agent: userAgent, request_id: requestId, challenge_ts: cfResult.challenge_ts ?? null, cdata: cfResult.cdata ?? null, duration_ms: elapsed, metadata: { cf_action: cfResult.action ?? null } } });
  if (!cfResult.success) return json(403, { ok: false, code: "verification_failed", error_codes: cfResult["error-codes"] ?? [], hint: "Turnstile verification failed." }, origin);
  if (action && cfResult.action && action !== cfResult.action) return json(403, { ok: false, code: "action_mismatch", message: "The verification action did not match the submitted action." }, origin);
  return json(200, { ok: true, verification_id: requestId, hostname: cfResult.hostname ?? null, action: cfResult.action ?? action, latency_ms: elapsed }, origin);
});
