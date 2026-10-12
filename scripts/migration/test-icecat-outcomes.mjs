import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { stripTypeScriptTypes } from 'node:module';
const source = fs.readFileSync(new URL('../../supabase/functions/enrich-icecat/index.ts', import.meta.url), 'utf8');
const code = stripTypeScriptTypes(source).replace(/^import .*$/gm, '');
for (const scenario of ['not_found','provider_error','write_error','target_missing','pending_error','batch_provider_error']) {
  let handler;
  const logged = [];
  const p = { id:'fixture', brand_name:'Brand', model_number:'MODEL123' };
  const client = { from: () => {
    const query = {
      select: () => query, eq: () => query, or: () => query, order: () => query,
      single: async () => ({ data: scenario === 'target_missing' ? null : p }),
      limit: async () => ({ data:[p], error: scenario === 'pending_error' ? {message:'fixture database failure'} : null }),
      update: () => ({ eq: async () => ({ error: scenario === 'write_error' ? {message:'fixture write failure'} : null }) }),
    };
    return query;
  }};
  vm.runInNewContext(code, {
    Request, Response, URL, URLSearchParams, AbortSignal, console, setTimeout: fn => { fn(); },
    Deno:{env:{get: () => 'fixture'},serve: fn => {handler=fn;}},
    createClient: () => client,
    requireJobAuth: async () => ({ok:true}),
    beginInvocation: () => ({}),
    finishInvocation: async (_c,_i,outcome,detail) => logged.push({outcome,detail}),
    fetch: async () => Response.json({message:'fixture'}, {status: scenario.includes('provider_error') ? 503 : 404}),
  });
  const batch = scenario === 'pending_error' || scenario === 'batch_provider_error';
  const response = await handler(new Request('https://example.test', {method:'POST',body:JSON.stringify(batch ? {batch_size:1} : {product_id:p.id})}));
  const row = logged.at(-1);
  assert.ok(row, scenario);
  assert.equal(row.outcome, scenario === 'not_found' ? 'completed' : 'failed', scenario);
  if (scenario === 'not_found') assert.equal(row.detail.not_found,1);
  if (scenario.includes('provider_error') || scenario === 'write_error') assert.equal(row.detail.errors,1);
  if (scenario === 'pending_error') assert.equal(response.status,503);
  if (scenario === 'target_missing') assert.equal(response.status,404);
  assert.equal(JSON.stringify(row).includes('fixture write failure'),false);
}
console.log('Icecat outcomes passed: actual not-found completion, provider/database failures, targeted completion and pending-query failure.');
