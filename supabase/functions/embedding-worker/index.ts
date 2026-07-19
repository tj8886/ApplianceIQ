// embedding-worker — Appliance IQ (ported from the Elev8 framework)
// Embeds ai_knowledge_chunks and products via the DB work-queue contract:
//   start_embedding_worker_run / list_pending_embeddings / write_embedding / complete_embedding_worker_run
// Provider: VOYAGE_API_KEY (voyage-3.5) or OPENAI_API_KEY (text-embedding-3-small, dims=1024).
// Service-role only.

import { createClient } from "jsr:@supabase/supabase-js@2";

const BATCH_SIZE = 50;
const MAX_CHARS_PER_TEXT = 8000;

function isServiceRole(authHeader: string, envServiceKey: string): boolean {
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return false;
  if (envServiceKey && token === envServiceKey) return true;
  if (token.startsWith("sb_secret_")) return true;
  const parts = token.split(".");
  if (parts.length === 3) {
    try {
      const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
      return payload?.role === "service_role";
    } catch { return false; }
  }
  return false;
}

async function embedVoyage(texts: string[], apiKey: string, model: string): Promise<number[][]> {
  const resp = await fetch("https://api.voyageai.com/v1/embeddings", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, input: texts, input_type: "document", output_dimension: 1024 }),
  });
  if (!resp.ok) throw new Error(`voyage_${resp.status}: ${(await resp.text()).slice(0, 300)}`);
  const data = await resp.json();
  return data.data.sort((a: {index:number}, b: {index:number}) => a.index - b.index)
    .map((d: {embedding:number[]}) => d.embedding);
}

async function embedOpenAI(texts: string[], apiKey: string, model: string): Promise<number[][]> {
  const resp = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model, input: texts, dimensions: 1024 }),
  });
  if (!resp.ok) throw new Error(`openai_${resp.status}: ${(await resp.text()).slice(0, 300)}`);
  const data = await resp.json();
  return data.data.sort((a: {index:number}, b: {index:number}) => a.index - b.index)
    .map((d: {embedding:number[]}) => d.embedding);
}

Deno.serve(async (req: Request) => {
  const authHeader = req.headers.get("Authorization") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!isServiceRole(authHeader, serviceKey)) {
    return json({ error: "service_role_required" }, 403);
  }

  const voyageKey = Deno.env.get("VOYAGE_API_KEY") ?? "";
  const openaiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  let provider: "voyage" | "openai" | null = null;
  let model = "";
  if (voyageKey) { provider = "voyage"; model = Deno.env.get("EMBEDDING_MODEL") ?? "voyage-3.5"; }
  else if (openaiKey) { provider = "openai"; model = Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-small"; }
  if (!provider) {
    return json({ error: "embedding_provider_not_configured", detail: "Set VOYAGE_API_KEY or OPENAI_API_KEY edge secret." }, 503);
  }

  const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", serviceKey);

  const { data: runId, error: runErr } = await admin.rpc("start_embedding_worker_run", {
    p_batch_requested: BATCH_SIZE, p_triggered_by: "edge_worker",
  });
  if (runErr) return json({ error: `start_run_failed: ${runErr.message}` }, 500);

  let embedded = 0;
  let failed = 0;

  try {
    const { data: pending, error: listErr } = await admin.rpc("list_pending_embeddings", {
      p_batch_size: BATCH_SIZE,
    });
    if (listErr) throw new Error(`list_failed: ${listErr.message}`);

    if (!pending || pending.length === 0) {
      await admin.rpc("complete_embedding_worker_run", {
        p_run_id: runId, p_status: "completed", p_rows_embedded: 0, p_rows_failed: 0,
        p_model: `${provider}:${model}`, p_error_message: null, p_metadata: { note: "no pending rows" },
      });
      return json({ run_id: runId, provider, model, embedded: 0, failed: 0, pending: 0 });
    }

    const texts = pending.map((r: { source_text: string }) =>
      (r.source_text ?? "").slice(0, MAX_CHARS_PER_TEXT) || "(empty)");
    const vectors = provider === "voyage"
      ? await embedVoyage(texts, voyageKey, model)
      : await embedOpenAI(texts, openaiKey, model);

    if (vectors.length !== pending.length) {
      throw new Error(`provider returned ${vectors.length} vectors for ${pending.length} inputs`);
    }

    for (let i = 0; i < pending.length; i++) {
      const row = pending[i];
      const vec = vectors[i];
      if (!vec || vec.length !== 1024) { failed++; continue; }
      const { data: ok, error: writeErr } = await admin.rpc("write_embedding", {
        p_table_name: row.table_name,
        p_row_id: row.row_id,
        p_embedding: `[${vec.join(",")}]`,
        p_model: `${provider}:${model}`,
        p_source_hash: row.source_hash,
      });
      if (writeErr || ok === false) failed++;
      else embedded++;
    }

    await admin.rpc("complete_embedding_worker_run", {
      p_run_id: runId,
      p_status: failed === 0 ? "completed" : "completed_with_errors",
      p_rows_embedded: embedded, p_rows_failed: failed,
      p_model: `${provider}:${model}`, p_error_message: null,
      p_metadata: { batch: pending.length },
    });

    return json({ run_id: runId, provider, model, embedded, failed, batch: pending.length });
  } catch (e) {
    const errorMessage = String(e).slice(0, 500);
    await admin.rpc("complete_embedding_worker_run", {
      p_run_id: runId, p_status: "failed",
      p_rows_embedded: embedded, p_rows_failed: failed,
      p_model: `${provider}:${model}`, p_error_message: errorMessage, p_metadata: {},
    });
    return json({ run_id: runId, error: errorMessage, embedded, failed }, 502);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
