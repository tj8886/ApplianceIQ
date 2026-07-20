// ai-request-processor — Appliance IQ CRM AI (ported from the Elev8 framework)
// Governance runs in the database first (public.ai_submit_request, as the user);
// this function layers the model call on top and writes results back.

import { createClient } from "jsr:@supabase/supabase-js@2";

// Tiered model routing. Assistants opt into a tier via ai_assistants.config.model_tier
// ('light' | 'standard' | 'heavy'); default is standard. Env overrides per tier.
const MODEL_TIERS: Record<string, string> = {
  light: Deno.env.get("AI_MODEL_LIGHT") ?? "claude-haiku-4-5",
  standard: Deno.env.get("AI_MODEL") ?? "claude-sonnet-4-6",
  heavy: Deno.env.get("AI_MODEL_HEAVY") ?? "claude-opus-4-8",
};
function pickAssistantModel(assistantConfig: unknown): string {
  const tier = String((assistantConfig as Record<string, unknown> | null)?.["model_tier"] ?? "standard");
  return MODEL_TIERS[tier] ?? MODEL_TIERS.standard;
}
const MAX_KNOWLEDGE_CHUNKS = 12;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return json({ error: "authentication_required" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json_body" }, 400);
  }

  const assistantKey = String(body.assistant_key ?? "").trim();
  const prompt = String(body.prompt ?? "").trim();
  const organizationId = body.organization_id ? String(body.organization_id) : null;
  const context = (body.context && typeof body.context === "object") ? body.context as Record<string, unknown> : {};
  const templateKey = body.template_key ? String(body.template_key) : null;
  const maxTokens = Math.min(Number(body.max_tokens ?? 2048) || 2048, 4096);

  if (!assistantKey || prompt.length < 3) {
    return json({ error: "assistant_key_and_prompt_required" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(supabaseUrl, serviceKey);

  // 1. GOVERNANCE (database-side, as the user)
  const { data: gov, error: govErr } = await userClient.rpc("ai_submit_request", {
    p_organization_id: organizationId,
    p_assistant_key: assistantKey,
    p_prompt: prompt,
    p_context: context,
  });

  if (govErr) {
    const msg = govErr.message ?? "governance_rejected";
    const status = /denied|Authentication/i.test(msg) ? 403 : 400;
    return json({ error: "governance_rejected", detail: msg }, status);
  }

  const requestId = gov?.request_id as string;
  const sessionId = gov?.session_id as string;
  const orgId = gov?.organization_id as string;
  const approvalRequired = Boolean(gov?.approval_required);
  const proposedActionId = gov?.proposed_action_id ?? null;

  // 2. MODEL CONTEXT — tenant-aware assistant resolution
  const { data: assistant } = await admin
    .from("ai_assistants")
    .select("assistant_key,label,category,description,retrieval_scopes,safety_controls,response_contract,config,approval_required,organization_id")
    .eq("assistant_key", assistantKey)
    .eq("status", "active")
    .single();

  if (!assistant || (assistant.organization_id && assistant.organization_id !== orgId)) {
    await admin.from("ai_requests").update({ error_message: "assistant_not_available_for_organization" }).eq("id", requestId);
    await admin.from("ai_audit_events").insert({
      organization_id: orgId, request_id: requestId, assistant_key: assistantKey,
      event_type: "ai.assistant.access_denied", event_status: "denied",
      event_payload: { reason: "assistant is scoped to a different organization" },
    });
    return json({ error: "assistant_not_available_for_organization" }, 403);
  }

  // Knowledge brain: org-scoped AND global chunks
  const { data: chunks } = await admin
    .from("ai_knowledge_chunks")
    .select("chunk_key,title,content,citation,organization_id")
    .eq("status", "active")
    .or(`organization_id.eq.${orgId},organization_id.is.null`)
    .limit(120);

  const promptTerms = new Set(prompt.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 3));
  const rankedChunks = (chunks ?? [])
    .map((c) => {
      const text = `${c.title ?? ""} ${c.content ?? ""}`.toLowerCase();
      let score = 0;
      for (const t of promptTerms) if (text.includes(t)) score++;
      return { ...c, score };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_KNOWLEDGE_CHUNKS);

  // Template: tenant-specific first, then platform default
  let template: { system_prompt?: string; user_prompt_template?: string; tone_guidance?: string; output_schema?: unknown } | null = null;
  if (templateKey) {
    const { data: tOrg } = await admin.from("ai_prompt_templates")
      .select("system_prompt,user_prompt_template,tone_guidance,output_schema")
      .eq("template_key", templateKey).eq("status", "active").eq("organization_id", orgId).maybeSingle();
    if (tOrg) template = tOrg;
    else {
      const { data: tGlobal } = await admin.from("ai_prompt_templates")
        .select("system_prompt,user_prompt_template,tone_guidance,output_schema")
        .eq("template_key", templateKey).eq("status", "active").is("organization_id", null).maybeSingle();
      template = tGlobal ?? null;
    }
  }

  const { data: reqRow } = await admin.from("ai_requests").select("grounded_context").eq("id", requestId).single();

  // 3. MODEL CALL
  const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
  if (!anthropicKey) {
    await admin.from("ai_requests").update({
      error_message: "ANTHROPIC_API_KEY edge secret not configured; returned foundation envelope only.",
    }).eq("id", requestId);
    return json({
      request_id: requestId, session_id: sessionId,
      approval_required: approvalRequired, proposed_action_id: proposedActionId,
      error: "anthropic_api_key_not_configured", fallback_output: gov?.output ?? null,
    }, 503);
  }

  const systemPrompt = buildSystemPrompt({
    assistant, template, approvalRequired,
    knowledge: rankedChunks, groundedContext: reqRow?.grounded_context ?? null,
  });

  const chosenModel = pickAssistantModel(assistant?.config);
  const startedAt = Date.now();
  let modelAnswer = "";
  let usage: { input_tokens?: number; output_tokens?: number } = {};
  try {
    const resp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: chosenModel, max_tokens: maxTokens,
        system: systemPrompt,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!resp.ok) {
      const errText = await resp.text();
      throw new Error(`anthropic_${resp.status}: ${errText.slice(0, 300)}`);
    }
    const data = await resp.json();
    modelAnswer = (data.content ?? [])
      .filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text)
      .join("\n");
    usage = data.usage ?? {};
  } catch (e) {
    const errMsg = String(e).slice(0, 500);
    await admin.from("ai_requests").update({ error_message: errMsg }).eq("id", requestId);
    await admin.from("ai_audit_events").insert({
      organization_id: orgId, request_id: requestId, assistant_key: assistantKey,
      event_type: "ai.model.call_failed", event_status: "error",
      event_payload: { error: errMsg, model: chosenModel },
    });
    return json({
      request_id: requestId, session_id: sessionId,
      approval_required: approvalRequired, proposed_action_id: proposedActionId,
      error: "model_call_failed", detail: errMsg, fallback_output: gov?.output ?? null,
    }, 502);
  }
  const latencyMs = Date.now() - startedAt;
  const totalTokens = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0);

  // 4. BOOKKEEPING
  const modelOutput = {
    mode: "model", assistant_key: assistantKey, answer: modelAnswer,
    model: { provider: "anthropic", name: chosenModel, latency_ms: latencyMs },
    usage,
    knowledge_citations: rankedChunks.filter((c) => c.score > 0)
      .map((c) => ({ chunk_key: c.chunk_key, title: c.title, citation: c.citation })),
    human_governance: {
      approval_required: approvalRequired,
      may_execute_without_approval: false,
      not_system_of_record: true,
    },
  };

  await admin.from("ai_requests").update({
    output: modelOutput,
    explanation: "Model response generated over the Appliance IQ governance envelope. Grounded in tenant-scoped context and knowledge. No operational records were modified.",
    model_provider: "anthropic", model_name: chosenModel,
    token_estimate: totalTokens > 0 ? totalTokens : undefined,
    completed_at: new Date().toISOString(),
  }).eq("id", requestId);

  await admin.from("ai_audit_events").insert({
    organization_id: orgId, request_id: requestId, assistant_key: assistantKey,
    event_type: "ai.model.response_generated", event_status: "recorded",
    event_payload: {
      model: chosenModel, latency_ms: latencyMs,
      input_tokens: usage.input_tokens ?? 0, output_tokens: usage.output_tokens ?? 0,
      knowledge_chunks_used: rankedChunks.filter((c) => c.score > 0).length,
      template_key: templateKey,
    },
  });

  if (totalTokens > 0) {
    await admin.from("ai_usage_meter").insert({
      organization_id: orgId, assistant_key: assistantKey, request_id: requestId,
      usage_kind: "token", quantity: totalTokens, limit_key: "ai.tokens.monthly",
      metadata: { source: "anthropic_actual", input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0 },
    });
  }

  return json({
    request_id: requestId, session_id: sessionId, organization_id: orgId,
    assistant_key: assistantKey, approval_required: approvalRequired,
    proposed_action_id: proposedActionId, answer: modelAnswer,
    model: chosenModel, usage, knowledge_citations: modelOutput.knowledge_citations,
  });
});

function buildSystemPrompt(args: {
  assistant: Record<string, unknown> | null;
  template: { system_prompt?: string; user_prompt_template?: string; tone_guidance?: string; output_schema?: unknown } | null;
  approvalRequired: boolean;
  knowledge: Array<{ title?: string; content?: string; citation?: unknown; chunk_key?: string; score: number }>;
  groundedContext: unknown;
}): string {
  const a = args.assistant ?? {};
  const parts: string[] = [];

  parts.push(`You are the ${a["label"] ?? "AI Assistant"}, part of the Appliance IQ CRM AI platform for appliance and specialty retail.`);
  if (a["description"]) parts.push(String(a["description"]));

  const methodology = (a["config"] as Record<string, unknown> | null)?.["methodology"];

  parts.push([
    "GOVERNANCE RULES (non-negotiable):",
    "- You are advisory only. You never execute actions, modify records, send messages, or commit anyone to anything.",
    args.approvalRequired
      ? "- Consequential recommendations are routed to the human approval queue. State clearly that they await human approval."
      : "- This assistant is configured for advisory analysis only.",
    "- Ground answers in the provided tenant context and knowledge base. Never fabricate prices, specs, stock positions, review scores, or records — if the context does not contain it, say so plainly.",
    "- Respect tenant scope: never reference or infer data from other organizations.",
    "- Brand voice: verified over hyped. The price is real — we checked. Evidence before claims; honest trade-offs build trust.",
    methodology
      ? `- House methodology for this assistant: ${JSON.stringify(methodology)}`
      : "- Default standards: evidence-first spec-by-spec selling; ACRA objection handling (Acknowledge, Clarify, Respond, Advance).",
  ].join("\n"));

  if (args.template?.system_prompt) parts.push(`TEMPLATE INSTRUCTIONS:\n${args.template.system_prompt}`);
  if (args.template?.tone_guidance) parts.push(`TONE:\n${args.template.tone_guidance}`);
  if (args.template?.output_schema) parts.push(`OUTPUT SCHEMA (follow strictly):\n${JSON.stringify(args.template.output_schema)}`);

  const rc = a["response_contract"];
  if (rc && Object.keys(rc as object).length > 0) parts.push(`RESPONSE CONTRACT:\n${JSON.stringify(rc)}`);
  const sc = a["safety_controls"];
  if (sc && Object.keys(sc as object).length > 0) parts.push(`SAFETY CONTROLS IN EFFECT:\n${JSON.stringify(sc)}`);

  const relevant = args.knowledge.filter((c) => c.score > 0);
  if (relevant.length > 0) {
    parts.push("AUTHORITATIVE KNOWLEDGE BASE (cite by [chunk_key] when used):\n" +
      relevant.map((c) => `[${c.chunk_key}] ${c.title ?? ""}\n${(c.content ?? "").slice(0, 2000)}`).join("\n---\n"));
  }

  if (args.groundedContext) {
    parts.push(`TENANT CONTEXT SNAPSHOT (permission-checked record counts):\n${JSON.stringify(args.groundedContext).slice(0, 4000)}`);
  }

  return parts.join("\n\n");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
