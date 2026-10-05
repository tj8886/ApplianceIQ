import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  buildEmailAuditMetadata,
  extractMessageEmails,
  normalizeEmailAddress,
  resolveStrongEmailAssociation
} from "../_shared/communications.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_WEBHOOK_SECRET = Deno.env.get("RESEND_WEBHOOK_SECRET");
const WEBHOOK_TOLERANCE_SECONDS = 5 * 60;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

function normalizeEventType(eventType: string): string {
  const map: Record<string, string> = {
    "email.sent": "sent",
    "email.delivered": "delivered",
    "email.delivery_delayed": "delayed",
    "email.opened": "opened",
    "email.clicked": "clicked",
    "email.bounced": "bounced",
    "email.complained": "complained",
    "email.failed": "failed"
  };

  return map[eventType] ?? eventType;
}

function decodeBase64(value: string): Uint8Array {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function timingSafeEqual(left: Uint8Array, right: Uint8Array) {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let index = 0; index < left.length; index += 1) {
    diff |= left[index] ^ right[index];
  }
  return diff === 0;
}

function parseSvixSignatures(header: string) {
  return header
    .split(" ")
    .map((part) => part.trim())
    .filter(Boolean)
    .flatMap((part) => {
      const [version, signature] = part.split(",");
      return version === "v1" && signature ? [signature] : [];
    });
}

async function verifySvixSignature(rawBody: string, headers: Headers) {
  if (!RESEND_WEBHOOK_SECRET) {
    return { ok: false, status: 500, error: "Webhook signing secret is not configured." };
  }

  const svixId = headers.get("svix-id");
  const timestamp = headers.get("svix-timestamp");
  const signatureHeader = headers.get("svix-signature");

  if (!svixId || !timestamp || !signatureHeader) {
    return { ok: false, status: 401, error: "Missing webhook signature headers." };
  }

  const timestampNumber = Number(timestamp);
  if (!Number.isFinite(timestampNumber)) {
    return { ok: false, status: 401, error: "Invalid webhook timestamp." };
  }

  const ageSeconds = Math.abs(Math.floor(Date.now() / 1000) - timestampNumber);
  if (ageSeconds > WEBHOOK_TOLERANCE_SECONDS) {
    return { ok: false, status: 401, error: "Webhook timestamp is outside the allowed window." };
  }

  const secret = RESEND_WEBHOOK_SECRET.startsWith("whsec_")
    ? RESEND_WEBHOOK_SECRET.slice("whsec_".length)
    : RESEND_WEBHOOK_SECRET;

  const key = await crypto.subtle.importKey("raw", decodeBase64(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signedContent = `${svixId}.${timestamp}.${rawBody}`;
  const expected = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signedContent)));
  const expectedBase64 = encodeBase64(expected);

  for (const candidate of parseSvixSignatures(signatureHeader)) {
    try {
      if (timingSafeEqual(decodeBase64(candidate), decodeBase64(expectedBase64))) {
        return { ok: true };
      }
    } catch {
      // ignore malformed candidate signatures
    }
  }

  return { ok: false, status: 401, error: "Invalid webhook signature." };
}

async function insertWebhookEvent({
  providerEventId,
  eventType,
  payload,
  organizationId,
  connectedAccountId,
  processingStatus = "received",
  signatureValid = true,
  errorMessage = null
}: {
  providerEventId: string;
  eventType: string;
  payload: Record<string, unknown>;
  organizationId: string | null;
  connectedAccountId: string | null;
  processingStatus?: string;
  signatureValid?: boolean;
  errorMessage?: string | null;
}) {
  const { data, error } = await supabase
    .from("communication_webhook_events")
    .insert({
      organization_id: organizationId,
      connected_account_id: connectedAccountId,
      provider: "resend",
      provider_event_id: providerEventId,
      provider_account_id: null,
      event_type: eventType,
      signature_valid: signatureValid,
      processing_status: processingStatus,
      payload_json: payload,
      error_message: errorMessage,
      metadata: {
        source_system: "email-webhook"
      }
    })
    .select("id")
    .maybeSingle();

  if (error) {
    if ((error as { code?: string }).code === "23505") {
      return { duplicate: true, id: null };
    }

    throw createHttpError(500, "Unable to store webhook event.", { message: error.message });
  }

  return { duplicate: false, id: data?.id ?? null };
}

async function findMessageByProviderIds(providerMessageId: string, providerThreadId: string | null) {
  const messageById = await supabase
    .from("communication_email_messages")
    .select("id,organization_id,provider_message_id,provider_thread_id,subject,recipients,sender,thread_id,metadata")
    .eq("provider", "resend")
    .eq("provider_message_id", providerMessageId)
    .maybeSingle();

  if (messageById.data) {
    return messageById.data;
  }

  if (!providerThreadId) {
    return null;
  }

  const messageByThread = await supabase
    .from("communication_email_messages")
    .select("id,organization_id,provider_message_id,provider_thread_id,subject,recipients,sender,thread_id,metadata")
    .eq("provider", "resend")
    .eq("provider_thread_id", providerThreadId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  return messageByThread.data ?? null;
}

async function findExactContactMatch(emails: string[]) {
  for (const email of emails) {
    const normalized = normalizeEmailAddress(email);
    if (!normalized) {
      continue;
    }

    const { data, error } = await supabase
      .from("aicrm_contacts")
      .select("id,organization_id,account_id,full_name,first_name,last_name,email,aicrm_accounts(id,company_name)")
      .eq("email", normalized)
      .limit(2);

    if (error) {
      throw createHttpError(500, "Unable to resolve contact email.", { message: error.message });
    }

    if ((data ?? []).length === 1) {
      return data[0] as {
        id: string;
        organization_id: string;
        account_id: string | null;
        full_name: string | null;
        first_name: string | null;
        last_name: string | null;
        email: string | null;
        aicrm_accounts?: Array<{ id: string; company_name: string }> | { id: string; company_name: string } | null;
      };
    }
  }

  return null;
}

async function ensureInboundThread(organizationId: string, providerThreadId: string | null, subject: string | null, participants: unknown[]) {
  const threadKey = providerThreadId || `inbound:${organizationId}:${participants.map((item: any) => normalizeEmailAddress(item?.email ?? item ?? null)).filter(Boolean).join(":")}`;
  const { data: existingThread } = await supabase
    .from("communication_email_threads")
    .select("id,provider_thread_id,message_count")
    .eq("organization_id", organizationId)
    .eq("provider", "resend")
    .eq("provider_thread_id", threadKey)
    .maybeSingle();

  if (existingThread) {
    const { data: updatedThread, error } = await supabase
      .from("communication_email_threads")
      .update({
        subject,
        last_message_at: new Date().toISOString(),
        message_count: Number(existingThread.message_count ?? 0) + 1,
        participants,
        sync_status: "synced",
        visibility_scope: "organization"
      })
      .eq("id", existingThread.id)
      .select("id,provider_thread_id")
      .maybeSingle();

    if (error) {
      throw createHttpError(500, "Unable to update inbound thread.", { message: error.message });
    }

    return updatedThread ?? { id: existingThread.id, provider_thread_id: threadKey };
  }

  const { data: createdThread, error } = await supabase
    .from("communication_email_threads")
    .insert({
      organization_id: organizationId,
      provider: "resend",
      provider_thread_id: threadKey,
      subject,
      participants,
      last_message_at: new Date().toISOString(),
      message_count: 1,
      sync_status: "synced",
      visibility_scope: "organization",
      metadata: {
        source_system: "email-webhook",
        direction: "inbound"
      }
    })
    .select("id,provider_thread_id")
    .maybeSingle();

  if (error) {
    throw createHttpError(500, "Unable to create inbound thread.", { message: error.message });
  }

  return createdThread;
}

async function createInboundMessage({
  organizationId,
  threadId,
  providerMessageId,
  providerThreadId,
  sender,
  recipients,
  subject,
  attachments,
  payload
}: {
  organizationId: string;
  threadId: string | null;
  providerMessageId: string;
  providerThreadId: string | null;
  sender: string | null;
  recipients: Array<{ email: string | null }>;
  subject: string | null;
  attachments: unknown[];
  payload: Record<string, unknown>;
}) {
  const { data: message, error } = await supabase
    .from("communication_email_messages")
    .insert({
      organization_id: organizationId,
      thread_id: threadId,
      provider: "resend",
      provider_message_id: providerMessageId,
      provider_thread_id: providerThreadId,
      sender: sender ? { email: sender } : {},
      recipients,
      subject,
      snippet: typeof payload?.body === "string" ? payload.body.slice(0, 280) : null,
      received_at: new Date().toISOString(),
      direction: "inbound",
      attachment_count: attachments.length,
      has_body: typeof payload?.body === "string" && payload.body.length > 0,
      body_storage_status: "metadata_only",
      sync_status: "synced",
      visibility_scope: "organization",
      metadata: {
        source_system: "email-webhook",
        payload
      }
    })
    .select("id")
    .maybeSingle();

  if (error || !message) {
    throw createHttpError(500, "Unable to store inbound message.", { message: error?.message ?? "unknown" });
  }

  if (attachments.length > 0) {
    await storeAttachments(message.id, organizationId, attachments);
  }

  return message.id;
}

async function updateMessageFromWebhook(
  message: {
    id: string;
    organization_id: string;
    provider_message_id: string;
    provider_thread_id: string | null;
    subject: string | null;
    recipients: unknown;
    sender: unknown;
    thread_id: string | null;
    metadata: Record<string, unknown> | null;
  },
  eventType: string,
  payload: Record<string, unknown>
) {
  const messageMetadata = {
    ...(message.metadata ?? {}),
    last_webhook_event: {
      event_type: eventType,
      payload,
      received_at: new Date().toISOString()
    }
  };

  const updatePayload: Record<string, unknown> = {
    metadata: messageMetadata,
    sync_status: "synced"
  };

  if (eventType === "sent") {
    updatePayload.sent_at = new Date().toISOString();
  }

  if (eventType === "delivered" || eventType === "opened" || eventType === "clicked") {
    updatePayload.received_at = new Date().toISOString();
  }

  if (eventType === "bounced" || eventType === "complained" || eventType === "failed") {
    updatePayload.sync_status = "failed";
  }

  const { error } = await supabase.from("communication_email_messages").update(updatePayload).eq("id", message.id);
  if (error) {
    throw createHttpError(500, "Unable to update matched email message.", { message: error.message });
  }

  await supabase.from("communication_audit_events").insert({
    organization_id: message.organization_id,
    event_type: `email_webhook_${eventType}`,
    resource_type: "communication_email_messages",
    resource_id: message.id,
    severity: eventType === "bounced" || eventType === "complained" || eventType === "failed" ? "warning" : "info",
    metadata: buildEmailAuditMetadata(message, eventType, {
      source_system: "email-webhook",
      payload
    })
  });
}

async function storeAttachments(messageId: string, organizationId: string, attachments: unknown[]) {
  const rows = attachments
    .filter((item) => item && typeof item === "object")
    .map((item: any) => ({
      organization_id: organizationId,
      message_id: messageId,
      provider_attachment_id: typeof item.id === "string" ? item.id : null,
      filename: typeof item.filename === "string" ? item.filename : null,
      content_type: typeof item.content_type === "string" ? item.content_type : null,
      size_bytes: typeof item.size === "number" ? item.size : null,
      storage_status: "metadata_only",
      metadata: item
    }));

  if (rows.length === 0) {
    return;
  }

  const { data: existingRows, error: existingError } = await supabase
    .from("communication_email_attachments")
    .select("provider_attachment_id")
    .eq("message_id", messageId)
    .eq("organization_id", organizationId);

  if (existingError) {
    throw createHttpError(500, "Unable to inspect attachment metadata.", { message: existingError.message });
  }

  const existingIds = new Set((existingRows ?? []).map((row: any) => row.provider_attachment_id).filter(Boolean));
  const insertRows = rows.filter((row) => !row.provider_attachment_id || !existingIds.has(row.provider_attachment_id));

  if (insertRows.length === 0) {
    return;
  }

  const { error } = await supabase.from("communication_email_attachments").insert(insertRows);

  if (error) {
    throw createHttpError(500, "Unable to store attachment metadata.", { message: error.message });
  }
}

function extractEventIdentifiers(payload: any) {
  const data = payload?.data ?? {};
  const providerMessageId = data.email_id ?? data.id ?? payload.id ?? null;
  const providerThreadId = data.thread_id ?? data.threadId ?? data.conversation_id ?? null;
  const eventType = normalizeEventType(payload.type ?? "");
  const recipients = Array.isArray(data.to) ? data.to : data.to ? [data.to] : [];
  const sender = data.from ?? payload.from ?? null;

  return {
    providerMessageId: typeof providerMessageId === "string" ? providerMessageId : null,
    providerThreadId: typeof providerThreadId === "string" ? providerThreadId : null,
    eventType,
    recipients,
    sender
  };
}

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);

    const rawBody = await request.text();
    const signature = await verifySvixSignature(rawBody, request.headers);
    if (!signature.ok) {
      return jsonResponse({ error: signature.error }, { status: signature.status });
    }

    let payload: any;
    try {
      payload = JSON.parse(rawBody);
    } catch {
      return jsonResponse({ error: "invalid json" }, { status: 400 });
    }

    const { providerMessageId, providerThreadId, eventType, recipients, sender } = extractEventIdentifiers(payload);
    if (!providerMessageId) {
      return jsonResponse({ ok: true, recorded: false, reason: "no_message_id" });
    }

    const eventPayload: Record<string, unknown> = {
      email: recipients.map((item: any) => normalizeEmailAddress(item?.email ?? item?.address ?? item ?? null)).filter(Boolean),
      sender: normalizeEmailAddress(sender?.email ?? sender?.address ?? sender ?? null),
      ip: payload.data?.ip ?? null,
      user_agent: payload.data?.user_agent ?? null,
      url: payload.data?.url ?? null,
      bounce_type: payload.data?.bounce?.type ?? null,
      bounce_description: payload.data?.bounce?.message ?? null,
      attachments: payload.data?.attachments ?? [],
      raw: payload
    };

    const matchedMessage = await findMessageByProviderIds(providerMessageId, providerThreadId);
    const matchedEmail = matchedMessage
      ? resolveStrongEmailAssociation({
          existingMessage: matchedMessage,
          reason: "provider_message_match"
        })
      : resolveStrongEmailAssociation({
          reason: "unmatched_webhook"
        });

    if (!matchedMessage) {
      const exactContact = await findExactContactMatch([sender ?? null, ...recipients.map((item: any) => item?.email ?? item?.address ?? item ?? null)]);
      if (exactContact) {
        const webhookEvent = await insertWebhookEvent({
          providerEventId: payload.id ?? providerMessageId,
          eventType,
          payload: eventPayload,
          organizationId: exactContact.organization_id,
          connectedAccountId: null,
          signatureValid: true
        });

        if (webhookEvent.duplicate) {
          return jsonResponse({ ok: true, recorded: false, duplicate: true, event_type: eventType });
        }

        const organizationId = exactContact.organization_id;
        const senderEmail = normalizeEmailAddress(sender?.email ?? sender?.address ?? sender ?? null);
        const recipientEmails = recipients.map((item: any) => normalizeEmailAddress(item?.email ?? item?.address ?? item ?? null)).filter(Boolean);
        const participants = [
          senderEmail ? { email: senderEmail } : null,
          ...recipientEmails.map((email) => ({ email }))
        ].filter(Boolean);
        const thread = await ensureInboundThread(organizationId, providerThreadId, payload.data?.subject ?? payload.subject ?? null, participants);
        const messageId = await createInboundMessage({
          organizationId,
          threadId: thread?.id ?? null,
          providerMessageId,
          providerThreadId,
          sender: senderEmail,
          recipients: recipientEmails.map((email) => ({ email })),
          subject: payload.data?.subject ?? payload.subject ?? null,
          attachments: Array.isArray(payload.data?.attachments) ? payload.data.attachments : [],
          payload: eventPayload
        });

        await supabase.from("communication_record_links").upsert(
          [
            {
              organization_id: organizationId,
              source_system: "email-webhook",
              source_record_id: messageId,
              linked_entity_type: "contact",
              linked_entity_id: exactContact.id,
              visibility_scope: "organization",
              metadata: {
                association_type: "exact_email_match"
              }
            },
            exactContact.account_id
              ? {
                  organization_id: organizationId,
                  source_system: "email-webhook",
                  source_record_id: messageId,
                  linked_entity_type: "company",
                  linked_entity_id: exactContact.account_id,
                  visibility_scope: "organization",
                  metadata: {
                    association_type: "exact_email_match"
                  }
                }
              : null
          ].filter(Boolean) as Array<Record<string, unknown>>,
          {
            onConflict: "source_system,source_record_id,linked_entity_type,linked_entity_id"
          }
        );

        await supabase.from("communication_audit_events").insert({
          organization_id: organizationId,
          event_type: "email_associated",
          resource_type: "communication_email_messages",
          resource_id: messageId,
          severity: "info",
          metadata: {
            association_type: "exact_email_match",
            contact_id: exactContact.id,
            account_id: exactContact.account_id
          }
        });

        return jsonResponse({
          ok: true,
          recorded: true,
          associated: true,
          association_type: "contact",
          event_type: eventType
        });
      }
    }

    const webhookEvent = await insertWebhookEvent({
      providerEventId: payload.id ?? providerMessageId,
      eventType,
      payload: eventPayload,
      organizationId: matchedMessage?.organization_id ?? null,
      connectedAccountId: null,
      signatureValid: true
    });

    if (webhookEvent.duplicate) {
      return jsonResponse({ ok: true, recorded: false, duplicate: true, event_type: eventType });
    }

    if (matchedMessage) {
      await updateMessageFromWebhook(matchedMessage, eventType, eventPayload);

      const attachments = Array.isArray(payload.data?.attachments) ? payload.data.attachments : [];
      if (attachments.length > 0) {
        await storeAttachments(matchedMessage.id, matchedMessage.organization_id, attachments);
      }

      return jsonResponse({
        ok: true,
        recorded: true,
        associated: true,
        association_type: matchedEmail.association_type,
        event_type: eventType
      });
    }

    return jsonResponse({
      ok: true,
      recorded: true,
      associated: false,
      event_type: eventType
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
