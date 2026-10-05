type Context = Record<string, unknown>;
type Consumed = { user_id: string; context: Context };
export type HandoffDependencies = {
  authenticatedUser(token: string): Promise<string | null>;
  issue(userId: string, ticketHash: string, targetModule: string, context: Context): Promise<boolean>;
  consume(ticketHash: string, targetModule: string): Promise<Consumed | null>;
  sessionLink(userId: string): Promise<string | null>;
};
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};
const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: cors });
const sha = async (input: string) => {
  const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(hash)].map(x => x.toString(16).padStart(2, '0')).join('');
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createHandoffHandler(deps: HandoffDependencies) {
  return async (req: Request): Promise<Response> => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
    if (req.method !== 'POST') return json(405, { error: 'method_not_allowed' });
    try {
      const text = await req.text();
      if (new TextEncoder().encode(text).length > 16384) return json(413, { error: 'request_too_large' });
      let body: Record<string, unknown>;
      try { body = JSON.parse(text); } catch { return json(400, { error: 'invalid_json' }); }
      if (!body || typeof body !== 'object' || Array.isArray(body)) return json(400, { error: 'invalid_json' });
      if (body.action !== 'issue' && body.action !== 'redeem') return json(400, { error: 'unknown_action' });
      if (typeof body.target_module_key !== 'string' || !/^[a-z0-9_-]{1,80}$/.test(body.target_module_key)) {
        return json(400, { error: 'invalid_target_module' });
      }
      if (body.action === 'issue') {
        const auth = req.headers.get('authorization') ?? '';
        if (!/^bearer .+/i.test(auth)) return json(401, { error: 'missing_authorization' });
        const userId = await deps.authenticatedUser(auth.slice(7));
        if (!userId) return json(401, { error: 'invalid_session' });
        const context: Context = {};
        for (const key of ['organization_id', 'location_id']) {
          const value = body[key];
          if (value != null && value !== '' && (typeof value !== 'string' || !uuid.test(value))) {
            return json(400, { error: 'invalid_context' });
          }
          context[key] = value || null;
        }
        for (const key of ['entity_type', 'entity_id', 'entity_label', 'source_module_key']) {
          if (body[key] != null && (typeof body[key] !== 'string' || (body[key] as string).length > 2000)) {
            return json(400, { error: 'invalid_context' });
          }
          context[key] = body[key] || null;
        }
        context.source_module_key ||= 'platform';
        const random = crypto.getRandomValues(new Uint8Array(32));
        const ticket = [...random].map(x => x.toString(16).padStart(2, '0')).join('');
        if (!await deps.issue(userId, await sha(ticket), body.target_module_key, context)) {
          return json(403, { error: 'handoff_access_denied' });
        }
        return json(200, { ticket, expires_in: 120 });
      }
      if (typeof body.ticket !== 'string' || !/^[0-9a-f]{64}$/.test(body.ticket)) {
        return json(400, { error: 'invalid_ticket' });
      }
      const row = await deps.consume(await sha(body.ticket), body.target_module_key);
      if (!row?.user_id) return json(401, { error: 'ticket_invalid_or_expired' });
      const tokenHash = await deps.sessionLink(row.user_id);
      if (!tokenHash) return json(500, { error: 'session_handoff_failed' });
      return json(200, { token_hash: tokenHash, type: 'magiclink', context: row.context });
    } catch {
      // Do not leak credentials, SQL details or account information in responses/logs.
      return json(500, { error: 'handoff_failed' });
    }
  };
}
