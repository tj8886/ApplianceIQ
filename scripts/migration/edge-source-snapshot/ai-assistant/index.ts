import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json = Record<string, any>;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply({ error: "authentication_required" }, 401);

  let body: Json;
  try { body = await req.json(); } catch { return reply({ error: "invalid_json" }, 400); }

  const message = String(body.message ?? "").trim();
  if (!message) return reply({ error: "message_required" }, 400);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const userRes = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: auth, apikey: anon },
  });
  if (!userRes.ok) return reply({ error: "invalid_session" }, 401);
  const user = await userRes.json();

  const organizationId = body.organization_id ? String(body.organization_id) : null;
  let conversationId = body.conversation_id ? String(body.conversation_id) : null;

  if (!conversationId) {
    const filters = [
      `user_id=eq.${encodeURIComponent(user.id)}`,
      `status=eq.active`,
      `select=id,last_message_at,updated_at`,
      `order=last_message_at.desc.nullslast,updated_at.desc`,
      `limit=1`,
    ];
    if (organizationId) filters.splice(1, 0, `organization_id=eq.${encodeURIComponent(organizationId)}`);
    const rows = await rest(url, service, `ai_conversations?${filters.join("&")}`);
    conversationId = rows?.[0]?.id ?? null;
  }

  const payload = {
    organization_id: organizationId,
    assistant_id: body.assistant_id ?? null,
    message,
    history: Array.isArray(body.history) ? body.history : [],
    conversation_id: conversationId,
    mode: "auto",
    country: String(body.country ?? "CA").toUpperCase(),
    retailer_name: body.retailer_name ?? null,
    crm_record_type: body.crm_record_type ?? null,
    crm_record_id: body.crm_record_id ?? null,
    title: body.title ?? null,
  };

  const routerRes = await fetch(`${url}/functions/v1/ai-intelligence-router`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: auth,
      apikey: anon,
    },
    body: JSON.stringify(payload),
  });

  const data = await routerRes.json().catch(() => ({}));
  if (!routerRes.ok) {
    return reply({
      error: "intelligence_router_failed",
      detail: data.detail ?? data.error ?? routerRes.status,
      conversation_id: conversationId,
    }, routerRes.status >= 400 && routerRes.status < 600 ? routerRes.status : 502);
  }

  return reply({
    ok: true,
    engine: "applianceiq-ai-assistant-v2",
    answer: data.answer ?? data.response ?? "",
    response: data.answer ?? data.response ?? "",
    conversation_id: data.conversation_id ?? conversationId,
    primary_persona: data.primary_persona ?? null,
    routed_personas: data.routed_personas ?? [],
    memory: data.memory ?? null,
    recommendation_scoring_used: data.recommendation_scoring_used ?? false,
    recommendation_scoring: data.recommendation_scoring ?? null,
    specialists: data.specialists ?? [],
  });
});

async function rest(url: string, key: string, path: string) {
  const r = await fetch(`${url}/rest/v1/${path}`, {
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
  });
  const text = await r.text();
  if (!r.ok) throw new Error(`REST ${r.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
