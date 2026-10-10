ALTER POLICY consolidation_app_read ON tj.piq_retailer_profiles USING(tj_private.is_source_self(user_id) AND (organization_id IS NULL OR tj_private.can_read_runtime_org(organization_id)));
NOTIFY pgrst,'reload schema';
