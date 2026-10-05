import { createClient } from 'npm:@supabase/supabase-js@2.117.2';
import { createStorageTransferHandler } from './handler.ts';
import { config } from './transfer-config.ts';
const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  { auth: { persistSession: false, autoRefreshToken: false } });
Deno.serve(createStorageTransferHandler(config, {
  async buckets() { const { data, error } = await client.storage.listBuckets(); return error ? null : data; },
  async createBucket(b) {
    const { error } = await client.storage.createBucket(b.id, { public: b.public,
      fileSizeLimit: b.file_size_limit ?? undefined, allowedMimeTypes: b.allowed_mime_types ?? undefined });
    if (!error) return true;
    return { error: /file size|file_size|size limit|maximum allowed/i.test(error.message)
      ? 'bucket_file_limit_rejected' : 'bucket_validation_failed' };
  },
  async download(o) { const { data, error } = await client.storage.from(o.bucket_id).download(o.name); return error ? null : data; },
  async upload(o, bytes) {
    const { error } = await client.storage.from(o.bucket_id).upload(o.name, bytes, {
      upsert: false, contentType: o.mimetype, headers: { 'cache-control': o.cache_control },
    });
    return !error;
  },
}));
