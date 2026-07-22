-- =============================================================================
-- PROPOSED SCHEMA — NOT APPLIED
-- Created: 2026-07-22
-- Purpose: Schema required by file-url-mint, storage-deletion-worker, file-scanner
-- Status: These tables do NOT exist in production despite the edge functions being deployed.
--         The functions may be non-functional or may have been deployed for future use.
--         DO NOT apply this migration without verifying production state first.
--
-- Required by:
--   file-url-mint      → signed_url_nonces, file_access_events, consume_signed_url_nonce()
--   storage-deletion-worker → storage_deletion_jobs, file_assets, file_access_events
--   file-scanner        → file_assets, file_access_events, v_files_pending_scan
--
-- WARNING: This schema is organization-based. It must NOT be connected to
-- vendor-owned manufacturer assets (mfr_assets) without explicit design review.
-- The mfr_assets system uses vendor_id ownership, not organization_id.
-- =============================================================================

-- file_assets: central registry of uploaded files
CREATE TABLE IF NOT EXISTS public.file_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  bucket_id text NOT NULL,
  object_path text NOT NULL,
  file_name text NOT NULL,
  mime_type text,
  file_size_bytes bigint,
  uploaded_by uuid REFERENCES auth.users(id),
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  sensitivity text DEFAULT 'internal',
  scan_status text DEFAULT 'pending',
  scanned_at timestamptz,
  scan_engine text,
  scan_error text,
  deletion_status text,
  deleted_at timestamptz,
  deletion_error text,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- signed_url_nonces: one-time-use tokens for secure file access
CREATE TABLE IF NOT EXISTS public.signed_url_nonces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  file_asset_id uuid NOT NULL REFERENCES public.file_assets(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  nonce text NOT NULL UNIQUE,
  bucket text NOT NULL,
  path text NOT NULL,
  filename text NOT NULL,
  purpose text NOT NULL DEFAULT 'download',
  consumed boolean DEFAULT false,
  consumed_at timestamptz,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- file_access_events: audit trail for file operations
CREATE TABLE IF NOT EXISTS public.file_access_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  file_asset_id uuid REFERENCES public.file_assets(id),
  actor_user_id uuid,
  access_type text NOT NULL,
  success boolean DEFAULT true,
  context jsonb DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- storage_deletion_jobs: queue for background file deletion
CREATE TABLE IF NOT EXISTS public.storage_deletion_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  file_asset_id uuid NOT NULL REFERENCES public.file_assets(id),
  bucket_id text NOT NULL,
  object_path text NOT NULL,
  status text NOT NULL DEFAULT 'queued',
  attempts integer DEFAULT 0,
  claimed_at timestamptz,
  processed_at timestamptz,
  deleted_at timestamptz,
  last_error text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb
);

-- v_files_pending_scan: view for file-scanner to pick up work
CREATE OR REPLACE VIEW public.v_files_pending_scan AS
SELECT id, organization_id, bucket_id, object_path, file_name, mime_type,
       file_size_bytes, uploaded_at, sensitivity
FROM public.file_assets
WHERE scan_status = 'pending';

-- consume_signed_url_nonce: atomically consume a nonce and return file details
CREATE OR REPLACE FUNCTION public.consume_signed_url_nonce(p_nonce text, p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $$
DECLARE
  v_record record;
BEGIN
  UPDATE public.signed_url_nonces
  SET consumed = true, consumed_at = now()
  WHERE nonce = p_nonce
    AND user_id = p_user_id
    AND consumed = false
    AND expires_at > now()
  RETURNING * INTO v_record;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  RETURN jsonb_build_object(
    'bucket', v_record.bucket,
    'path', v_record.path,
    'filename', v_record.filename,
    'purpose', v_record.purpose,
    'expires_at', v_record.expires_at,
    'organization_id', v_record.organization_id,
    'file_asset_id', v_record.file_asset_id
  );
END;
$$;

-- RLS
ALTER TABLE public.file_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.signed_url_nonces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.file_access_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.storage_deletion_jobs ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_file_assets_org ON public.file_assets(organization_id);
CREATE INDEX IF NOT EXISTS idx_file_assets_scan_status ON public.file_assets(scan_status) WHERE scan_status = 'pending';
CREATE INDEX IF NOT EXISTS idx_signed_url_nonces_nonce ON public.signed_url_nonces(nonce) WHERE consumed = false;
CREATE INDEX IF NOT EXISTS idx_storage_deletion_jobs_status ON public.storage_deletion_jobs(status) WHERE status = 'queued';
