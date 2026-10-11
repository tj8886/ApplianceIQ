import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';

const source = fs.readFileSync(new URL('../../supabase/functions/enrich-icecat/index.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source).replace(/^import .*$/gm, '');
for (const configured of [false, true]) {
  let handler;
  const logged = [];
  let queries = 0;
  const context = {
    Request, Response, console,
    Deno: { env: { get: key => key === 'ICECAT_USERNAME' && configured ? 'fixture-user' : undefined }, serve: fn => { handler = fn; } },
    createClient: () => ({ from: () => { queries++; throw Error('unexpected query'); } }),
    requireJobAuth: async req => req.headers.get('x-ingest-secret') === 'fixture-secret' ? { ok: true } : Response.json({ error: 'unauthorized' }, { status: 401 }),
    beginInvocation: () => ({}), finishInvocation: async (_client, _inv, outcome, detail) => logged.push({ outcome, detail }),
    fetch: () => { throw Error('unexpected vendor request'); },
  };
  vm.runInNewContext(code, context);
  const probe = () => new Request('https://example.test/functions/v1/enrich-icecat', { method: 'POST', headers: { 'x-ingest-secret': 'fixture-secret' }, body: JSON.stringify({ status_only: true }) });
  const response = await handler(probe());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { configured, pim_first: true });
  assert.equal(queries, 0);
  assert.equal(logged.at(-1).detail.readiness_only, true);
  const denied = await handler(new Request('https://example.test', { method: 'POST', body: '{}' }));
  assert.equal(denied.status, 401);
  if (!configured) {
    const missing = await handler(new Request('https://example.test', { method: 'POST', headers: { 'x-ingest-secret': 'fixture-secret' }, body: '{}' }));
    assert.equal(missing.status, 503);
    assert.equal(logged.at(-1).outcome, 'failed');
    assert.equal(queries, 0);
  }
}
console.log('Icecat readiness: configured/missing, no vendor calls, denial and failure logging passed.');
