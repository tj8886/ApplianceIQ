import assert from 'node:assert/strict';
import { createHandoffHandler } from '../../supabase/functions/platform-handoff/handler.ts';

let issues = 0, links = 0;
const tickets = new Map();
const handler = createHandoffHandler({
  async authenticatedUser(token) { return token === 'fixture-session' ? 'fixture-user' : null; },
  async issue(userId, hash, module, context) {
    issues++;
    if (context.organization_id === '00000000-0000-0000-0000-000000000000') return false;
    tickets.set(hash, { module, user_id: userId, context });
    return true;
  },
  async consume(hash, module) {
    const t = tickets.get(hash);
    if (!t || t.module !== module) return null;
    tickets.delete(hash);
    return t;
  },
  async sessionLink() { links++; return 'synthetic-token-hash'; },
});
const request = (body, token) => new Request('https://fixture.invalid', {
  method: 'POST', headers: token ? { Authorization: `Bearer ${token}` } : {}, body: JSON.stringify(body),
});
assert.equal((await handler(new Request('https://fixture.invalid', { method: 'OPTIONS' }))).status, 200);
assert.equal((await handler(new Request('https://fixture.invalid'))).status, 405);
assert.equal((await handler(request({ action: 'issue', target_module_key: 'crm' }))).status, 401);
assert.equal((await handler(request({ action: 'issue', target_module_key: 'crm' }, 'invalid'))).status, 401);
assert.equal(issues, 0);
assert.equal((await handler(request(null))).status, 400);
assert.equal((await handler(request({ action: 'issue', target_module_key: 'crm', organization_id: 'bad' }, 'fixture-session'))).status, 400);
assert.equal((await handler(request({ action: 'issue', target_module_key: 'crm', organization_id: '00000000-0000-0000-0000-000000000000' }, 'fixture-session'))).status, 403);
const issued = await handler(request({ action: 'issue', target_module_key: 'crm' }, 'fixture-session'));
assert.equal(issued.status, 200);
assert.equal(issued.headers.get('cache-control'), 'no-store');
const { ticket } = await issued.json();
assert.match(ticket, /^[0-9a-f]{64}$/);
assert.equal((await handler(request({ action: 'redeem', ticket, target_module_key: 'academy' }))).status, 401);
assert.equal(links, 0);
const redeemed = await handler(request({ action: 'redeem', ticket, target_module_key: 'crm' }));
assert.equal(redeemed.status, 200);
assert.equal((await redeemed.json()).token_hash, 'synthetic-token-hash');
assert.equal((await handler(request({ action: 'redeem', ticket, target_module_key: 'crm' }))).status, 401);
assert.equal(links, 1);
const failing = createHandoffHandler({ async authenticatedUser() { throw Error('private credential detail'); } });
const failure = await failing(request({ action: 'issue', target_module_key: 'crm' }, 'fixture-session'));
assert.equal(failure.status, 500);
assert.deepEqual(await failure.json(), { error: 'handoff_failed' });
console.log('Handoff HTTP handler checks passed');
