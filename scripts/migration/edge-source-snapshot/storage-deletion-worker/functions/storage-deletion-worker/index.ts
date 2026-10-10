import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { isRetryableDeletionFailure, normalizeStorageDeletionStatus } from "../_shared/file-governance.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const DELETE_BATCH_SIZE = 25;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

type DeletionJob = {
  id: string;
  organization_id: string;
  file_asset_id: string;
  bucket_id: string;
  object_path: string;
  status: string;
  attempts: number;
  last_error: string | null;
  metadata: Record<string, unknown> | null;
};

async function claimJobs() {
  const { data, error } = await supabase
    .from("storage_deletion_jobs")
    .select("id,organization_id,file_asset_id,bucket_id,object_path,status,attempts,last_error,metadata")
    .eq("status", "queued")
    .order("requested_at", { ascending: true })
    .limit(DELETE_BATCH_SIZE);

  if (error) {
    throw createHttpError(500, "Unable to fetch storage deletion jobs.", { message: error.message });
  }

  const jobs = (data ?? []) as DeletionJob[];
  const claimed: DeletionJob[] = [];

  for (const job of jobs) {
    const { data: updated, error: claimError } = await supabase
      .from("storage_deletion_jobs")
      .update({
        status: "deleting",
        attempts: (job.attempts ?? 0) + 1,
        claimed_at: new Date().toISOString(),
        last_error: null
      })
      .eq("id", job.id)
      .eq("status", "queued")
      .select("id,organization_id,file_asset_id,bucket_id,object_path,status,attempts,last_error,metadata")
      .maybeSingle();

    if (claimError || !updated) {
      continue;
    }

    claimed.push(updated as DeletionJob);
  }

  return claimed;
}

async function completeJob(job: DeletionJob, status: "deleted" | "failed", errorMessage: string | null = null) {
  const now = new Date().toISOString();
  const payload: Record<string, unknown> = {
    status,
    processed_at: now
  };

  if (status === "deleted") {
    payload.deleted_at = now;
    payload.last_error = null;
  } else {
    payload.last_error = errorMessage;
    payload.status = "failed";
  }

  const { error } = await supabase
    .from("storage_deletion_jobs")
    .update(payload)
    .eq("id", job.id)
    .eq("organization_id", job.organization_id);

  if (error) {
    throw createHttpError(500, "Unable to persist storage deletion status.", { message: error.message });
  }

  if (status === "deleted") {
    await supabase
      .from("file_assets")
      .update({
        deletion_status: "deleted",
        deleted_at: now,
        deletion_error: null,
        metadata: { deletion_job_id: job.id }
      })
      .eq("id", job.file_asset_id)
      .eq("organization_id", job.organization_id);
  } else {
    await supabase
      .from("file_assets")
      .update({
        deletion_status: "failed",
        deletion_error: errorMessage,
        metadata: { deletion_job_id: job.id, deletion_error: errorMessage }
      })
      .eq("id", job.file_asset_id)
      .eq("organization_id", job.organization_id);
  }

  await supabase.from("file_access_events").insert({
    organization_id: job.organization_id,
    file_asset_id: job.file_asset_id,
    access_type: status === "deleted" ? "deleted" : "deletion_failed",
    success: status === "deleted",
    context: {
      bucket_id: job.bucket_id,
      object_path: job.object_path,
      error: errorMessage,
      attempts: job.attempts
    }
  });
}

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);

    const jobs = await claimJobs();
    const results: Array<{ id: string; status: string }> = [];

    for (const job of jobs) {
      try {
        const { error } = await supabase.storage.from(job.bucket_id).remove([job.object_path]);
        if (error) {
          const retryable = isRetryableDeletionFailure(error.message);
          if (!retryable) {
            await completeJob(job, "deleted");
            results.push({ id: job.id, status: "deleted" });
            continue;
          }

          await completeJob(job, "failed", error.message);
          results.push({ id: job.id, status: "failed" });
          continue;
        }

        await completeJob(job, "deleted");
        results.push({ id: job.id, status: "deleted" });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const retryable = isRetryableDeletionFailure(message);
        await completeJob(job, retryable ? "failed" : "deleted", retryable ? message : null);
        results.push({ id: job.id, status: retryable ? "failed" : "deleted" });
      }
    }

    return jsonResponse({
      ok: true,
      processed: jobs.length,
      deleted: results.filter((item) => item.status === "deleted").length,
      failed: results.filter((item) => item.status === "failed").length,
      results
    });
  } catch (error) {
    const normalized = normalizeHttpError(error);
    return jsonResponse(
      {
        error: normalized.message,
        details: normalized.details
      },
      { status: normalized.status }
    );
  }
});

