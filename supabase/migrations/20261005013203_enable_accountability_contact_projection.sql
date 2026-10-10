DO $guard$ BEGIN IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='tj.aicrm_contacts'::regclass) OR EXISTS(SELECT 1 FROM pg_policy WHERE polrelid='tj.aicrm_contacts'::regclass) THEN RAISE EXCEPTION 'Review existing contact RLS'; END IF; END $guard$;
CREATE POLICY consolidation_accountability_contact_read ON tj.aicrm_contacts FOR SELECT TO authenticated USING(tj_private.can_read_runtime_org(organization_id) AND tj.aiq_scope_allows(organization_id,created_by));
GRANT SELECT(id,organization_id,full_name,email,phone,crm_completeness,deleted_at) ON tj.aicrm_contacts TO authenticated;
