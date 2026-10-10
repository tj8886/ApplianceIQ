// ai-proxy v4 — GPT-5 param support (max_completion_tokens + reasoning_effort), error passthrough, rate limiting
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const COST_MAP: Record<string, { input: number; output: number }> = {
  "claude-sonnet-4-6":    { input: 0.003, output: 0.015 },
  "claude-haiku-4-5":     { input: 0.0008, output: 0.004 },
  "claude-haiku-4-5-20251001": { input: 0.0008, output: 0.004 },
  "gpt-5.6-luna":         { input: 0.0002, output: 0.0012 },
  "gpt-4.1-mini":         { input: 0.0004, output: 0.0016 },
  "gpt-4.1":              { input: 0.002, output: 0.008 },
  "gpt-4.1-nano":         { input: 0.0001, output: 0.0004 },
  "gemini-3.5-flash-lite": { input: 0.00003, output: 0.00025 },
  "gemini-2.5-flash":     { input: 0.00015, output: 0.001 },
  "gemini-2.5-pro":       { input: 0.00125, output: 0.01 },
};

const RATE_LIMITS = { perMinute: 60, perHour: 500 };
const rateBuckets = new Map<string, number[]>();
function checkRateLimit(userId: string): { allowed: boolean; retryAfter?: number } {
  const now = Date.now();
  const key = userId || "anon";
  if (!rateBuckets.has(key)) rateBuckets.set(key, []);
  const ts = rateBuckets.get(key)!;
  const cutoff = now - 3600000;
  while (ts.length && ts[0] < cutoff) ts.shift();
  if (ts.filter(t => t >= now - 60000).length >= RATE_LIMITS.perMinute) return { allowed: false, retryAfter: 60 };
  if (ts.length >= RATE_LIMITS.perHour) return { allowed: false, retryAfter: 3600 };
  ts.push(now);
  return { allowed: true };
}

function detectProvider(model: string): "anthropic" | "openai" | "gemini" {
  if (model.startsWith("claude")) return "anthropic";
  if (model.startsWith("gpt") || model.startsWith("o1") || model.startsWith("o3") || model.startsWith("o4")) return "openai";
  if (model.startsWith("gemini")) return "gemini";
  return "anthropic";
}

function isReasoningModel(model: string): boolean {
  return model.startsWith("gpt-5") || model.startsWith("o1") || model.startsWith("o3") || model.startsWith("o4");
}

function estimateCost(model: string, i: number, o: number): number {
  const r = COST_MAP[model] ?? { input: 0.003, output: 0.015 };
  return (i * r.input + o * r.output) / 1000;
}

async function callAnthropic(apiKey: string, body: any) {
  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify(body),
  });
  const data = await r.json();
  return { data, ok: r.ok, inputTokens: data.usage?.input_tokens ?? 0, outputTokens: data.usage?.output_tokens ?? 0 };
}

async function callOpenAI(apiKey: string, body: any) {
  const messages: any[] = [];
  if (body.system) messages.push({ role: "system", content: body.system });
  for (const m of (body.messages || [])) {
    if (typeof m.content === "string") messages.push({ role: m.role, content: m.content });
    else if (Array.isArray(m.content)) {
      const parts = m.content.map((b: any) => b.type === "text" ? { type: "text", text: b.text } : b.type === "image" ? { type: "image_url", image_url: { url: `data:${b.source.media_type};base64,${b.source.data}` } } : { type: "text", text: JSON.stringify(b) });
      messages.push({ role: m.role, content: parts });
    }
  }
  const req: any = { model: body.model, messages };
  if (isReasoningModel(body.model)) {
    req.max_completion_tokens = Math.max(body.max_tokens ?? 1000, 1000);
    if (body.model.startsWith("gpt-5")) req.reasoning_effort = "none";
  } else {
    req.max_tokens = body.max_tokens ?? 1000;
    if (body.temperature != null) req.temperature = body.temperature;
  }
  const r = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
    body: JSON.stringify(req),
  });
  const data = await r.json();
  if (!r.ok) return { data: { error: data.error?.message ?? JSON.stringify(data).slice(0, 300) }, ok: false, inputTokens: 0, outputTokens: 0 };
  const text = data.choices?.[0]?.message?.content ?? "";
  return { data: { content: [{ type: "text", text }], usage: { input_tokens: data.usage?.prompt_tokens ?? 0, output_tokens: data.usage?.completion_tokens ?? 0 } }, ok: true, inputTokens: data.usage?.prompt_tokens ?? 0, outputTokens: data.usage?.completion_tokens ?? 0 };
}

async function callGemini(apiKey: string, body: any) {
  const contents: any[] = [];
  const systemInstruction = body.system ? { parts: [{ text: body.system }] } : undefined;
  for (const m of (body.messages || [])) {
    const role = m.role === "assistant" ? "model" : "user";
    if (typeof m.content === "string") contents.push({ role, parts: [{ text: m.content }] });
    else if (Array.isArray(m.content)) {
      const parts = m.content.map((b: any) => b.type === "text" ? { text: b.text } : (b.type === "image" || b.type === "document") ? { inline_data: { mime_type: b.source?.media_type ?? "application/octet-stream", data: b.source?.data ?? "" } } : { text: JSON.stringify(b) });
      contents.push({ role, parts });
    }
  }
  const gBody: any = { contents, generationConfig: { maxOutputTokens: body.max_tokens ?? 1000, temperature: body.temperature ?? 0 } };
  if (systemInstruction) gBody.systemInstruction = systemInstruction;
  const model = body.model || "gemini-2.5-flash";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(gBody),
  });
  const data = await r.json();
  if (!r.ok || data.error) return { data: { error: data.error?.message ?? "Gemini error" }, ok: false, inputTokens: 0, outputTokens: 0 };
  const text = data.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("") ?? "";
  const it = data.usageMetadata?.promptTokenCount ?? 0;
  const ot = data.usageMetadata?.candidatesTokenCount ?? 0;
  return { data: { content: [{ type: "text", text }], usage: { input_tokens: it, output_tokens: ot } }, ok: true, inputTokens: it, outputTokens: ot };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Auth required" }, 401);

  const sbUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const sbAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const sbService = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  let userId: string | null = null;
  try { const r = await fetch(`${sbUrl}/auth/v1/user`, { headers: { Authorization: auth, apikey: sbAnon } }); if (r.ok) { const u = await r.json(); userId = u.id ?? null; } } catch {}

  const rate = checkRateLimit(userId ?? "anon");
  if (!rate.allowed) return json({ error: "Rate limit exceeded. Please slow down.", retry_after: rate.retryAfter }, 429);

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const taskType = body._task_type ?? "utility"; delete body._task_type;
  const sourceApp = body._source_app ?? "unknown"; delete body._source_app;

  const model = body.model ?? "claude-sonnet-4-6";
  const provider = detectProvider(model);

  const keys: Record<string, string> = {
    anthropic: Deno.env.get("ANTHROPIC_API_KEY") ?? "",
    openai: Deno.env.get("OPENAI_API_KEY") ?? "",
    gemini: Deno.env.get("GOOGLE_API_KEY") ?? "",
  };

  let activeKey = keys[provider];
  let activeProvider = provider;
  if (!activeKey) {
    const order = provider === "gemini" ? ["openai", "anthropic"] : provider === "openai" ? ["gemini", "anthropic"] : ["openai", "gemini"];
    for (const fb of order) { if (keys[fb]) { activeProvider = fb as any; activeKey = keys[fb]; body.model = fb === "anthropic" ? "claude-sonnet-4-6" : fb === "openai" ? "gpt-5.6-luna" : "gemini-2.5-flash"; break; } }
    if (!activeKey) return json({ error: `No API key configured for ${provider} or any fallback` }, 500);
  }

  const startMs = Date.now();
  try {
    let result;
    switch (activeProvider) {
      case "openai":  result = await callOpenAI(activeKey, body); break;
      case "gemini":  result = await callGemini(activeKey, body); break;
      default:        result = await callAnthropic(activeKey, body); break;
    }

    // Cross-provider failover on provider error (e.g. no credits)
    if (!result.ok) {
      const order = activeProvider === "anthropic" ? ["openai", "gemini"] : activeProvider === "openai" ? ["gemini", "anthropic"] : ["openai", "anthropic"];
      for (const fb of order) {
        if (!keys[fb]) continue;
        const fbBody = { ...body, model: fb === "anthropic" ? "claude-sonnet-4-6" : fb === "openai" ? "gpt-5.6-luna" : "gemini-2.5-flash" };
        const fbResult = fb === "openai" ? await callOpenAI(keys[fb], fbBody) : fb === "gemini" ? await callGemini(keys[fb], fbBody) : await callAnthropic(keys[fb], fbBody);
        if (fbResult.ok) { result = fbResult; activeProvider = fb as any; body.model = fbBody.model; break; }
      }
    }

    const latencyMs = Date.now() - startMs;
    const cost = estimateCost(body.model, result.inputTokens, result.outputTokens);
    try {
      const admin = createClient(sbUrl, sbService);
      await admin.from("ai_audit_events").insert({
        event_type: "proxy_call", user_id: userId, metadata: null,
        event_payload: { task_type: taskType, source_app: sourceApp, provider: activeProvider, model: body.model, input_tokens: result.inputTokens, output_tokens: result.outputTokens, cost_estimate_usd: cost, latency_ms: latencyMs, status: result.ok ? "success" : "error" },
      });
    } catch {}

    return new Response(JSON.stringify(result.data), { status: result.ok ? 200 : 502, headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return json({ error: String(e) }, 502);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
