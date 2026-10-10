// activity-analyzer v4 — persona-aware coaching with handoff detection.
// Modes: process | transcribe | coach | summarize | persona_coach (new)
// v4: custom KPIs, persona routing, handoff detection, conversational coaching

import { createClient } from "jsr:@supabase/supabase-js@2";

const SEVEN_STEPS_FALLBACK = ["prospecting","preparation","needs_discovery","presentation","objection_handling","closing","follow_up"];
const MODEL_LIGHT = Deno.env.get("AI_MODEL_LIGHT") ?? "claude-haiku-4-5";
const MODEL_STANDARD = Deno.env.get("AI_MODEL") ?? "claude-sonnet-4-6";
const SHORT_TRANSCRIPT_CHARS = 1200;
function pickCoachModel(text: string): string {
  return text.length < SHORT_TRANSCRIPT_CHARS ? MODEL_LIGHT : MODEL_STANDARD;
}
const MAX_FILE_BYTES = 26_214_400;
const MAX_DURATION_SECONDS = 10800;

interface Persona { persona_name: string; persona_role: string; avatar_emoji: string; tone: string; specialization: string; prompt_prefix: string; }
interface CommProtocol { persona_name: string; handoff_triggers: string[]; handoff_style: string; handoff_template: string; debate_approach: string; defer_pattern: string; max_response_length: string; }

async function loadOrgKpis(admin: ReturnType<typeof createClient>, orgId: string): Promise<string[]> {
  const { data } = await admin.from("org_kpis").select("kpi_name").eq("organization_id", orgId).eq("active", true);
  if (data && data.length > 0) return data.map((k: any) => k.kpi_name);
  return SEVEN_STEPS_FALLBACK;
}

async function loadPersonas(admin: ReturnType<typeof createClient>, orgId: string): Promise<Persona[]> {
  const { data } = await admin.from("ai_personas").select("persona_name, persona_role, avatar_emoji, tone, specialization, prompt_prefix").eq("organization_id", orgId).eq("active", true);
  return (data ?? []) as Persona[];
}

async function loadProtocols(admin: ReturnType<typeof createClient>, orgId: string): Promise<CommProtocol[]> {
  const { data } = await admin.from("persona_communication_protocol").select("persona_name, handoff_triggers, handoff_style, handoff_template, debate_approach, defer_pattern, max_response_length").eq("organization_id", orgId);
  return (data ?? []) as CommProtocol[];
}

function detectPersonas(text: string, personas: Persona[], protocols: CommProtocol[]): { primary: Persona; secondaries: Persona[] } {
  const lower = text.toLowerCase();
  const scored: { persona: Persona; score: number }[] = [];
  for (const p of personas) {
    let score = 0;
    const proto = protocols.find(pr => pr.persona_name === p.persona_name);
    if (proto) {
      for (const trigger of proto.handoff_triggers) {
        if (lower.includes(trigger.toLowerCase())) score += 3;
      }
    }
    const specWords = p.specialization.toLowerCase().split(/[,\s]+/);
    for (const w of specWords) {
      if (w.length > 3 && lower.includes(w)) score += 1;
    }
    scored.push({ persona: p, score });
  }
  scored.sort((a, b) => b.score - a.score);
  let primary: Persona;
  const secondaries: Persona[] = [];
  if (scored[0].score > 0 && scored[0].persona.persona_name !== "TJ") {
    primary = scored[0].persona;
    const tj = scored.find(s => s.persona.persona_name === "TJ");
    if (tj && tj.persona !== primary) secondaries.push(tj.persona);
    for (const s of scored.slice(1)) {
      if (s.score >= 2 && s.persona !== primary && !secondaries.includes(s.persona) && secondaries.length < 2) {
        secondaries.push(s.persona);
      }
    }
  } else {
    primary = scored.find(s => s.persona.persona_name === "TJ")?.persona ?? scored[0].persona;
    if (scored[0].score > 0 && scored[0].persona !== primary) secondaries.push(scored[0].persona);
  }
  return { primary, secondaries };
}

function buildPersonaCoachSystem(primary: Persona, secondaries: Persona[], protocols: CommProtocol[], kpis: string[], mode: "coach" | "persona_coach"): string {
  const primaryProto = protocols.find(p => p.persona_name === primary.persona_name);
  let system = primary.prompt_prefix + "\n\n";
  system += "VOICE & STYLE: " + primary.tone + ". Keep responses brief — under 250 words. Verified over hyped. Evidence before claims.\n\n";
  if (secondaries.length > 0) {
    system += "TEAM COLLABORATION: You're part of a coaching team (siblings who work together). ";
    for (const sec of secondaries) {
      const secProto = protocols.find(p => p.persona_name === sec.persona_name);
      system += `When the topic touches ${sec.persona_name}'s area (${sec.persona_role}), include their perspective naturally: "${secProto?.handoff_template ?? 'Let me bring in ' + sec.persona_name + '.'}" `;
      system += `Their style is ${sec.tone}. `;
    }
    if (primaryProto) {
      system += `Your debate style: ${primaryProto.debate_approach}. Your defer pattern: ${primaryProto.defer_pattern}. `;
    }
    system += "Keep handoffs to 1-2 sentences each. Total response under 300 words.\n\n";
  }
  if (mode === "coach") {
    system += `SCORING: Analyze the sales interaction against these KPIs: ${kpis.join(", ")}. `;
    system += `Respond ONLY with JSON (no markdown fences): {"kpi_scores":{${kpis.map(k => `"${k}":<0-10>`).join(",")}},"overall_score":<0-10 one decimal>,"strengths":[..max 4 short strings..],"improvements":[..max 4, each naming the KPI and the concrete fix..],"best_moment":"<short quote or paraphrase>","next_actions":[..max 3..],"primary_persona":"${primary.persona_name}","handoffs":[${secondaries.map(s => `{"persona":"${s.persona_name}","insight":"<one sentence>"}`).join(",")}]}. `;
    system += "Score only what the content shows; if a KPI area is absent, score it low. Never invent quotes.";
  } else {
    system += "CONTEXT: A sales rep is asking you a coaching question. Answer in your persona's voice. ";
    if (secondaries.length > 0) {
      system += "If part of the question falls outside your specialty, naturally hand off to the relevant team member and include their perspective. ";
      system += "Use the team member's name and emoji naturally. ";
    }
    system += `The org's KPIs are: ${kpis.join(", ")}. Reference them when relevant. `;
    system += "Respond as plain text (not JSON). Be direct, actionable, and keep it under 250 words.";
  }
  return system;
}

function buildFallbackCoachSystem(kpis: string[]): string {
  return `You are the Appliance IQ sales coach. Brand voice: verified over hyped; evidence-first. Analyze the sales interaction against these KPIs: ${kpis.join(", ")}. Respond ONLY with JSON, no markdown fences: {"kpi_scores":{${kpis.map(k => `"${k}":<0-10>`).join(",")}},"overall_score":<0-10 one decimal>,"strengths":[..max 4 short strings..],"improvements":[..max 4, each naming the KPI and the concrete fix..],"best_moment":"<short quote or paraphrase>","next_actions":[..max 3..]}. Score only what the content shows. Never invent quotes.`;
}

async function callClaude(anthropicKey: string, model: string, system: string, sourceText: string):
  Promise<{ parsed: Record<string, any> } | { error: string; detail?: string }> {
  const resp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({ model, max_tokens: 1500, system, messages: [{ role: "user", content: sourceText }] }),
  });
  if (!resp.ok) return { error: "model_call_failed", detail: (await resp.text()).slice(0, 300) };
  const data = await resp.json();
  const raw = (data.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
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

// ---- Main handler ----

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);

  let body: { mode?: string; activity_id?: string; question?: string; organization_id?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const mode = String(body.mode ?? "");

  if (!["process","transcribe","coach","summarize","persona_coach"].includes(mode)) {
    return json({ error: "invalid_mode" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const userClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
  const admin = createClient(url, serviceKey);

  // --- persona_coach: conversational coaching (no activity needed) ---
  if (mode === "persona_coach") {
    const question = String(body.question ?? "").trim();
    const orgId = String(body.organization_id ?? "");
    if (!question || !orgId) return json({ error: "question_and_organization_id_required" }, 400);

    const { data: member } = await userClient.from("organization_members").select("id").eq("organization_id", orgId).maybeSingle();
    if (!member) return json({ error: "not_a_member" }, 403);

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) return json({ error: "anthropic_api_key_not_configured" }, 503);

    const [kpis, personas, protocols] = await Promise.all([
      loadOrgKpis(admin, orgId),
      loadPersonas(admin, orgId),
      loadProtocols(admin, orgId),
    ]);
    if (personas.length === 0) return json({ error: "no_personas_configured" }, 400);

    const { primary, secondaries } = detectPersonas(question, personas, protocols);
    const systemPrompt = buildPersonaCoachSystem(primary, secondaries, protocols, kpis, "persona_coach");

    const { data: knowledge } = await admin.from("ai_knowledge_chunks").select("content").eq("organization_id", orgId).limit(5);
    const knowledgeCtx = knowledge?.map((k: any) => k.content).join("\n") ?? "";
    const userMsg = knowledgeCtx ? `[Company knowledge base]\n${knowledgeCtx}\n\n[Rep's question]\n${question}` : question;

    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: MODEL_STANDARD, max_tokens: 1000, system: systemPrompt, messages: [{ role: "user", content: userMsg }] }),
    });
    if (!resp.ok) return json({ error: "model_call_failed", detail: (await resp.text()).slice(0, 300) }, 502);
    const data = await resp.json();
    const answer = (data.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");

    await audit(admin, orgId, "direct", "crm.persona_coach.answered", {
      primary_persona: primary.persona_name,
      secondaries: secondaries.map(s => s.persona_name),
      question_length: question.length,
    });

    return json({
      ok: true, answer,
      primary_persona: { name: primary.persona_name, emoji: primary.avatar_emoji, role: primary.persona_role },
      handoffs: secondaries.map(s => ({ name: s.persona_name, emoji: s.avatar_emoji, role: s.persona_role })),
    });
  }

  // --- All other modes need activity_id ---
  const activityId = String(body.activity_id ?? "");
  if (!activityId) return json({ error: "activity_id_required" }, 400);

  const { data: act, error: actErr } = await userClient
    .from("activities")
    .select("id, organization_id, activity_type, title, summary, entity_type, entity_id, related_recording_id, related_email_id, metadata")
    .eq("id", activityId)
    .maybeSingle();
  if (actErr || !act) return json({ error: "activity_not_found_or_access_denied" }, 403);
  const orgId = act.organization_id as string;

  // ---------- PROCESS ----------
  if (mode === "process") {
    if (!act.related_recording_id) return json({ error: "no_recording_on_activity" }, 400);
    const { data: rec } = await admin.from("sales_recordings").select("*").eq("id", act.related_recording_id).single();
    if (!rec) return json({ error: "recording_not_found" }, 404);

    if (!rec.consent_confirmed) { await fail(admin, rec.id, "consent_not_confirmed"); return json({ error: "consent_not_confirmed" }, 400); }
    if (rec.file_size_bytes && rec.file_size_bytes > MAX_FILE_BYTES) { await fail(admin, rec.id, "file_too_large"); return json({ error: "file_too_large" }, 400); }
    if (rec.duration_seconds && rec.duration_seconds > MAX_DURATION_SECONDS) { await fail(admin, rec.id, "recording_too_long"); return json({ error: "recording_too_long" }, 400); }

    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!openaiKey) { await fail(admin, rec.id, "openai_api_key_not_configured"); return json({ error: "openai_api_key_not_configured" }, 503); }
    await admin.from("sales_recordings").update({ status: "transcribing" }).eq("id", rec.id);

    const { data: fileData, error: dlErr } = await admin.storage.from("crm-media").download(rec.file_path);
    if (dlErr || !fileData) { await fail(admin, rec.id, `download_failed: ${dlErr?.message ?? ""}`); return json({ error: "recording_download_failed" }, 500); }

    const form = new FormData();
    form.append("file", new File([fileData], rec.file_name ?? rec.file_path.split("/").pop() ?? "audio.webm", { type: rec.mime_type ?? "audio/webm" }));
    form.append("model", "whisper-1");
    const sttResp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${openaiKey}` }, body: form,
    });
    if (!sttResp.ok) { const e = (await sttResp.text()).slice(0, 300); await fail(admin, rec.id, `transcription_failed: ${e}`); return json({ error: "transcription_failed", detail: e }, 502); }
    const tr = await sttResp.json();
    const content = String(tr.text ?? "").trim();

    const { data: transcript } = await admin.from("recording_transcripts")
      .insert({ organization_id: orgId, recording_id: rec.id, content, model: "openai:whisper-1" })
      .select("id").single();
    await admin.from("sales_recordings").update({ status: "transcribed", transcript_id: transcript?.id ?? null }).eq("id", rec.id);
    await admin.from("activities").update({ metadata: { ...(act.metadata ?? {}), has_transcript: true } }).eq("id", act.id);
    await audit(admin, orgId, act.id, "crm.recording.transcribed", { recording_id: rec.id, chars: content.length });

    if (content.length < 20) { await fail(admin, rec.id, "transcript_too_short"); return json({ error: "transcript_too_short", transcript_id: transcript?.id }, 400); }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) { await fail(admin, rec.id, "anthropic_api_key_not_configured"); return json({ error: "anthropic_api_key_not_configured", transcript_id: transcript?.id }, 503); }
    await admin.from("sales_recordings").update({ status: "analyzing" }).eq("id", rec.id);

    const [kpis, personas, protocols] = await Promise.all([
      loadOrgKpis(admin, orgId), loadPersonas(admin, orgId), loadProtocols(admin, orgId),
    ]);
    const detected = personas.length > 0 ? detectPersonas(content, personas, protocols) : null;

    const model = pickCoachModel(content);
    const systemPrompt = detected
      ? buildPersonaCoachSystem(detected.primary, detected.secondaries, protocols, kpis, "coach")
      : buildFallbackCoachSystem(kpis);

    const coachResult = await callClaude(anthropicKey, model, systemPrompt, content.slice(0, 24000));
    if ("error" in coachResult) { await fail(admin, rec.id, coachResult.error); return json({ error: coachResult.error, detail: coachResult.detail, transcript_id: transcript?.id }, 502); }
    const parsed = coachResult.parsed;

    const { data: review } = await admin.from("ai_coaching_reviews").insert({
      organization_id: orgId, activity_id: act.id, recording_id: rec.id,
      review_kind: "coaching",
      analysis: {
        strengths: parsed.strengths, improvements: parsed.improvements,
        best_moment: parsed.best_moment, next_actions: parsed.next_actions,
        primary_persona: parsed.primary_persona ?? detected?.primary?.persona_name ?? "system",
        handoffs: parsed.handoffs ?? [],
      },
      kpi_scores: parsed.kpi_scores ?? {}, overall_score: parsed.overall_score ?? null, model,
    }).select("id, kpi_scores, overall_score, analysis").single();

    await admin.from("sales_recordings").update({ status: "complete", coaching_review_id: review?.id ?? null }).eq("id", rec.id);
    await audit(admin, orgId, act.id, "crm.recording.processed", {
      recording_id: rec.id, review_id: review?.id, overall: parsed.overall_score,
      primary_persona: detected?.primary?.persona_name ?? "system",
      handoff_personas: detected?.secondaries?.map(s => s.persona_name) ?? [],
    });
    return json({ ok: true, transcript_id: transcript?.id, review });
  }

  // ---------- TRANSCRIBE ----------
  if (mode === "transcribe") {
    const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
    if (!openaiKey) return json({ error: "openai_api_key_not_configured" }, 503);
    if (!act.related_recording_id) return json({ error: "no_recording_on_activity" }, 400);
    const { data: rec } = await admin.from("sales_recordings").select("*").eq("id", act.related_recording_id).single();
    if (!rec) return json({ error: "recording_not_found" }, 404);

    await admin.from("sales_recordings").update({ status: "transcribing" }).eq("id", rec.id);
    const { data: fileData, error: dlErr } = await admin.storage.from("crm-media").download(rec.file_path);
    if (dlErr || !fileData) { await fail(admin, rec.id, `download_failed: ${dlErr?.message ?? ""}`); return json({ error: "recording_download_failed" }, 500); }

    const form = new FormData();
    form.append("file", new File([fileData], rec.file_name ?? rec.file_path.split("/").pop() ?? "audio.webm", { type: rec.mime_type ?? "audio/webm" }));
    form.append("model", "whisper-1");
    const resp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST", headers: { Authorization: `Bearer ${openaiKey}` }, body: form,
    });
    if (!resp.ok) { const e = (await resp.text()).slice(0, 300); await fail(admin, rec.id, `transcription_failed: ${e}`); return json({ error: "transcription_failed", detail: e }, 502); }
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
    if (!sourceText) return json({ error: "no_transcript_yet" }, 400);
  } else if (act.related_email_id) {
    const { data: em } = await admin.from("crm_emails").select("subject, body, to_email").eq("id", act.related_email_id).single();
    sourceText = em ? `EMAIL to ${em.to_email ?? "client"}\nSubject: ${em.subject}\n\n${em.body ?? ""}` : "";
  } else {
    sourceText = [act.title, act.summary, JSON.stringify(act.metadata?.body ?? "")].filter(Boolean).join("\n");
  }
  if (sourceText.trim().length < 20) return json({ error: "not_enough_content_to_analyze" }, 400);
  sourceText = sourceText.slice(0, 24000);

  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!anthropicKey) return json({ error: "anthropic_api_key_not_configured" }, 503);

  if (mode === "coach") {
    const [kpis, personas, protocols] = await Promise.all([
      loadOrgKpis(admin, orgId), loadPersonas(admin, orgId), loadProtocols(admin, orgId),
    ]);
    const detected = personas.length > 0 ? detectPersonas(sourceText, personas, protocols) : null;
    const model = pickCoachModel(sourceText);
    const systemPrompt = detected
      ? buildPersonaCoachSystem(detected.primary, detected.secondaries, protocols, kpis, "coach")
      : buildFallbackCoachSystem(kpis);

    const coachResult = await callClaude(anthropicKey, model, systemPrompt, sourceText);
    if ("error" in coachResult) return json({ error: coachResult.error, detail: coachResult.detail }, 502);
    const parsed = coachResult.parsed;

    const { data: review } = await admin.from("ai_coaching_reviews").insert({
      organization_id: orgId, activity_id: act.id, recording_id: act.related_recording_id,
      review_kind: "coaching",
      analysis: {
        strengths: parsed.strengths, improvements: parsed.improvements,
        best_moment: parsed.best_moment, next_actions: parsed.next_actions,
        primary_persona: parsed.primary_persona ?? detected?.primary?.persona_name ?? "system",
        handoffs: parsed.handoffs ?? [],
      },
      kpi_scores: parsed.kpi_scores ?? {}, overall_score: parsed.overall_score ?? null, model,
    }).select("id, kpi_scores, overall_score, analysis").single();
    if (act.related_recording_id) {
      await admin.from("sales_recordings").update({ coaching_review_id: review?.id ?? null }).eq("id", act.related_recording_id);
    }
    await audit(admin, orgId, act.id, "crm.activity.coached", {
      review_id: review?.id, overall: parsed.overall_score,
      primary_persona: detected?.primary?.persona_name ?? "system",
    });
    return json({ ok: true, review });
  } else {
    const model = MODEL_LIGHT;
    const system = `You are the Appliance IQ communication summarizer. Verified-over-hyped voice. Summarize the client communication below for the CRM record. Respond ONLY with JSON, no markdown fences: {"summary":"<3-4 sentence factual summary>","client_intent":"<one line>","open_items":[..max 3..],"sentiment":"positive|neutral|at_risk"}. Only state what the content supports.`;
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model, max_tokens: 1500, system, messages: [{ role: "user", content: sourceText }] }),
    });
    if (!resp.ok) return json({ error: "model_call_failed", detail: (await resp.text()).slice(0, 300) }, 502);
    const data = await resp.json();
    const raw = (data.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
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
