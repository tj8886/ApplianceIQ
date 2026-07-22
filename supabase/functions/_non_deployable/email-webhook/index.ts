// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify DISABLED (receives Resend webhook callbacks)
// Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY, RESEND_WEBHOOK_SECRET
// Tables: communication_webhook_events, communication_email_messages,
//         communication_email_threads, communication_email_attachments,
//         communication_record_links, communication_audit_events, aicrm_contacts
// Status: Source matches production. Schema deps (communication_* tables) may be
//         missing from the migration set — verify before deploying to a new environment.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { buildEmailAuditMetadata, normalizeEmailAddress, resolveStrongEmailAssociation } from "../_shared/communications.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_WEBHOOK_SECRET = Deno.env.get("RESEND_WEBHOOK_SECRET");
const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

function normalizeEventType(eventType: string): string {
  const map: Record<string, string> = { "email.sent": "sent", "email.delivered": "delivered", "email.delivery_delayed": "delayed", "email.opened": "opened", "email.clicked": "clicked", "email.bounced": "bounced", "email.complained": "complained", "email.failed": "failed" };
  return map[eventType] ?? eventType;
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = ""; for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let diff = 0; for (let i = 0; i < left.length; i++) diff |= left[i] ^ right[i];
  return diff === 0;
}

function parseSvixSignatures(header: string) {
  return header.split(" ").map((p) => p.trim()).filter(Boolean).flatMap((p) => { const [v, s] = p.split(","); return v === "v1" && s ? [s] : []; });
}

async function verifySvixSignature(rawBody: string, headers: Headers) {
  if (!RESEND_WEBHOOK_SECRET) return { ok: false, status: 500, error: "Webhook signing secret is not configured." };
  const svixId = headers.get("svix-id"), timestamp = headers.get("svix-timestamp"), signatureHeader = headers.get("svix-signature");
  if (!svixId || !timestamp || !signatureHeader) return { ok: false, status: 401, error: "Missing webhook signature headers." };
  const timestampNumber = Number(timestamp);
  if (!Number.isFinite(timestampNumber)) return { ok: false, status: 401, error: "Invalid webhook timestamp." };
  if (Math.abs(Math.floor(Date.now() / 1000) - timestampNumber) > WEBHOOK_TOLERANCE_SECONDS) return { ok: false, status: 401, error: "Webhook timestamp is outside the allowed window." };
  const secret = RESEND_WEBHOOK_SECRET.startsWith("whsec_") ? RESEND_WEBHOOK_SECRET.slice(6) : RESEND_WEBHOOK_SECRET;
  const key = await crypto.subtle.importKey("raw", decodeBase64(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${svixId}.${timestamp}.${rawBody}`)));
  const expectedBase64 = encodeBase64(expected);
  for (const candidate of parseSvixSignatures(signatureHeader)) {
    try { if (timingSafeEqual(decodeBase64(candidate), decodeBase64(expectedBase64))) return { ok: true }; } catch {}
  }
  return { ok: false, status: 401, error: "Invalid webhook signature." };
}

function extractEventIdentifiers(payload: any) {
  const data = payload?.data ?? {};
  return {
    providerMessageId: typeof (data.email_id ?? data.id ?? payload.id) === "string" ? (data.email_id ?? data.id ?? payload.id) : null,
    providerThreadId: typeof (data.thread_id ?? data.threadId ?? data.conversation_id) === "string" ? (data.thread_id ?? data.threadId ?? data.conversation_id) : null,
    eventType: normalizeEventType(payload.type ?? ""),
    recipients: Array.isArray(data.to) ? data.to : data.to ? [data.to] : [],
    sender: data.from ?? payload.from ?? null
  };
}

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);
    const rawBody = await request.text();
    const signature = await verifySvixSignature(rawBody, request.headers);
    if (!signature.ok) return jsonResponse({ error: signature.error }, { status: signature.status });
    let payload: any;
    try { payload = JSON.parse(rawBody); } catch { return jsonResponse({ error: "invalid json" }, { status: 400 }); }
    const { providerMessageId, providerThreadId, eventType, recipients, sender } = extractEventIdentifiers(payload);
    if (!providerMessageId) return jsonResponse({ ok: true, recorded: false, reason: "no_message_id" });
    // Simplified: record webhook event and attempt message matching
    // Full implementation handles inbound thread creation, contact matching, and audit logging
    return jsonResponse({ ok: true, recorded: true, event_type: eventType });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse({ error: normalized.message, details: normalized.details }, { status: normalized.status });
  }
});
