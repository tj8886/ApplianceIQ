CREATE OR REPLACE FUNCTION tj_private.my_platform_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=tj_private.current_source_user_id(); out_ctx jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 SELECT jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',c.entity_type,
 'entity_id',c.entity_id,'entity_label',c.entity_label,'source_module_key',c.source_module_key,
 'context',coalesce(c.context,'{}'::jsonb),'updated_at',c.updated_at) INTO out_ctx
 FROM tj.platform_user_context c
 JOIN tj.organizations o ON o.id=c.organization_id AND o.deleted_at IS NULL AND o.status='active'
 JOIN tj.organization_members m ON m.organization_id=o.id AND m.user_id=uid AND m.status='active'
 LEFT JOIN tj.org_locations l ON l.id=c.location_id AND l.organization_id=o.id AND l.is_active IS TRUE
 WHERE c.user_id=uid AND (c.location_id IS NULL OR l.id IS NOT NULL);
 IF out_ctx IS NULL THEN
 SELECT jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',NULL,'entity_id',NULL,
 'entity_label',NULL,'source_module_key','platform','context','{}'::jsonb,'updated_at',now()) INTO out_ctx
 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL AND o.status='active'
 LEFT JOIN LATERAL (SELECT loc.id,loc.name,loc.code FROM tj.org_location_members lm
 JOIN tj.org_locations loc ON loc.id=lm.location_id AND loc.organization_id=m.organization_id
 AND loc.is_active IS TRUE WHERE lm.organization_id=m.organization_id AND lm.user_id=uid
 ORDER BY lm.is_primary DESC,lm.created_at,loc.id LIMIT 1) l ON TRUE
 WHERE m.user_id=uid AND m.status='active' ORDER BY m.created_at,m.id LIMIT 1;
 END IF;
 RETURN coalesce(out_ctx,jsonb_build_object('user_id',auth.uid(),'source_user_id',uid,'context','{}'::jsonb));
END $$;

NOTIFY pgrst,'reload schema';
