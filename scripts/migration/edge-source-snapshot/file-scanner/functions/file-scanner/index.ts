import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { classifyFileScan } from "../_shared/file-governance.js";
import { createHttpError, ensureAllowedMethod, jsonResponse, normalizeHttpError } from "../_shared/http.js";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

type PendingFile = {
  id: string;
  organization_id: string;
  bucket_id: string;
  object_path: string;
  file_name: string;
  mime_type: string | null;
  file_size_bytes: number | null;
  uploaded_at: string;
  sensitivity: string | null;
};

function extensionFor(name: string) {
  const parts = name.toLowerCase().split(".");
  return parts.length > 1 ? parts.at(-1) || "" : "";
}

async function scanFile(file: PendingFile, blob: Blob) {
  const head = new Uint8Array(await blob.slice(0, 8).arrayBuffer());
  const headHex = Array.from(head)
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");

  return classifyFileScan({
    fileName: file.file_name || file.object_path || extensionFor(file.file_name),
    mimeType: file.mime_type,
    sizeBytes: file.file_size_bytes,
    headHex
  });
}

async function markScanResult(fileId: string, organizationId: string, result: { status: string; reason?: string; details?: Record<string, unknown> }) {
  const { error } = await supabase
    .from("file_assets")
    .update({
      scan_status: result.status,
      scanned_at: new Date().toISOString(),
      scan_engine: "static_rules_v1",
      scan_error: result.status === "clean" ? null : result.reason ?? "scan_result",
      metadata: { scan_result: result }
    })
    .eq("id", fileId)
    .eq("organization_id", organizationId);

  if (error) {
    throw createHttpError(500, "Unable to persist scan result.", { message: error.message });
  }
}

async function markScanFailed(fileId: string, organizationId: string, errorMessage: string) {
  const { error } = await supabase
    .from("file_assets")
    .update({
      scan_status: "failed",
      scanned_at: new Date().toISOString(),
      scan_engine: "static_rules_v1",
      scan_error: errorMessage,
      metadata: { scan_error: errorMessage }
    })
    .eq("id", fileId)
    .eq("organization_id", organizationId);

  if (error) {
    throw createHttpError(500, "Unable to mark scan failure.", { message: error.message });
  }
}

async function recordScanAudit(file: PendingFile, outcome: string, details: Record<string, unknown>) {
  const { error } = await supabase.from("file_access_events").insert({
    organization_id: file.organization_id,
    file_asset_id: file.id,
    access_type: "scan",
    success: outcome === "clean",
    context: {
      outcome,
      details
    }
  });

  if (error) {
    throw createHttpError(500, "Unable to record scan audit event.", { message: error.message });
  }
}

Deno.serve(async (request) => {
  try {
    ensureAllowedMethod(request, ["POST"]);

    const { data: pending, error: pendingErr } = await supabase
      .from("v_files_pending_scan")
      .select("id,organization_id,bucket_id,object_path,file_name,mime_type,file_size_bytes,uploaded_at,sensitivity");

    if (pendingErr) {
      throw createHttpError(500, "Unable to fetch pending files.", { message: pendingErr.message });
    }

    const files = (pending ?? []) as PendingFile[];
    let clean = 0;
    let infected = 0;
    let unsupported = 0;
    let failed = 0;

    for (const file of files) {
      const { data: claimed, error: claimErr } = await supabase
        .from("file_assets")
        .update({ scan_status: "scanning", scan_engine: "static_rules_v1" })
        .eq("id", file.id)
        .eq("organization_id", file.organization_id)
        .eq("scan_status", "pending")
        .select("id")
        .maybeSingle();

      if (claimErr || !claimed) {
        continue;
      }

      try {
        const { data: blob, error: downloadError } = await supabase.storage.from(file.bucket_id).download(file.object_path);
        if (downloadError || !blob) {
          throw new Error(downloadError?.message ?? "download failed");
        }

        const result = await scanFile(file, blob);
        await markScanResult(file.id, file.organization_id, result);
        await recordScanAudit(file, result.status, result.details ?? {});

        if (result.status === "clean") {
          clean += 1;
        } else if (result.status === "infected") {
          infected += 1;
        } else if (result.status === "unsupported") {
          unsupported += 1;
        } else {
          failed += 1;
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        await markScanFailed(file.id, file.organization_id, message);
        await recordScanAudit(file, "failed", { error: message });
        failed += 1;
      }
    }

    return jsonResponse({
      ok: true,
      processed: files.length,
      clean,
      infected,
      unsupported,
      failed
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

