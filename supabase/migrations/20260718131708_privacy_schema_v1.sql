CREATE TABLE IF NOT EXISTS privacy_jurisdictions (
  code             TEXT PRIMARY KEY,
  label            TEXT NOT NULL,
  recording_mode   TEXT NOT NULL DEFAULT 'structured_notes_only'
                   CHECK (recording_mode IN ('structured_notes_only','transcription_optin','prohibited')),
  employee_policy_required BOOLEAN NOT NULL DEFAULT true,
  notes            TEXT,
  counsel_signoff  BOOLEAN NOT NULL DEFAULT false,
  signoff_by       TEXT, signoff_at TIMESTAMPTZ,
  version          INT NOT NULL DEFAULT 1,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS consent_ledger (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id    UUID NOT NULL,
  tenant_id     UUID,
  scope         TEXT NOT NULL,
  basis         TEXT NOT NULL CHECK (basis IN ('consent','contract','legitimate_interest','legal_obligation')),
  jurisdiction  TEXT REFERENCES privacy_jurisdictions(code),
  matrix_version INT,
  method        TEXT NOT NULL,
  granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at    TIMESTAMPTZ,
  revoked_at    TIMESTAMPTZ,
  revoked_method TEXT,
  evidence      JSONB NOT NULL DEFAULT '{}'::jsonb
);
CREATE INDEX IF NOT EXISTS idx_consent_active ON consent_ledger(subject_id, scope) WHERE revoked_at IS NULL;

CREATE OR REPLACE FUNCTION consent_active(p_subject UUID, p_scope TEXT)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM consent_ledger
    WHERE subject_id = p_subject AND scope = p_scope
      AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > now()));
$$ LANGUAGE sql STABLE;

CREATE TABLE IF NOT EXISTS privacy_retention_policies (
  data_class   TEXT PRIMARY KEY,
  retain_days  INT NOT NULL,
  legal_hold_exempt BOOLEAN NOT NULL DEFAULT false,
  notes        TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS privacy_purge_log (
  id          BIGSERIAL PRIMARY KEY,
  data_class  TEXT NOT NULL,
  purged_rows INT NOT NULL,
  job_run     UUID NOT NULL,
  ran_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS dsr_requests (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id    UUID NOT NULL,
  tenant_id     UUID,
  request_type  TEXT NOT NULL CHECK (request_type IN ('access','correction','deletion','portability')),
  status        TEXT NOT NULL DEFAULT 'received' CHECK (status IN
                ('received','identity_verification','processing','downstream_notified','completed','rejected')),
  jurisdiction  TEXT REFERENCES privacy_jurisdictions(code),
  due_at        TIMESTAMPTZ NOT NULL,
  details       JSONB NOT NULL DEFAULT '{}'::jsonb,
  received_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at  TIMESTAMPTZ,
  handled_by    UUID
);
CREATE TABLE IF NOT EXISTS dsr_downstream_notices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  dsr_id       UUID NOT NULL REFERENCES dsr_requests(id) ON DELETE CASCADE,
  participant  TEXT NOT NULL,
  notified_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at TIMESTAMPTZ
);

INSERT INTO privacy_jurisdictions (code, label, recording_mode, employee_policy_required, notes) VALUES
 ('CA-ON','Ontario, Canada','structured_notes_only', true,
  'PIPEDA; ESA s.41.1.1 written electronic monitoring policy required (25+ employees) before any transcription mode. COUNSEL REVIEW REQUIRED.'),
 ('CA-QC','Quebec, Canada','structured_notes_only', true,
  'Law 25: express consent, privacy officer, PIAs, French-language notices. Own deployment profile. COUNSEL REVIEW REQUIRED.'),
 ('US-DEFAULT','United States (default)','structured_notes_only', true,
  'All-party-consent states exist; no state row => notes-only. COUNSEL REVIEW REQUIRED.')
ON CONFLICT (code) DO NOTHING;

INSERT INTO privacy_retention_policies (data_class, retain_days, notes) VALUES
 ('delivery.address', 30, 'Job-scoped; purge post-completion window'),
 ('install.site_notes', 90, 'Job-scoped; installer callbacks window'),
 ('conversation.session_events', 30, 'Session-scope memory events'),
 ('finance.application_passthrough', 0, 'Never stored — enforced upstream; row documents the rule')
ON CONFLICT (data_class) DO NOTHING;

ALTER TABLE consent_ledger    ENABLE ROW LEVEL SECURITY;
ALTER TABLE dsr_requests      ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_purge_log ENABLE ROW LEVEL SECURITY;
