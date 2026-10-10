-- Storage paths carry the source organization identifier; malformed paths deny access.
CREATE FUNCTION tj_private.storage_org_from_path(p_name text) RETURNS uuid
LANGUAGE sql IMMUTABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT CASE WHEN split_part(p_name,'/',1) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
 THEN split_part(p_name,'/',1)::uuid ELSE NULL END; $$;
REVOKE ALL ON FUNCTION tj_private.storage_org_from_path(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.storage_org_from_path(text) TO authenticated;

CREATE POLICY consolidation_crm_media_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='crm-media' AND tj.is_org_member(tj_private.storage_org_from_path(name)));
CREATE POLICY consolidation_crm_media_upload ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='crm-media' AND tj.is_org_member(tj_private.storage_org_from_path(name)));
CREATE POLICY consolidation_crm_media_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='crm-media' AND tj.is_org_admin(tj_private.storage_org_from_path(name)));

CREATE POLICY consolidation_manager_files_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='manager-task-files' AND tj_private.storage_org_from_path(name)
 IN (SELECT o.organization_id FROM tj.my_platform_organizations() o));
CREATE POLICY consolidation_manager_files_upload ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='manager-task-files' AND tj_private.storage_org_from_path(name)
 IN (SELECT o.organization_id FROM tj.my_platform_organizations() o));
CREATE POLICY consolidation_manager_files_update ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id='manager-task-files' AND owner_id=(SELECT auth.uid())::text AND tj_private.storage_org_from_path(name)
 IN (SELECT o.organization_id FROM tj.my_platform_organizations() o))
WITH CHECK (bucket_id='manager-task-files' AND owner_id=(SELECT auth.uid())::text AND tj_private.storage_org_from_path(name)
 IN (SELECT o.organization_id FROM tj.my_platform_organizations() o));
CREATE POLICY consolidation_manager_files_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='manager-task-files' AND owner_id=(SELECT auth.uid())::text AND tj_private.storage_org_from_path(name)
 IN (SELECT o.organization_id FROM tj.my_platform_organizations() o));
