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

function requireEnv(value: string | null, name: string) {
  if (!value || !value.trim()) {
    throw createHttpError(500, `Missing ${name}.`);
  }
  return value;
}

async function resolveUser(request: Request, organizationId: string) {
  const authHeader = request.headers.get("authorization");
  if (!authHeader) {
    return null;
  }

  const userClient = createClient(requireEnv(SUPABASE_URL, "SUPABASE_URL"), requireEnv(SUPABASE_ANON_KEY, "SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false }
  });

  const {
    data: { user },
    error
  } = await userClient.auth.getUser();

  if (error || !user) {
    return null;
  }

  const { data: membership } = await userClient.rpc("user_can_access_organization", {
    p_organization_id: organizationId,
    p_permission: "mobile.notifications.manage",
    p_user_id: user.id
  });

  return { user, canAccess: Boolean(membership) };
}

function webpushPayloadFromRecord(record: Record<string, unknown>) {
  return buildPushPayload({
    title: typeof record.title === "string" ? record.title : "ApplianceIQ update",
    body: typeof record.body === "string" ? record.body : "A notification requires attention.",
    url: typeof record.action_url === "string" ? record.action_url : "/dashboard",
    tag: typeof record.category === "string" ? record.category : "applianceiq-notification",
    notificationId: typeof record.id === "string" ? record.id : null,
    organizationId: typeof record.organization_id === "string" ? record.organization_id : null,
    appKey: typeof record.app_key === "string" ? record.app_key : "universal"
  });
}

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);

    const envValues = {
      supabaseUrl: requireEnv(SUPABASE_URL, "SUPABASE_URL"),
      supabaseAnonKey: requireEnv(SUPABASE_ANON_KEY, "SUPABASE_ANON_KEY"),
      serviceKey: requireEnv(SUPABASE_SERVICE_KEY, "SUPABASE_SERVICE_ROLE_KEY"),
      vapidSubject: VAPID_SUBJECT,
      vapidPublicKey: requireEnv(VAPID_PUBLIC_KEY ?? null, "WEB_PUSH_PUBLIC_KEY"),
      vapidPrivateKey: requireEnv(VAPID_PRIVATE_KEY ?? null, "WEB_PUSH_PRIVATE_KEY")
    };

    const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const organizationId = typeof payload.organization_id === "string" ? payload.organization_id : null;
    const recipientUserId = typeof payload.recipient_user_id === "string" ? payload.recipient_user_id : null;
    const appKey = typeof payload.app_key === "string" ? payload.app_key : "universal";

    if (!organizationId) {
      return jsonResponse({ error: "organization_id is required." }, { status: 400 });
    }

    const auth = await resolveUser(request, organizationId);
    if (!auth?.user || !auth.canAccess) {
      return jsonResponse({ error: "Authentication and organization access are required." }, { status: 403 });
    }

    const serviceClient = createClient(envValues.supabaseUrl, envValues.serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: allSubscriptions, error: listError } = recipientUserId
      ? await serviceClient
          .from("push_subscriptions")
          .select("id,organization_id,user_id,app_key,status,endpoint,p256dh,auth_secret,revoked_at,last_seen_at,token_expires_at")
          .eq("organization_id", organizationId)
          .eq("app_key", appKey)
          .eq("user_id", recipientUserId)
      : await serviceClient
          .from("push_subscriptions")
          .select("id,organization_id,user_id,app_key,status,endpoint,p256dh,auth_secret,revoked_at,last_seen_at,token_expires_at")
          .eq("organization_id", organizationId)
          .eq("app_key", appKey);

    if (listError) {
      throw createHttpError(500, "Unable to load push subscriptions.", {
        message: listError?.message ?? "unknown"
      });
    }

    const notificationId = typeof payload.notification_id === "string" ? payload.notification_id : null;
    let notificationRecord: Record<string, unknown> | null = null;
    if (notificationId) {
      const { data, error } = await serviceClient
        .from("mobile_notifications")
        .select("id,organization_id,user_id,app_key,title,body,action_url,category")
        .eq("organization_id", organizationId)
        .eq("id", notificationId)
        .maybeSingle();

      if (error) {
        throw createHttpError(500, "Unable to load mobile notification.", { message: error.message });
      }

      notificationRecord = data as Record<string, unknown> | null;
    }

    const targetSubscriptions = (allSubscriptions ?? []).filter((subscription) => !isExpiredPushSubscription(subscription));
    if (targetSubscriptions.length === 0) {
      return jsonResponse({
        ok: true,
        attempted: 0,
        sent: 0,
        expired: 0,
        failed: 0,
        results: []
      });
    }

    webpush.setVapidDetails(envValues.vapidSubject ?? VAPID_SUBJECT, envValues.vapidPublicKey, envValues.vapidPrivateKey);

    const pushPayload = webpushPayloadFromRecord({
      id: notificationRecord?.id ?? notificationId ?? null,
      organization_id: organizationId,
      app_key: appKey,
      title: typeof payload.title === "string" ? payload.title : notificationRecord?.title,
      body: typeof payload.body === "string" ? payload.body : notificationRecord?.body,
      action_url: typeof payload.url === "string" ? payload.url : notificationRecord?.action_url,
      category: typeof payload.tag === "string" ? payload.tag : notificationRecord?.category
    });

    const results = [];
    for (const subscription of targetSubscriptions) {
      try {
        const response = await webpush.sendNotification(
          {
            endpoint: subscription.endpoint,
            keys: {
              p256dh: subscription.p256dh,
              auth: subscription.auth_secret
            }
          },
          JSON.stringify(pushPayload)
        );

        await serviceClient.from("push_delivery_attempts").insert({
          push_subscription_id: subscription.id,
          notification_id: notificationId,
          organization_id: organizationId,
          user_id: subscription.user_id,
          app_key: appKey,
          status: "sent",
          response_status: response.statusCode,
          delivered_at: new Date().toISOString(),
          metadata: { endpoint: subscription.endpoint }
        });

        if (notificationId) {
          await serviceClient
            .from("mobile_notifications")
            .update({
              push_status: "sent",
              delivered_at: new Date().toISOString()
            })
            .eq("id", notificationId)
            .eq("organization_id", organizationId);
        }

        results.push({ id: subscription.id, status: "sent", response_status: response.statusCode });
      } catch (error) {
        const statusCode = typeof error === "object" && error && "statusCode" in error ? Number(error.statusCode) : null;
        const expired = statusCode === 404 || statusCode === 410 || isExpiredPushSubscription(subscription);

        if (expired) {
          await serviceClient
            .from("push_subscriptions")
            .update({ status: "expired", revoked_at: new Date().toISOString() })
            .eq("id", subscription.id)
            .eq("organization_id", organizationId);
        }

        await serviceClient.from("push_delivery_attempts").insert({
          push_subscription_id: subscription.id,
          notification_id: notificationId,
          organization_id: organizationId,
          user_id: subscription.user_id,
          app_key: appKey,
          status: expired ? "expired" : "failed",
          response_status: statusCode,
          provider_message: error instanceof Error ? error.message : "Push delivery failed.",
          metadata: { endpoint: subscription.endpoint }
        });

        if (notificationId) {
          await serviceClient
            .from("mobile_notifications")
            .update({
              push_status: expired ? "skipped" : "failed"
            })
            .eq("id", notificationId)
            .eq("organization_id", organizationId);
        }

        results.push({ id: subscription.id, status: expired ? "expired" : "failed", response_status: statusCode });
      }
    }

    return jsonResponse({
      ok: true,
      attempted: results.length,
      sent: results.filter((result: any) => result.status === "sent").length,
      expired: results.filter((result: any) => result.status === "expired").length,
      failed: results.filter((result: any) => result.status === "failed").length,
      results
    });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse(
      {
        error: normalized.message,
        details: normalized.details
      },
      { status: normalized.status }
    );
  }
});
