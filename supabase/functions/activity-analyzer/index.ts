// activity-analyzer — server-side AI for the CRM capture layer.
// Modes:
//   process    — full recording pipeline: transcribe (OpenAI STT) -> coach (Anthropic) with status transitions
//   transcribe — STT only
//   coach      — 7-steps KPI scoring (Anthropic)
//   summarize  — communication summary (Anthropic)
// Caller auth: user JWT; access enforced by reading the activity through RLS as the user.
// API keys live in edge secrets only — never in frontend code.

import { createClient } from "jsr:@supabase/supabase-js@2";

const SEVEN_STEPS = ["prospecting","preparation","needs_discovery","presentation","objection_handling","closing","follow_up"];
const MAX_FILE_BYTES = 26_214_400; // 25 MB (STT provider limit)
const MAX_DURATION_SECONDS = 1800; // 30 min

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);

  let body: { mode?: string; activity_id?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const mode = String(body.mode ?? "");
  const activityId = String(body.activity_id ?? "");
  if (!["process","transcribe","coach","summarize"].includes(mode) || !activityId) {
    return json({ error: "mode_and_activity_id_required" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey);

  // Access check via RLS: if the user can read the activity, they can analyze it.
  const { data: act, error: actErr } = await userClient
    .from("activities")
    .select("id, organization_id, activity_type, title, summary, entity_type, entity_id, related_recording_id, related_email_id, metadata")
    .eq("id", activityId)
    .maybeSingle();
  if (actErr || !act) return json({ error: "activity_not_found_or_access_denied" }, 403);
  const orgId = act.organization_id as string;

  // ---------- PROCESS: full pipeline for a recording ----------
  if (mode === "process") {
    if (!act.related_recording_id) return json({ error: "no_recording_on_activity" }, 400);
    const { data: rec } = await admin.from("sales_recordings").select("*").eq("id", act.related_recording_id).single();
    if (!rec) return json({ error: "recording_not_found" }, 404);

    if (!rec.consent_confirmed) {
      await fail(admin, rec.id, "consent_not_confirmed");
      return json({ error: "consent_not_confirmed", detail: "Recording cannot be processed without confirmed consent." }, 400);
    }
    if (rec.file_size_bytes && rec.file_size_bytes > MAX_FILE_BYTES) {
      await fail(admin, rec.id, "file_too_large");
      return json({ error: "file_too_large", detail: `Max ${Math.round(MAX_FILE_BYTES/1048576)} MB.` }, 400);
    }
    if (rec.duration_seconds && rec.duration_seconds > MAX_DURATION_SECONDS) {
      await fail(admin, rec.id, "recording_too_long");
      return json({ error: "recording_too_long", detail: `Max ${MAX_DURATION_SECONDS/60} minutes.` }, 400);
    }

    // --- Step 1: transcribe ---
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!openaiKey) {
      await fail(admin, rec.id, "openai_api_key_not_configured");
      return json({ error: "openai_api_key_not_configured", detail: "Add OPENAI_API_KEY to Supabase Edge Function secrets to enable transcription." }, 503);
    }
    await admin.from("sales_recordings").update({ status: "transcribing" }).eq("id", rec.id);

    const { data: fileData, error: dlErr } = await admin.storage.from("crm-media").download(rec.file_path);
    if (dlErr || !fileData) {
      await fail(admin, rec.id, `download_failed: ${dlErr?.message ?? ""}`);
      return json({ error: "recording_download_failed", detail: dlErr?.message }, 500);
    }
    if (fileData.size > MAX_FILE_BYTES) {
      await fail(admin, rec.id, "file_too_large");
      return json({ error: "file_too_large", detail: `Max ${Math.round(MAX_FILE_BYTES/1048576)} MB.` }, 400);
    }

    const form = new FormData();
    form.append("file", new File([fileData], rec.file_name ?? rec.file_path.split("/").pop() ?? "audio.webm", { type: rec.mime_type ?? "audio/webm" }));
    form.append("model", "whisper-1");
    const sttResp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${openaiKey}` }, body: form,
    });
    if (!sttResp.ok) {
      const errText = (await sttResp.text()).slice(0, 300);
      await fail(admin, rec.id, `transcription_failed: ${errText}`);
      return json({ error: "transcription_failed", detail: errText }, 502);
    }
    const tr = await sttResp.json();
    const content = String(tr.text ?? "").trim();

    const { data: transcript } = await admin.from("recording_transcripts")
      .insert({ organization_id: orgId, recording_id: rec.id, content, model: "openai:whisper-1" })
      .select("id").single();
    await admin.from("sales_recordings").update({ status: "transcribed", transcript_id: transcript?.id ?? null }).eq("id", rec.id);
    await admin.from("activities").update({ metadata: { ...(act.metadata ?? {}), has_transcript: true } }).eq("id", act.id);
    await audit(admin, orgId, act.id, "crm.recording.transcribed", { recording_id: rec.id, chars: content.length });

    if (content.length < 20) {
      await fail(admin, rec.id, "transcript_too_short");
      return json({ error: "transcript_too_short", detail: "Not enough speech was detected to analyze.", transcript_id: transcript?.id }, 400);
    }

    // --- Step 2: coach ---
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) {
      await fail(admin, rec.id, "anthropic_api_key_not_configured");
      return json({ error: "anthropic_api_key_not_configured", detail: "Transcript saved, but add ANTHROPIC_API_KEY to Edge Function secrets to enable coaching.", transcript_id: transcript?.id }, 503);
    }
    await admin.from("sales_recordings").update({ status: "analyzing" }).eq("id", rec.id);

    const model = Deno.env.get("AI_MODEL") ?? "claude-sonnet-4-6";
    const coachResult = await coachText(anthropicKey, model, content.slice(0, 24000));
    if ("error" in coachResult) {
      await fail(admin, rec.id, coachResult.error);
      return json({ error: coachResult.error, detail: coachResult.detail, transcript_id: transcript?.id }, 502);
    }
    const parsed = coachResult.parsed;

    const { data: review } = await admin.from("ai_coaching_reviews").insert({
      organization_id: orgId, activity_id: act.id, recording_id: rec.id,
      review_kind: "coaching",
      analysis: { strengths: parsed.strengths, improvements: parsed.improvements, best_moment: parsed.best_moment, next_actions: parsed.next_actions },
      kpi_scores: parsed.kpi_scores ?? {}, overall_score: parsed.overall_score ?? null, model,
    }).select("id, kpi_scores, overall_score, analysis").single();

    await admin.from("sales_recordings").update({ status: "complete", coaching_review_id: review?.id ?? null }).eq("id", rec.id);
    await audit(admin, orgId, act.id, "crm.recording.processed", { recording_id: rec.id, review_id: review?.id, overall: parsed.overall_score });
    return json({ ok: true, transcript_id: transcript?.id, review });
  }

  // ---------- TRANSCRIBE (single step) ----------
  if (mode === "transcribe") {
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!openaiKey) return json({ error: "openai_api_key_not_configured", detail: "Add OPENAI_API_KEY to Edge Function secrets to enable transcription." }, 503);
    if (!act.related_recording_id) return json({ error: "no_recording_on_activity" }, 400);

    const { data: rec } = await admin.from("sales_recordings").select("*").eq("id", act.related_recording_id).single();
    if (!rec) return json({ error: "recording_not_found" }, 404);

    await admin.from("sales_recordings").update({ status: "transcribing" }).eq("id", rec.id);
    const { data: fileData, error: dlErr } = await admin.storage.from("crm-media").download(rec.file_path);
    if (dlErr || !fileData) {
      await fail(admin, rec.id, `download_failed: ${dlErr?.message ?? ""}`);
      return json({ error: "recording_download_failed", detail: dlErr?.message }, 500);
    }

    const form = new FormData();
    form.append("file", new File([fileData], rec.file_name ?? rec.file_path.split("/").pop() ?? "audio.webm", { type: rec.mime_type ?? "audio/webm" }));
    form.append("model", "whisper-1");
    const resp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${openaiKey}` }, body: form,
    });
    if (!resp.ok) {
      const errText = (await resp.text()).slice(0, 300);
      await fail(admin, rec.id, `transcription_failed: ${errText}`);
      return json({ error: "transcription_failed", detail: errText }, 502);
    }
    const tr = await resp.json();
    const content = String(tr.text ?? "").trim();

    const { data: transcript } = await admin.from("recording_transcripts")
      .insert({ organization_id: orgId, recording_id: rec.id, content, model: "openai:whisper-1" })
      .select("id").single();
    await admin.from("sales_recordings").update({ status: "transcribed", transcript_id: transcript?.id ?? null }).eq("id", rec.id);
    await admin.from("activities").update({ metadata: { ...(act.metadata ?? {}), has_transcript: true } }).eq("id", act.id);
    await audit(admin, orgId, act.id, "crm.activity.transcribed", { recording_id: rec.id, chars: content.length });
    return json({ ok: true, transcript_id: transcript?.id, chars: content.length });
  }

  // ---------- Gather text for coach/summarize ----------
  let sourceText = "";
  if (act.related_recording_id) {
    const { data: t } = await admin.from("recording_transcripts")
      .select("content").eq("recording_id", act.related_recording_id)
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    sourceText = t?.content ?? "";
    if (!sourceText) return json({ error: "no_transcript_yet", detail: "Run transcription first." }, 400);
  } else if (act.related_email_id) {
    const { data: em } = await admin.from("crm_emails").select("subject, body, to_email").eq("id", act.related_email_id).single();
    sourceText = em ? `EMAIL to ${em.to_email ?? "client"}\nSubject: ${em.subject}\n\n${em.body ?? ""}` : "";
  } else {
    sourceText = [act.title, act.summary, JSON.stringify(act.metadata?.body ?? "")].filter(Boolean).join("\n");
  }
  if (sourceText.trim().length < 20) return json({ error: "not_enough_content_to_analyze" }, 400);
  sourceText = sourceText.slice(0, 24000);

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!anthropicKey) return json({ error: "anthropic_api_key_not_configured", detail: "Add ANTHROPIC_API_KEY to Edge Function secrets." }, 503);
  const model = Deno.env.get("AI_MODEL") ?? "claude-sonnet-4-6";

  if (mode === "coach") {
    const coachResult = await coachText(anthropicKey, model, sourceText);
    if ("error" in coachResult) return json({ error: coachResult.error, detail: coachResult.detail }, 502);
    const parsed = coachResult.parsed;
    const { data: review } = await admin.from("ai_coaching_reviews").insert({
      organization_id: orgId, activity_id: act.id, recording_id: act.related_recording_id,
      review_kind: "coaching",
      analysis: { strengths: parsed.strengths, improvements: parsed.improvements, best_moment: parsed.best_moment, next_actions: parsed.next_actions },
      kpi_scores: parsed.kpi_scores ?? {}, overall_score: parsed.overall_score ?? null, model,
    }).select("id, kpi_scores, overall_score, analysis").single();
    if (act.related_recording_id) {
      await admin.from("sales_recordings").update({ coaching_review_id: review?.id ?? null }).eq("id", act.related_recording_id);
    }
    await audit(admin, orgId, act.id, "crm.activity.coached", { review_id: review?.id, overall: parsed.overall_score });
    return json({ ok: true, review });
  } else {
    const system = `You are the Appliance IQ communication summarizer. Verified-over-hyped voice. Summarize the client communication below for the CRM record. Respond ONLY with JSON, no markdown fences: {"summary":"<3-4 sentence factual summary>","client_intent":"<one line>","open_items":[..max 3..],"sentiment":"positive|neutral|at_risk"}. Only state what the content supports.`;
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model, max_tokens: 1500, system, messages: [{ role: "user", content: sourceText }] }),
    });
    if (!resp.ok) return json({ error: "model_call_failed", detail: (await resp.text()).slice(0, 300) }, 502);
    const data = await resp.json();
    const raw = (data.content ?? []).filter((b: {type:string}) => b.type === "text").map((b: {text:string}) => b.text).join("");
    let parsed: Record<string, unknown>;
    try { parsed = JSON.parse(raw.replace(/```json|```/g, "").trim()); }
    catch { return json({ error: "model_output_parse_failed" }, 502); }
    await admin.from("activities").update({
      summary: String(parsed.summary ?? "").slice(0, 2000),
      metadata: { ...(act.metadata ?? {}), ai_summary: parsed, ai_summary_model: model },
    }).eq("id", act.id);
    await admin.from("ai_coaching_reviews").insert({
      organization_id: orgId, activity_id: act.id, recording_id: act.related_recording_id,
      review_kind: "summary", analysis: parsed, model,
    });
    await audit(admin, orgId, act.id, "crm.activity.summarized", { sentiment: parsed.sentiment });
    return json({ ok: true, summary: parsed });
  }
});

async function coachText(anthropicKey: string, model: string, sourceText: string):
  Promise<{ parsed: Record<string, any> } | { error: string; detail?: string }> {
  const system = `You are the Appliance IQ sales coach. Brand voice: verified over hyped; evidence-first. Analyze the sales interaction below against the 7 steps of sales: ${SEVEN_STEPS.join(", ")}. Respond ONLY with JSON, no markdown fences: {"kpi_scores":{${SEVEN_STEPS.map((s)=>`"${s}":<0-10>`).join(",")}},"overall_score":<0-10 one decimal>,"strengths":[..max 4 short strings..],"improvements":[..max 4 short, each naming the step and the concrete fix..],"best_moment":"<short quote or paraphrase>","next_actions":[..max 3..]}. Score only what the content shows; if a step is absent, score it low and say so in improvements. Never invent quotes.`;
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model, max_tokens: 1500, system, messages: [{ role: "user", content: sourceText }] }),
  });
  if (!resp.ok) return { error: "model_call_failed", detail: (await resp.text()).slice(0, 300) };
  const data = await resp.json();
  const raw = (data.content ?? []).filter((b: {type:string}) => b.type === "text").map((b: {text:string}) => b.text).join("");
  try { return { parsed: JSON.parse(raw.replace(/```json|```/g, "").trim()) }; }
  catch { return { error: "model_output_parse_failed" }; }
}

async function fail(admin: ReturnType<typeof createClient>, recordingId: string, reason: string) {
  const { data: rec } = await admin.from("sales_recordings").select("metadata").eq("id", recordingId).single();
  await admin.from("sales_recordings").update({
    status: "failed",
    metadata: { ...(rec?.metadata ?? {}), last_error: reason.slice(0, 500), failed_at: new Date().toISOString() },
  }).eq("id", recordingId);
}

async function audit(admin: ReturnType<typeof createClient>, orgId: string, activityId: string, eventType: string, payload: Record<string, unknown>) {
  await admin.from("ai_audit_events").insert({
    organization_id: orgId, event_type: eventType, event_payload: { activity_id: activityId, ...payload },
  });
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
