-- ============================================================================
-- SECURITY HARDENING v1 — closes advisor findings before first deploy.
-- Content tables: authenticated read-only. User tables: own-row.
-- Ops/governance tables: RLS on, no policy = service-role only (deny default).
-- ============================================================================

-- 1. CONTENT TABLES — authenticated read, service-role write
ALTER TABLE academy_volumes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_chapters           ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_tracks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_plans              ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_quizzes            ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_worksheets         ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_cert_gates         ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_object_types    ENABLE ROW LEVEL SECURITY;
ALTER TABLE foundation_relationship_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_jurisdictions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy_retention_policies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_read_volumes ON academy_volumes;
CREATE POLICY p_read_volumes ON academy_volumes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_chapters ON academy_chapters;
CREATE POLICY p_read_chapters ON academy_chapters FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_tracks ON academy_tracks;
CREATE POLICY p_read_tracks ON academy_tracks FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_plans ON academy_plans;
CREATE POLICY p_read_plans ON academy_plans FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_quizzes ON academy_quizzes;
CREATE POLICY p_read_quizzes ON academy_quizzes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_worksheets ON academy_worksheets;
CREATE POLICY p_read_worksheets ON academy_worksheets FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_cert_gates ON academy_cert_gates;
CREATE POLICY p_read_cert_gates ON academy_cert_gates FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_otypes ON foundation_object_types;
CREATE POLICY p_read_otypes ON foundation_object_types FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_rtypes ON foundation_relationship_types;
CREATE POLICY p_read_rtypes ON foundation_relationship_types FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_jurisdictions ON privacy_jurisdictions;
CREATE POLICY p_read_jurisdictions ON privacy_jurisdictions FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS p_read_retention ON privacy_retention_policies;
CREATE POLICY p_read_retention ON privacy_retention_policies FOR SELECT TO authenticated USING (true);

-- 2. USER DATA — own-row access
ALTER TABLE academy_progress       ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_track_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_certifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_own_progress ON academy_progress;
CREATE POLICY p_own_progress ON academy_progress FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS p_own_track_progress ON academy_track_progress;
CREATE POLICY p_own_track_progress ON academy_track_progress FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS p_own_profile ON academy_profiles;
CREATE POLICY p_own_profile ON academy_profiles FOR ALL TO authenticated
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
DROP POLICY IF EXISTS p_own_certs ON academy_certifications;
CREATE POLICY p_own_certs ON academy_certifications FOR ALL TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 3. OPS / FIRM / GOVERNANCE — RLS on, no anon/authenticated policy:
--    service-role only until firm features ship (deny-by-default is intended).
ALTER TABLE academy_firms          ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_seats          ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_cohorts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE academy_cohort_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE dsr_downstream_notices ENABLE ROW LEVEL SECURITY;

-- 4. VIEWS — enforce querying user's RLS (fixes SECURITY DEFINER findings)
ALTER VIEW v_verified_facts SET (security_invoker = true);
ALTER VIEW v_steward_queue  SET (security_invoker = true);
ALTER VIEW v_vendors        SET (security_invoker = true);
ALTER VIEW v_memory_current SET (security_invoker = true);

-- 5. FUNCTIONS — pin search_path (fixes mutable search_path warnings)
ALTER FUNCTION is_admin()                SET search_path = public;
ALTER FUNCTION manages_vendor(uuid)      SET search_path = public;
ALTER FUNCTION foundation_fact_guard()   SET search_path = public;
ALTER FUNCTION foundation_audit()        SET search_path = public;
ALTER FUNCTION consent_active(uuid,text) SET search_path = public;

-- 6. Lock SECURITY DEFINER helpers away from anon (kept for authenticated:
--    RLS policies on mfr_* tables depend on them; they only reveal the
--    caller's own booleans).
REVOKE EXECUTE ON FUNCTION is_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION manages_vendor(uuid) FROM anon;
