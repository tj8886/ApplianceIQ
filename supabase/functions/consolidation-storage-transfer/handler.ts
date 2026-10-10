export type Bucket = { id: string; public: boolean; file_size_limit: number | null; allowed_mime_types: string[] | null };
export type ObjectSpec = { bucket_id: string; name: string; size: number; mimetype: string; cache_control: string };
export type Config = { role: 'source' | 'destination'; expiresAt: number; capabilityHash: string; buckets: Bucket[]; objects: ObjectSpec[] };
export type StorageDependencies = {
  buckets(): Promise<Bucket[] | null>;
  createBucket(bucket: Bucket): Promise<boolean | { error: string }>;
  download(object: ObjectSpec): Promise<Blob | null>;
  upload(object: ObjectSpec, body: ArrayBuffer): Promise<boolean>;
};
export const sha256 = async (body: BufferSource) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', body))]
  .map(b => b.toString(16).padStart(2, '0')).join('');
const json = (status: number, result: unknown) => new Response(JSON.stringify(result), {
  status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
export function createStorageTransferHandler(config: Config, storage: StorageDependencies) {
  return async (request: Request): Promise<Response> => {
    if (!config.capabilityHash || Date.now() >= config.expiresAt) return json(410, { error: 'transfer_closed' });
    const auth = request.headers.get('authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json(401, { error: 'unauthorized' });
    const hash = await sha256(new TextEncoder().encode(auth.slice(7)));
    let difference = hash.length ^ config.capabilityHash.length;
    for (let i = 0; i < hash.length; i++) difference |= hash.charCodeAt(i) ^ config.capabilityHash.charCodeAt(i);
    if (difference) return json(401, { error: 'unauthorized' });
    try {
      const url = new URL(request.url);
      if (request.method === 'POST' && url.searchParams.get('action') === 'buckets' && config.role === 'destination') {
        const existing = await storage.buckets();
        if (!existing) return json(502, { error: 'bucket_inventory_failed' });
        for (const bucket of config.buckets) {
          const found = existing.find(b => b.id === bucket.id);
          if (found) {
            if (found.public !== bucket.public || found.file_size_limit !== bucket.file_size_limit
              || JSON.stringify(found.allowed_mime_types) !== JSON.stringify(bucket.allowed_mime_types)) {
              return json(409, { error: 'bucket_configuration_conflict' });
            }
          } else {
            const created = await storage.createBucket(bucket);
            if (created !== true) return json(502, { error: typeof created === 'object' ? created.error : 'bucket_create_failed' });
          }
        }
        return json(200, { buckets: config.buckets.length });
      }
      const rawIndex = url.searchParams.get('object') ?? '';
      if (!/^\d+$/.test(rawIndex)) return json(400, { error: 'invalid_object' });
      const object = config.objects[Number(rawIndex)];
      if (!object) return json(404, { error: 'object_not_in_manifest' });
      if (request.method === 'GET') {
        const blob = await storage.download(object);
        if (!blob) return json(502, { error: 'object_download_failed' });
        const bytes = await blob.arrayBuffer();
        if (bytes.byteLength !== object.size) return json(409, { error: 'source_size_changed' });
        return new Response(bytes, { headers: { 'Content-Type': 'application/octet-stream',
          'Cache-Control': 'no-store', 'X-Content-SHA256': await sha256(bytes) } });
      }
      if (request.method === 'PUT' && config.role === 'destination') {
        const bytes = await request.arrayBuffer();
        if (bytes.byteLength !== object.size || await sha256(bytes) !== request.headers.get('x-content-sha256')) {
          return json(409, { error: 'object_checksum_mismatch' });
        }
        if (!await storage.upload(object, bytes)) return json(409, { error: 'upload_failed_or_object_exists' });
        return json(200, { uploaded: true });
      }
      return json(405, { error: 'method_not_allowed' });
    } catch { return json(500, { error: 'transfer_failed' }); }
  };
}
