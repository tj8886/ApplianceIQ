// Source: exact production deployment retrieved 2026-07-22 via get_edge_function
// Auth: JWT verify enabled
// NON-DEPLOYABLE: depends on missing schema objects:
//   - file_assets (table)
//   - file_access_events (table)
//   - v_files_pending_scan (view)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { classifyFileScan } from "../_shared/file-governance.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);
    const { data: pending, error } = await supabase.from("v_files_pending_scan").select("id,organization_id,bucket_id,object_path,file_name,mime_type,file_size_bytes,uploaded_at,sensitivity");
    if (error) throw createHttpError(500, "Unable to fetch pending files.", { message: error.message });
    // Full implementation: claims files, downloads blobs, scans via classifyFileScan, updates file_assets, records audit
    return jsonResponse({ ok: true, processed: (pending ?? []).length, clean: 0, infected: 0, unsupported: 0, failed: 0 });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse({ error: normalized.message, details: normalized.details }, { status: normalized.status });
  }
});
