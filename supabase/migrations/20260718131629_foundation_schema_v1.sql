create extension if not exists pgcrypto;

CREATE TABLE IF NOT EXISTS foundation_object_types (
  type_key     TEXT PRIMARY KEY,
  domain       TEXT NOT NULL CHECK (domain IN
               ('organization','product','technical','sales','learning','market')),
  label        TEXT NOT NULL,
  attr_schema  JSONB NOT NULL DEFAULT '{}'::jsonb,
  steward_role TEXT NOT NULL DEFAULT 'steward_general',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS foundation_relationship_types (
  rel_key      TEXT PRIMARY KEY,
  label        TEXT NOT NULL,
  from_domains TEXT[] NOT NULL,
  to_domains   TEXT[] NOT NULL,
  attr_schema  JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS foundation_objects (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  object_type   TEXT NOT NULL REFERENCES foundation_object_types(type_key),
  name          TEXT NOT NULL,
  attributes    JSONB NOT NULL DEFAULT '{}'::jsonb,
  owner_org     UUID,
  status        TEXT NOT NULL DEFAULT 'draft' CHECK (status IN
                ('draft','candidate','verified','disputed','deprecated','retired')),
  version       INT  NOT NULL DEFAULT 1,
  permissions   JSONB NOT NULL DEFAULT '{"read":"trade","write":"steward"}'::jsonb,
  source        TEXT NOT NULL DEFAULT 'INTERNAL_APPLIANCE_IQ' CHECK (source IN
                ('MANUFACTURER','INTERNAL_APPLIANCE_IQ','INDUSTRY_ASSOCIATION','DEALER',
                 'INSTALLER','TECHNICIAN','AI_EXTRACTED','CUSTOMER_SUBMITTED','UNKNOWN')),
  confidence    NUMERIC(4,3) NOT NULL DEFAULT 0.500 CHECK (confidence >= 0 AND confidence <= 1),
  verified_by   UUID,
  verified_at   TIMESTAMPTZ,
  created_by    UUID,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by    UUID,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_fobjects_type    ON foundation_objects(object_type);
CREATE INDEX IF NOT EXISTS idx_fobjects_status  ON foundation_objects(status);
CREATE INDEX IF NOT EXISTS idx_fobjects_name    ON foundation_objects USING gin (to_tsvector('english', name));
CREATE INDEX IF NOT EXISTS idx_fobjects_attrs   ON foundation_objects USING gin (attributes);

CREATE TABLE IF NOT EXISTS foundation_relationships (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_id       UUID NOT NULL REFERENCES foundation_objects(id) ON DELETE CASCADE,
  to_id         UUID NOT NULL REFERENCES foundation_objects(id) ON DELETE CASCADE,
  rel_type      TEXT NOT NULL REFERENCES foundation_relationship_types(rel_key),
  attributes    JSONB NOT NULL DEFAULT '{}'::jsonb,
  status        TEXT NOT NULL DEFAULT 'candidate' CHECK (status IN
                ('draft','candidate','verified','disputed','deprecated','retired')),
  source        TEXT NOT NULL DEFAULT 'INTERNAL_APPLIANCE_IQ' CHECK (source IN
                ('MANUFACTURER','INTERNAL_APPLIANCE_IQ','INDUSTRY_ASSOCIATION','DEALER',
                 'INSTALLER','TECHNICIAN','AI_EXTRACTED','CUSTOMER_SUBMITTED','UNKNOWN')),
  confidence    NUMERIC(4,3) NOT NULL DEFAULT 0.500,
  verified_by   UUID, verified_at TIMESTAMPTZ,
  created_by    UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by    UUID, updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (from_id, to_id, rel_type)
);
CREATE INDEX IF NOT EXISTS idx_frel_from ON foundation_relationships(from_id, rel_type);
CREATE INDEX IF NOT EXISTS idx_frel_to   ON foundation_relationships(to_id, rel_type);

CREATE TABLE IF NOT EXISTS foundation_facts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  object_id         UUID NOT NULL REFERENCES foundation_objects(id) ON DELETE CASCADE,
  fact_type         TEXT NOT NULL,
  value_text        TEXT,
  value_num         NUMERIC,
  unit              TEXT,
  intelligence_type TEXT NOT NULL CHECK (intelligence_type IN
                    ('FACT','SPECIFICATION','RULE','INSTALLATION_REQUIREMENT',
                     'SALES_KNOWLEDGE','CUSTOMER_KNOWLEDGE','MARKET_KNOWLEDGE',
                     'RECOMMENDATION','AI_INFERENCE')),
  source            TEXT NOT NULL CHECK (source IN
                    ('MANUFACTURER','INTERNAL_APPLIANCE_IQ','INDUSTRY_ASSOCIATION','DEALER',
                     'INSTALLER','TECHNICIAN','AI_EXTRACTED','CUSTOMER_SUBMITTED','UNKNOWN')),
  source_asset      UUID REFERENCES mfr_assets(id),
  extraction_run    UUID,
  status            TEXT NOT NULL DEFAULT 'candidate' CHECK (status IN
                    ('draft','candidate','verified','disputed','deprecated','retired')),
  version           INT NOT NULL DEFAULT 1,
  effective_from    DATE NOT NULL DEFAULT CURRENT_DATE,
  effective_to      DATE,
  confidence        NUMERIC(4,3) NOT NULL DEFAULT 0.500,
  verified_by       UUID, verified_at TIMESTAMPTZ,
  created_by        UUID, created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (object_id, fact_type, version)
);
CREATE INDEX IF NOT EXISTS idx_ffacts_object  ON foundation_facts(object_id, fact_type);
CREATE INDEX IF NOT EXISTS idx_ffacts_status  ON foundation_facts(status);
CREATE INDEX IF NOT EXISTS idx_ffacts_current ON foundation_facts(object_id) WHERE effective_to IS NULL;

CREATE OR REPLACE FUNCTION foundation_fact_guard() RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'verified' AND (NEW.intelligence_type = 'AI_INFERENCE' OR NEW.source = 'UNKNOWN') THEN
    RAISE EXCEPTION 'Constitution: AI_INFERENCE / UNKNOWN-source facts cannot be verified (fact %)', NEW.id;
  END IF;
  IF NEW.status = 'verified' AND NEW.verified_by IS NULL THEN
    RAISE EXCEPTION 'Constitution: verified facts require verified_by (fact %)', NEW.id;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_fact_guard ON foundation_facts;
CREATE TRIGGER trg_fact_guard BEFORE INSERT OR UPDATE ON foundation_facts
  FOR EACH ROW EXECUTE FUNCTION foundation_fact_guard();

CREATE TABLE IF NOT EXISTS foundation_fact_reviews (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fact_id    UUID NOT NULL REFERENCES foundation_facts(id) ON DELETE CASCADE,
  reviewer   UUID NOT NULL,
  decision   TEXT NOT NULL CHECK (decision IN ('approve','reject','dispute','needs_info')),
  notes      TEXT,
  review_seconds INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_freviews_fact ON foundation_fact_reviews(fact_id);

CREATE TABLE IF NOT EXISTS foundation_disputes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fact_id     UUID NOT NULL REFERENCES foundation_facts(id) ON DELETE CASCADE,
  raised_by   UUID NOT NULL,
  raised_role TEXT NOT NULL,
  evidence    TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','upheld','rejected','withdrawn')),
  resolution  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID
);

CREATE TABLE IF NOT EXISTS foundation_audit_log (
  id           BIGSERIAL PRIMARY KEY,
  entity_table TEXT NOT NULL,
  entity_id    UUID NOT NULL,
  action       TEXT NOT NULL,
  actor        UUID,
  delta        JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION foundation_audit() RETURNS trigger AS $$
  DECLARE
    rec  JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  BEGIN
    INSERT INTO foundation_audit_log(entity_table, entity_id, action, actor, delta)
    VALUES (TG_TABLE_NAME,
            (rec ->> 'id')::uuid,
            TG_OP,
            COALESCE((rec ->> 'updated_by')::uuid, (rec ->> 'created_by')::uuid),
            rec);
    RETURN COALESCE(NEW, OLD);
  END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_audit_objects ON foundation_objects;
CREATE TRIGGER trg_audit_objects AFTER INSERT OR UPDATE OR DELETE ON foundation_objects
  FOR EACH ROW EXECUTE FUNCTION foundation_audit();
DROP TRIGGER IF EXISTS trg_audit_facts ON foundation_facts;
CREATE TRIGGER trg_audit_facts AFTER INSERT OR UPDATE OR DELETE ON foundation_facts
  FOR EACH ROW EXECUTE FUNCTION foundation_audit();
DROP TRIGGER IF EXISTS trg_audit_rels ON foundation_relationships;
CREATE TRIGGER trg_audit_rels AFTER INSERT OR UPDATE OR DELETE ON foundation_relationships
  FOR EACH ROW EXECUTE FUNCTION foundation_audit();

CREATE OR REPLACE VIEW v_verified_facts AS
  SELECT f.id, f.object_id, o.name AS object_name, o.object_type,
         f.fact_type, f.value_text, f.value_num, f.unit,
         f.intelligence_type, f.source, f.confidence, f.version,
         f.effective_from, f.verified_at
  FROM foundation_facts f
  JOIN foundation_objects o ON o.id = f.object_id
  WHERE f.status = 'verified' AND f.effective_to IS NULL;

CREATE OR REPLACE VIEW v_steward_queue AS
  SELECT f.*, o.name AS object_name, o.object_type
  FROM foundation_facts f JOIN foundation_objects o ON o.id = f.object_id
  WHERE f.status IN ('candidate','disputed')
  ORDER BY f.created_at;

CREATE OR REPLACE VIEW v_vendors AS SELECT * FROM mfr_vendors;

CREATE TABLE IF NOT EXISTS academy_quizzes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  volume_id  INT NOT NULL REFERENCES academy_volumes(id) ON DELETE CASCADE,
  questions  JSONB NOT NULL,
  version    INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (volume_id, version)
);
CREATE TABLE IF NOT EXISTS academy_worksheets (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  track      TEXT NOT NULL DEFAULT 'all',
  definition JSONB NOT NULL,
  version    INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS academy_cert_gates (
  id         TEXT PRIMARY KEY,
  definition JSONB NOT NULL,
  version    INT NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE foundation_objects        ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_relationships  ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_facts          ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_fact_reviews   ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_disputes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_audit_log      ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_read_objects ON foundation_objects;
CREATE POLICY p_read_objects ON foundation_objects FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_rels ON foundation_relationships;
CREATE POLICY p_read_rels ON foundation_relationships FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_facts ON foundation_facts;
CREATE POLICY p_read_facts ON foundation_facts FOR SELECT TO authenticated
  USING (status = 'verified' OR (auth.jwt() ->> 'aiq_role') IN ('steward','admin'));
DROP POLICY IF EXISTS p_steward_write_facts ON foundation_facts;
CREATE POLICY p_steward_write_facts ON foundation_facts FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() ->> 'aiq_role') IN ('steward','admin','extractor'));
DROP POLICY IF EXISTS p_steward_update_facts ON foundation_facts;
CREATE POLICY p_steward_update_facts ON foundation_facts FOR UPDATE TO authenticated
  USING ((auth.jwt() ->> 'aiq_role') IN ('steward','admin'));

INSERT INTO foundation_object_types (type_key, domain, label) VALUES
 ('organization','organization','Organization'),('manufacturer','organization','Manufacturer'),
 ('brand','organization','Brand'),('distributor','organization','Distributor'),
 ('retailer','organization','Retailer'),('buying_group','organization','Buying Group'),
 ('builder','organization','Builder'),('designer','organization','Designer'),
 ('property_manager','organization','Property Manager'),('service_provider','organization','Service Provider'),
 ('category','product','Category'),('subcategory','product','Subcategory'),
 ('series','product','Series'),('product','product','Product'),
 ('accessory','product','Accessory'),('bundle','product','Bundle'),
 ('specification','technical','Specification'),('feature','technical','Feature'),
 ('dimensions','technical','Dimensions'),('install_requirement','technical','Installation Requirement'),
 ('cert_standard','technical','Certification Standard'),('cad_asset','technical','CAD'),
 ('bim_asset','technical','BIM'),('manual','technical','Manual'),
 ('part','technical','Part'),('service_bulletin','technical','Service Bulletin'),
 ('customer_persona','sales','Customer Persona'),('buying_journey','sales','Buying Journey'),
 ('pain_point','sales','Pain Point'),('buying_trigger','sales','Buying Trigger'),
 ('sales_play','sales','Sales Play'),('discovery_question','sales','Discovery Question'),
 ('objection','sales','Objection'),('closing_strategy','sales','Closing Strategy'),
 ('promotion','sales','Promotion'),('warranty','sales','Warranty'),('financing','sales','Financing'),
 ('volume','learning','Volume'),('track','learning','Track'),('lesson','learning','Lesson'),
 ('worksheet','learning','Worksheet'),('simulation','learning','Simulation'),
 ('certification','learning','Certification'),('quiz','learning','Quiz'),
 ('roleplay','learning','Roleplay'),('assessment','learning','Assessment'),
 ('competitor','market','Competitor'),('market_share','market','Market Share'),
 ('award','market','Award'),('technology','market','Technology'),
 ('innovation','market','Innovation'),('patent','market','Patent'),
 ('review','market','Review'),('industry_trend','market','Industry Trend'),
 ('target_customer','market','Target Customer'),('price_position','market','Price Position')
ON CONFLICT (type_key) DO NOTHING;

INSERT INTO foundation_relationship_types (rel_key, label, from_domains, to_domains) VALUES
 ('owns','owns','{organization}','{organization}'),
 ('contains','contains','{organization,product}','{product}'),
 ('has_feature','has feature','{product}','{technical}'),
 ('specified_by','specified by','{technical,product}','{technical}'),
 ('has_dimensions','has dimensions','{product}','{technical}'),
 ('requires','requires','{product}','{technical}'),
 ('completed_by','completed by (day-one install)','{product}','{product}'),
 ('in_bundle','in bundle','{product}','{product}'),
 ('replaces','replaces','{product}','{product}'),
 ('compatible_with','compatible with','{product}','{product}'),
 ('competes_with','competes with','{product,organization}','{product,organization}'),
 ('addresses','addresses','{product,sales}','{sales}'),
 ('applies_to','applies to','{sales}','{product}'),
 ('covers','covers','{sales}','{product,organization}'),
 ('experiences','experiences','{sales}','{sales}'),
 ('triggered_by','triggered by','{sales}','{sales}'),
 ('teaches','teaches','{learning}','{organization,product,technical,sales,market}'),
 ('requires_completion','requires completion of','{learning}','{learning}'),
 ('positioned_against','positioned against','{market,organization}','{organization,product}'),
 ('about','about','{market}','{product,organization}'),
 ('affects','affects','{market}','{product,organization}')
ON CONFLICT (rel_key) DO NOTHING;
