-- Reviewed platform bootstrap RPCs. Existing US public APIs are untouched.
-- Privileged implementations remain private; callers need an activated identity map.
CREATE FUNCTION tj_private.my_entitled_apps() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT coalesce(jsonb_agg(DISTINCT e.app_key),'[]'::jsonb)
 FROM tj.org_app_entitlements e JOIN tj.organizations o ON o.id=e.organization_id
 WHERE o.deleted_at IS NULL AND tj_private.current_source_user_id() IS NOT NULL
 AND (tj_private.is_platform_admin() OR (e.status IN ('active','trial') AND EXISTS (
 SELECT 1 FROM tj.organization_members m WHERE m.organization_id=e.organization_id
 AND m.user_id=tj_private.current_source_user_id() AND m.status='active')));
$$;

CREATE FUNCTION tj_private.my_platform_organizations()
RETURNS TABLE(organization_id uuid,organization_name text,role text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT o.id,o.name,m.role FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id
 WHERE m.user_id=tj_private.current_source_user_id() AND m.status='active'
 AND o.deleted_at IS NULL ORDER BY o.name; $$;

CREATE FUNCTION tj_private.my_platform_locations(p_organization_id uuid)
RETURNS TABLE(location_id uuid,location_name text,location_code text,location_type text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT l.id,l.name,l.code,l.location_type FROM tj.org_locations l
 JOIN tj.organizations o ON o.id=l.organization_id AND o.deleted_at IS NULL
 WHERE l.organization_id=p_organization_id AND l.is_active IS TRUE
 AND EXISTS (SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_organization_id
 AND m.user_id=tj_private.current_source_user_id() AND m.status='active') ORDER BY l.name; $$;

CREATE FUNCTION tj_private.my_platform_context() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=tj_private.current_source_user_id(); out_ctx jsonb;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 SELECT jsonb_build_object('user_id',auth.uid(),'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',c.entity_type,
 'entity_id',c.entity_id,'entity_label',c.entity_label,'source_module_key',c.source_module_key,
 'context',coalesce(c.context,'{}'::jsonb),'updated_at',c.updated_at) INTO out_ctx
 FROM tj.platform_user_context c
 JOIN tj.organizations o ON o.id=c.organization_id AND o.deleted_at IS NULL
 JOIN tj.organization_members m ON m.organization_id=o.id AND m.user_id=uid AND m.status='active'
 LEFT JOIN tj.org_locations l ON l.id=c.location_id AND l.organization_id=o.id AND l.is_active IS TRUE
 WHERE c.user_id=uid AND (c.location_id IS NULL OR l.id IS NOT NULL);
 IF out_ctx IS NULL THEN
 SELECT jsonb_build_object('user_id',auth.uid(),'organization_id',o.id,
 'organization_name',o.name,'organization_role',m.role,'location_id',l.id,
 'location_name',l.name,'location_code',l.code,'entity_type',NULL,'entity_id',NULL,
 'entity_label',NULL,'source_module_key','platform','context','{}'::jsonb,'updated_at',now()) INTO out_ctx
 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 LEFT JOIN LATERAL (SELECT loc.id,loc.name,loc.code FROM tj.org_location_members lm
 JOIN tj.org_locations loc ON loc.id=lm.location_id AND loc.organization_id=m.organization_id
 AND loc.is_active IS TRUE WHERE lm.organization_id=m.organization_id AND lm.user_id=uid
 ORDER BY lm.is_primary DESC,lm.created_at,loc.id LIMIT 1) l ON TRUE
 WHERE m.user_id=uid AND m.status='active' ORDER BY m.created_at,m.id LIMIT 1;
 END IF;
 RETURN coalesce(out_ctx,jsonb_build_object('user_id',auth.uid(),'context','{}'::jsonb));
END $$;

CREATE FUNCTION tj_private.set_platform_context(p_organization_id uuid DEFAULT NULL,
 p_location_id uuid DEFAULT NULL,p_entity_type text DEFAULT NULL,p_entity_id text DEFAULT NULL,
 p_entity_label text DEFAULT NULL,p_source_module_key text DEFAULT NULL,p_context jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE uid uuid:=tj_private.current_source_user_id(); org_id uuid;
BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 org_id:=p_organization_id;
 IF org_id IS NULL THEN
 SELECT c.organization_id INTO org_id FROM tj.platform_user_context c
 JOIN tj.organizations o ON o.id=c.organization_id AND o.deleted_at IS NULL
 JOIN tj.organization_members m ON m.organization_id=o.id AND m.user_id=uid AND m.status='active'
 WHERE c.user_id=uid;
 END IF;
 IF org_id IS NULL THEN SELECT organization_id INTO org_id FROM tj_private.my_platform_organizations() LIMIT 1; END IF;
 IF org_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tj.organization_members m
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.user_id=uid AND m.organization_id=org_id AND m.status='active')
 THEN RAISE EXCEPTION 'organization_access_denied'; END IF;
 IF p_location_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tj.org_locations l
 WHERE l.id=p_location_id AND l.organization_id=org_id AND l.is_active IS TRUE)
 THEN RAISE EXCEPTION 'location_access_denied'; END IF;
 INSERT INTO tj.platform_user_context(user_id,organization_id,location_id,entity_type,entity_id,entity_label,source_module_key,context,updated_at)
 VALUES(uid,org_id,p_location_id,p_entity_type,p_entity_id,p_entity_label,p_source_module_key,coalesce(p_context,'{}'),now())
 ON CONFLICT(user_id) DO UPDATE SET organization_id=excluded.organization_id,location_id=excluded.location_id,
 entity_type=excluded.entity_type,entity_id=excluded.entity_id,entity_label=excluded.entity_label,
 source_module_key=excluded.source_module_key,context=excluded.context,updated_at=now();
 RETURN tj_private.my_platform_context();
END $$;

CREATE FUNCTION tj_private.platform_mark_notification_read(p_notification_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE uid uuid:=tj_private.current_source_user_id(); BEGIN
 IF uid IS NULL THEN RAISE EXCEPTION 'authentication_required'; END IF;
 UPDATE tj.crm_notifications n SET is_read=TRUE,read_at=coalesce(n.read_at,now())
 WHERE n.id=p_notification_id AND n.user_id=uid AND (n.organization_id IS NULL OR EXISTS (
 SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE m.organization_id=n.organization_id AND m.user_id=uid AND m.status='active'));
 RETURN FOUND;
END $$;

CREATE FUNCTION tj.my_entitled_apps() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.my_entitled_apps(); $$;
CREATE FUNCTION tj.my_platform_organizations() RETURNS TABLE(organization_id uuid,organization_name text,role text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj_private.my_platform_organizations(); $$;
CREATE FUNCTION tj.my_platform_locations(p_organization_id uuid)
RETURNS TABLE(location_id uuid,location_name text,location_code text,location_type text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM tj_private.my_platform_locations(p_organization_id); $$;
CREATE FUNCTION tj.my_platform_context() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.my_platform_context(); $$;
CREATE FUNCTION tj.set_platform_context(p_organization_id uuid DEFAULT NULL,p_location_id uuid DEFAULT NULL,
 p_entity_type text DEFAULT NULL,p_entity_id text DEFAULT NULL,p_entity_label text DEFAULT NULL,
 p_source_module_key text DEFAULT NULL,p_context jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=''
AS $$ SELECT tj_private.set_platform_context(p_organization_id,p_location_id,p_entity_type,p_entity_id,p_entity_label,p_source_module_key,p_context); $$;
CREATE FUNCTION tj.platform_mark_notification_read(p_notification_id uuid) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.platform_mark_notification_read(p_notification_id); $$;

DO $$ DECLARE s text; signature text; BEGIN
 FOREACH s IN ARRAY ARRAY['tj','tj_private'] LOOP
 FOREACH signature IN ARRAY ARRAY['my_entitled_apps()','my_platform_organizations()',
 'my_platform_locations(uuid)','my_platform_context()',
 'set_platform_context(uuid,uuid,text,text,text,text,jsonb)','platform_mark_notification_read(uuid)'] LOOP
 EXECUTE 'REVOKE ALL ON FUNCTION '||s||'.'||signature||' FROM PUBLIC,anon,authenticated';
 EXECUTE 'GRANT EXECUTE ON FUNCTION '||s||'.'||signature||' TO authenticated';
 END LOOP; END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
