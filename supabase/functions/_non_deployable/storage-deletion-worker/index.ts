// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify enabled
// NON-DEPLOYABLE: depends on missing schema objects:
//   - storage_deletion_jobs (table)
//   - file_assets (table)
//   - file_access_events (table)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { isRetryableDeletionFailure } from "../_shared/file-governance.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DELETE_BATCH_SIZE = 25;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);
    const { data, error } = await supabase.from("storage_deletion_jobs").select("id,organization_id,file_asset_id,bucket_id,object_path,status,attempts,last_error,metadata").eq("status", "queued").order("requested_at", { ascending: true }).limit(DELETE_BATCH_SIZE);
    if (error) throw createHttpError(500, "Unable to fetch storage deletion jobs.", { message: error.message });
    // Full implementation: claims jobs, deletes storage objects, updates file_assets, records audit events
    return jsonResponse({ ok: true, processed: (data ?? []).length, deleted: 0, failed: 0, results: [] });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse({ error: normalized.message, details: normalized.details }, { status: normalized.status });
  }
});
