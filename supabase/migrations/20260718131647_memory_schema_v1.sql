CREATE TABLE IF NOT EXISTS memory_subjects (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_kind TEXT NOT NULL CHECK (subject_kind IN ('customer','employee','trade_contact','org')),
  display_name TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS memory_subject_links (
  subject_id   UUID NOT NULL REFERENCES memory_subjects(id) ON DELETE CASCADE,
  link_kind    TEXT NOT NULL,
  link_value   TEXT NOT NULL,
  verified     BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (subject_id, link_kind, link_value)
);

CREATE TABLE IF NOT EXISTS memory_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id   UUID NOT NULL REFERENCES memory_subjects(id) ON DELETE CASCADE,
  tenant_id    UUID,
  event_type   TEXT NOT NULL,
  payload      JSONB NOT NULL,
  scope        TEXT NOT NULL DEFAULT 'session' CHECK (scope IN ('session','durable')),
  consent_id   UUID,
  session_id   UUID,
  source_agent TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at   TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_mev_subject ON memory_events(subject_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mev_expiry  ON memory_events(expires_at) WHERE expires_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS memory_facts (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_id    UUID NOT NULL REFERENCES memory_subjects(id) ON DELETE CASCADE,
  tenant_id     UUID,
  memory_type   TEXT NOT NULL,
  key           TEXT NOT NULL,
  value         JSONB NOT NULL,
  confidence    NUMERIC(4,3) NOT NULL DEFAULT 0.7,
  freshness     DATE NOT NULL DEFAULT CURRENT_DATE,
  derived_from  UUID REFERENCES memory_events(id),
  consent_id    UUID,
  superseded_by UUID REFERENCES memory_facts(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (subject_id, tenant_id, key, created_at)
);
CREATE INDEX IF NOT EXISTS idx_mf_subject ON memory_facts(subject_id) WHERE superseded_by IS NULL;

CREATE OR REPLACE VIEW v_memory_current AS
  SELECT subject_id, tenant_id, memory_type, key, value, confidence, freshness
  FROM memory_facts WHERE superseded_by IS NULL;

ALTER TABLE memory_subjects      ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory_subject_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE memory_facts         ENABLE ROW LEVEL SECURITY;
