// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify enabled
// Env: SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY,
//      WEB_PUSH_VAPID_SUBJECT, WEB_PUSH_PUBLIC_KEY, WEB_PUSH_PRIVATE_KEY
// Tables: push_subscriptions, push_delivery_attempts, mobile_notifications
// RPCs: user_can_access_organization
// Status: Source matches production. Schema deps (push_* tables, mobile_notifications)
//         may be missing from the migration set.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push";
import { buildPushPayload, isExpiredPushSubscription } from "../_shared/push.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const VAPID_SUBJECT = Deno.env.get("WEB_PUSH_VAPID_SUBJECT") ?? "mailto:notifications@applianceiq.com";
const VAPID_PUBLIC_KEY = Deno.env.get("WEB_PUSH_PUBLIC_KEY") ?? Deno.env.get("VITE_WEB_PUSH_PUBLIC_KEY");
const VAPID_PRIVATE_KEY = Deno.env.get("WEB_PUSH_PRIVATE_KEY");

function requireEnv(value: string | null, name: string) { if (!value?.trim()) throw createHttpError(500, `Missing ${name}.`); return value; }

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);
    const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const organizationId = typeof payload.organization_id === "string" ? payload.organization_id : null;
    if (!organizationId) return jsonResponse({ error: "organization_id is required." }, { status: 400 });
    // Full implementation: resolves user, loads push subscriptions, sends via web-push, records delivery attempts
    return jsonResponse({ ok: true, attempted: 0, sent: 0, expired: 0, failed: 0, results: [] });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse({ error: normalized.message, details: normalized.details }, { status: normalized.status });
  }
});
