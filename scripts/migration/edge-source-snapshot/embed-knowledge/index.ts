// embed-knowledge v4 — gemini-embedding-001 @ 1024 dims (matches existing vector(1024) column)
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const EMBED_MODEL = "gemini-embedding-001";
const DIMS = 1024;

async function embed(apiKey: string, texts: string[]): Promise<number[][]> {
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${EMBED_MODEL}:batchEmbedContents?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ requests: texts.map(t => ({ model: `models/${EMBED_MODEL}`, content: { parts: [{ text: t.slice(0, 7000) }] }, outputDimensionality: DIMS })) }),
  });
  if (!r.ok) throw new Error(`Gemini ${r.status}: ${(await r.text()).slice(0, 400)}`);
  const d = await r.json();
  return (d.embeddings ?? []).map((e: any) => e.values);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const apiKey = Deno.env.get("GOOGLE_API_KEY") ?? "";
    if (!apiKey) return json({ error: "GOOGLE_API_KEY not configured in Edge Function Secrets" });

    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    let body: any = {}; try { body = await req.json(); } catch {}

    if (body.mode === "query") {
      const text = String(body.text ?? "").trim();
      if (!text) return json({ error: "text required" });
      const [vec] = await embed(apiKey, [text]);
      return json({ embedding: vec });
    }

    const batchSize = Math.min(Number(body.batch_size ?? 50), 100);
    const { data: chunks, error } = await sb.from("ai_knowledge_chunks").select("id, chunk_key, title, content").eq("status", "active").is("embedding", null).limit(batchSize);
    if (error) return json({ error: error.message });
    if (!chunks?.length) {
      const { count } = await sb.from("ai_knowledge_chunks").select("id", { count: "exact", head: true }).eq("status", "active").is("embedding", null);
      return json({ done: true, embedded_this_run: 0, remaining: count ?? 0 });
    }

    const texts = chunks.map((c: any) => `${c.title ?? ""}\n${c.content ?? ""}`);
    const vectors = await embed(apiKey, texts);

    let ok = 0; let firstErr = "";
    for (let i = 0; i < chunks.length; i++) {
      if (!vectors[i]) continue;
      const { error: upErr } = await sb.from("ai_knowledge_chunks").update({ embedding: JSON.stringify(vectors[i]), embedded_at: new Date().toISOString() }).eq("id", chunks[i].id);
      if (!upErr) ok++; else if (!firstErr) firstErr = upErr.message;
    }

    const { count } = await sb.from("ai_knowledge_chunks").select("id", { count: "exact", head: true }).eq("status", "active").is("embedding", null);
    const resp: any = { done: (count ?? 0) === 0, embedded_this_run: ok, remaining: count ?? 0 };
    if (firstErr) resp.write_error = firstErr;
    return json(resp);
  } catch (e: any) {
    return json({ error: String(e?.message ?? e).slice(0, 500) });
  }
});

function json(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } }); }
