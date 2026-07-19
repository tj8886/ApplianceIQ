-- ============================================================================
-- METRICS IMPORT v1 — machine ingestion for the Daily Five.
-- API keys for external systems (POS, ETL, cron) + email→user resolution.
-- ============================================================================
CREATE TABLE IF NOT EXISTS academy_api_keys (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  label        TEXT NOT NULL,                -- 'Store POS nightly', 'HQ Oracle job'
  key_hash     TEXT UNIQUE NOT NULL,         -- sha256 hex of the key; plaintext never stored
  firm_id      UUID REFERENCES academy_firms(id) ON DELETE CASCADE,
  scopes       TEXT[] NOT NULL DEFAULT ARRAY['metrics:write'],
  active       BOOLEAN NOT NULL DEFAULT true,
  created_by   UUID,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_used_at TIMESTAMPTZ
);
ALTER TABLE academy_api_keys ENABLE ROW LEVEL SECURITY;
-- no anon/authenticated policies: service-role only, by design.

-- Resolve external identities (emails) to auth user ids. SECURITY DEFINER,
-- service-role execution only — the import function is the sole caller.
CREATE OR REPLACE FUNCTION resolve_user_emails(p_emails TEXT[])
RETURNS TABLE(email TEXT, user_id UUID)
LANGUAGE sql SECURITY DEFINER SET search_path = public, auth AS $$
  SELECT lower(u.email)::text, u.id
  FROM auth.users u
  WHERE lower(u.email) = ANY(SELECT lower(e) FROM unnest(p_emails) e);
$$;
REVOKE EXECUTE ON FUNCTION resolve_user_emails(TEXT[]) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION resolve_user_emails(TEXT[]) TO service_role;

-- Import audit: every batch logged (source, counts, errors)
CREATE TABLE IF NOT EXISTS academy_metric_imports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key_id       UUID REFERENCES academy_api_keys(id),
  admin_user   UUID,
  source       TEXT NOT NULL,                -- 'api-json' | 'api-csv' | 'portal-csv'
  rows_received INT NOT NULL,
  rows_applied INT NOT NULL,
  rows_failed  INT NOT NULL,
  errors       JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE academy_metric_imports ENABLE ROW LEVEL SECURITY;
