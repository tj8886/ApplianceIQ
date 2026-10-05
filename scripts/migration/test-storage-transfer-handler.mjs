import assert from 'node:assert/strict';
import { createStorageTransferHandler, sha256 } from '../../supabase/functions/consolidation-storage-transfer/handler.ts';
const bytes = new TextEncoder().encode('private fixture');
const capability = 'synthetic-fixture-capability';
const object = { bucket_id: 'fixture', name: 'private.bin', size: bytes.length, mimetype: 'application/octet-stream', cache_control: 'no-cache' };
const bucket = { id: 'fixture', public: false, file_size_limit: 100, allowed_mime_types: null };
let uploads = 0, creates = 0;
const dependencies = {
  async buckets() { return [{ id: 'existing-unrelated', public: true, file_size_limit: null, allowed_mime_types: null }]; },
  async createBucket(b) { assert.equal(b.id, 'fixture'); creates++; return true; },
  async download(o) { assert.equal(o.name, 'private.bin'); return new Blob([bytes]); },
  async upload(o, body) { assert.equal(o.name, 'private.bin'); assert.deepEqual(new Uint8Array(body), bytes); uploads++; return true; },
};
const config = { role: 'source', expiresAt: Date.now() + 60000,
  capabilityHash: await sha256(new TextEncoder().encode(capability)), buckets: [bucket], objects: [object] };
const source = createStorageTransferHandler(config, dependencies);
const destination = createStorageTransferHandler({ ...config, role: 'destination' }, dependencies);
const request = (query, method = 'GET', body, token = capability, checksum) => new Request(`https://fixture.invalid/?${query}`, {
  method, body, headers: { Authorization: `Bearer ${token}`, ...(checksum ? { 'x-content-sha256': checksum } : {}) },
});
assert.equal((await source(request('object=0', 'GET', undefined, 'wrong'))).status, 401);
assert.equal((await source(request('object=99'))).status, 404);
const download = await source(request('object=0'));
assert.equal(download.status, 200);
assert.equal(download.headers.get('cache-control'), 'no-store');
assert.equal(download.headers.get('x-content-sha256'), await sha256(bytes));
assert.deepEqual(new Uint8Array(await download.arrayBuffer()), bytes);
assert.equal((await source(request('object=0', 'PUT', bytes))).status, 405);
assert.equal((await source(request('action=buckets', 'POST'))).status, 400);
assert.equal((await destination(request('action=buckets', 'POST'))).status, 200);
assert.equal(creates, 1);
assert.equal((await destination(request('object=0', 'PUT', bytes, capability, 'wrong'))).status, 409);
assert.equal(uploads, 0);
assert.equal((await destination(request('object=0', 'PUT', bytes, capability, await sha256(bytes)))).status, 200);
assert.equal(uploads, 1);
const expired = createStorageTransferHandler({ ...config, expiresAt: 0 }, dependencies);
assert.equal((await expired(request('object=0'))).status, 410);
console.log('Scoped storage transfer handler checks passed');
