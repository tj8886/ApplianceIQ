// Temporary, bounded Canada -> US East append relay. No caller-supplied URLs or credentials.
export type DeltaConfig = { role: "export" | "import"; tokenHash: string; expiresAt: string };
const tables = new Set(["phase7_action_audit", "phase7_automation_policies"]);
export function createDeltaHandler(config: DeltaConfig, env: (key: string) => string | undefined, request = fetch) {
  return async (req: Request): Promise<Response> => {
    const reply = (status: number, value: unknown) => new Response(JSON.stringify(value), {status, headers: {"content-type": "application/json", "cache-control": "no-store"}});
    if (!config.tokenHash || Date.now() >= Date.parse(config.expiresAt) || !Number.isFinite(Date.parse(config.expiresAt))) return reply(410, {error: "transfer_closed"});
    const bearer = req.headers.get("authorization")?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    if (!bearer) return reply(401, {error: "unauthorized"});
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(bearer)))).map(x=>x.toString(16).padStart(2,"0")).join("");
    if (digest !== config.tokenHash) return reply(401, {error: "unauthorized"});
    if (req.method !== "POST") return reply(405, {error: "post_required"});
    const raw = await req.text();
    if (raw.length > 2_000_000) return reply(413, {error: "batch_too_large"});
    let input: Record<string, unknown>;
    try {input = JSON.parse(raw);} catch {return reply(400, {error: "invalid_json"});}
    if (!input || typeof input !== "object" || Array.isArray(input)) return reply(400, {error: "invalid_object"});
    const table = input.p_table;
    if (typeof table !== "string" || !tables.has(table)) return reply(400, {error: "table_not_allowed"});
    const service = env("SUPABASE_SERVICE_ROLE_KEY");
    const base = env("SUPABASE_URL");
    if (!service || !base) return reply(503, {error: "runtime_unavailable"});
    const expected = config.role === "export" ? "https://fumwwhyozeouoqscolke.supabase.co" : "https://jdxslqmgjsuzoisuhvlc.supabase.co";
    if (base.replace(/\/$/, "") !== expected) return reply(503, {error: "wrong_project"});
    const internal = {authorization: `Bearer ${service}`, apikey: service, "content-type": "application/json"};
    if (config.role === "import") {
      if (!Array.isArray(input.p_rows) || input.p_rows.length > 500) return reply(400, {error: "invalid_rows"});
      // Forward the original JSON text: JSON.parse/stringify would round arbitrary precision values.
      const result = await request(`${expected}/rest/v1/rpc/aiq_apply_delta_batch`, {method: "POST",headers: internal,body: raw,redirect: "error",signal: AbortSignal.timeout(45000)});
      if (!result.ok) return reply(409, {error: "database_rejected_batch",status: result.status});
      return new Response(await result.text(), {headers: {"content-type": "application/json", "cache-control": "no-store"}});
    }
    const cursor = input.cursor;
    if (cursor !== null && cursor !== undefined && (typeof cursor !== "string" || !(table === "phase7_action_audit" ? /^\d{1,9}$/ : /^[0-9a-f-]{36}$/).test(cursor))) return reply(400, {error: "invalid_cursor"});
    const url = new URL(`${expected}/rest/v1/${table}`);
    url.searchParams.set("select", "*"); url.searchParams.set("order", "id.asc"); url.searchParams.set("limit", "500");
    if (table === "phase7_action_audit") {
      url.searchParams.set("and", `(id.gt.${cursor ?? "252802"},id.lte.275452)`);
    } else {
      url.searchParams.set("and", "(created_at.gt.2026-10-04T18:45:00.236213Z,created_at.lte.2026-10-09T12:00:00.185084Z)");
      if (cursor) url.searchParams.set("id", `gt.${cursor}`);
    }
    const result = await request(url, {headers: internal,redirect: "error",signal: AbortSignal.timeout(45000)});
    if (!result.ok) return reply(502, {error: "source_read_failed",status: result.status});
    const rowsText = await result.text();
    if (rowsText.length > 1_900_000) return reply(413, {error: "source_batch_too_large"});
    const rows = JSON.parse(rowsText);
    if (!Array.isArray(rows) || rows.length > 500) return reply(502, {error: "invalid_source_response"});
    if (!rows.length) return reply(200, {count: 0, cursor: cursor ?? null});
    const forwarded = await request("https://jdxslqmgjsuzoisuhvlc.supabase.co/functions/v1/migration-delta-import", {method: "POST", headers: {authorization: `Bearer ${bearer}`, "content-type": "application/json"},body: `{"p_table":${JSON.stringify(table)},"p_rows":${rowsText}}`,redirect: "error",signal: AbortSignal.timeout(60000)});
    if (!forwarded.ok) return reply(409, {error: "destination_rejected_batch",status: forwarded.status});
    const stats = await forwarded.json();
    return reply(200, {count: rows.length, cursor: String(rows.at(-1).id), stats});
  };
}
