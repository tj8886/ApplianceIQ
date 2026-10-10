-- Caller-authenticated broker. No connector credentials, external calls or worker activation.
CREATE FUNCTION tj_private.connector_runtime(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id(); org uuid; member_role text; action text:=coalesce(p_body->>'action','catalog');
 connector tj.platform_connectors%rowtype; variant tj.platform_connector_variants%rowtype;
 conn tj.platform_connector_connections%rowtype; job tj.platform_sync_jobs%rowtype; settings jsonb; store uuid; result jsonb;
BEGIN
 IF actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'organization_access_denied' USING ERRCODE='42501';END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 THEN RAISE EXCEPTION 'invalid_body' USING ERRCODE='22023';END IF;
 IF action='catalog' THEN
  SELECT jsonb_build_object('connectors',coalesce(jsonb_agg(jsonb_build_object(
   'id',c.id,'key',c.key,'name',c.name,'vendor_name',c.vendor_name,'category',c.category,'description',c.description,'auth_type',c.auth_type,'status',c.status,
   'supports_webhooks',c.supports_webhooks,'supports_incremental_sync',c.supports_incremental_sync,'partner_required',c.partner_required,'capabilities',c.capabilities,'documentation_url',c.documentation_url,
   'onboarding_supported',EXISTS(SELECT 1 FROM tj.platform_connector_onboarding_profiles p WHERE p.connector_id=c.id AND p.variant_id IS NULL AND p.is_active),
   'variants',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',v.id,'connector_id',v.connector_id,'key',v.key,'name',v.name,'description',v.description,'api_family',v.api_family,'auth_type',v.auth_type,'status',v.status,'capabilities',v.capabilities,
   'onboarding_supported',EXISTS(SELECT 1 FROM tj.platform_connector_onboarding_profiles p WHERE p.connector_id=c.id AND p.variant_id=v.id AND p.is_active)) ORDER BY v.name),'[]'::jsonb) FROM tj.platform_connector_variants v WHERE v.connector_id=c.id)) ORDER BY c.name),'[]'::jsonb)) INTO result FROM tj.platform_connectors c;
  RETURN result;
 END IF;
 org:=nullif(p_body->>'organization_id','')::uuid;
 SELECT m.role INTO member_role FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL;
 IF member_role IS NULL THEN RAISE EXCEPTION 'organization_access_denied' USING ERRCODE='42501';END IF;
 IF action='connections' THEN
  SELECT jsonb_build_object('connections',coalesce(jsonb_agg(jsonb_build_object('id',c.id,'organization_id',c.organization_id,'store_id',c.store_id,'connector_id',c.connector_id,'variant_id',c.variant_id,'external_account_id',c.external_account_id,'display_name',c.display_name,'status',c.status,'auth_status',c.auth_status,'last_sync_at',c.last_sync_at,'last_success_at',c.last_success_at,'created_at',c.created_at,'updated_at',c.updated_at) ORDER BY c.created_at DESC),'[]'::jsonb)) INTO result FROM tj.platform_connector_connections c WHERE c.organization_id=org;
  RETURN result;
 END IF;
 IF member_role NOT IN ('owner','admin','super_admin') THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF action='prepare_connection' THEN
  SELECT * INTO connector FROM tj.platform_connectors WHERE key=p_body->>'connector_key';
  IF NOT FOUND THEN RAISE EXCEPTION 'connector_not_found' USING ERRCODE='P0002';END IF;
  IF nullif(p_body->>'variant_key','') IS NOT NULL THEN
   SELECT * INTO variant FROM tj.platform_connector_variants WHERE connector_id=connector.id AND key=p_body->>'variant_key';
   IF NOT FOUND THEN RAISE EXCEPTION 'connector_variant_not_found' USING ERRCODE='P0002';END IF;
  END IF;
  settings:=coalesce(p_body->'settings','{}'::jsonb);
  IF jsonb_typeof(settings)<>'object' OR octet_length(settings::text)>4096 OR EXISTS(SELECT 1 FROM jsonb_object_keys(settings) k WHERE k NOT IN ('source','market','timezone','entity_types','sync_interval')) THEN RAISE EXCEPTION 'unsupported_settings_use_credentials_configuration' USING ERRCODE='22023';END IF;
  store:=nullif(p_body->>'store_id','')::uuid;
  IF store IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=store AND organization_id=org AND is_active) THEN RAISE EXCEPTION 'store_access_denied' USING ERRCODE='42501';END IF;
  IF length(coalesce(p_body->>'display_name',variant.name,connector.name))>160 THEN RAISE EXCEPTION 'display_name_too_long' USING ERRCODE='22023';END IF;
  INSERT INTO tj.platform_connector_connections(organization_id,store_id,connector_id,variant_id,display_name,status,auth_status,settings,created_by)
   VALUES(org,store,connector.id,variant.id,coalesce(p_body->>'display_name',variant.name,connector.name),'pending','not_configured',settings,actor) RETURNING * INTO conn;
  RETURN jsonb_build_object('connection',jsonb_build_object('id',conn.id,'organization_id',org,'store_id',store,'connector_id',connector.id,'variant_id',variant.id,'display_name',conn.display_name,'status',conn.status,'auth_status',conn.auth_status,'settings',settings,'created_at',conn.created_at),
   'connector',jsonb_build_object('id',connector.id,'key',connector.key,'name',connector.name,'auth_type',connector.auth_type,'status',connector.status),
   'variant',CASE WHEN variant.id IS NULL THEN NULL ELSE jsonb_build_object('id',variant.id,'key',variant.key,'name',variant.name,'api_family',variant.api_family,'auth_type',variant.auth_type,'status',variant.status) END,
   'onboarding_supported',EXISTS(SELECT 1 FROM tj.platform_connector_onboarding_profiles p WHERE p.connector_id=connector.id AND p.variant_id IS NOT DISTINCT FROM variant.id AND p.is_active),
   'next_step',CASE WHEN coalesce(variant.auth_type,connector.auth_type)='oauth2' THEN 'oauth_authorization' ELSE 'credentials_configuration' END);
 ELSIF action='queue_sync' THEN
  IF coalesce(p_body->>'sync_type','incremental') NOT IN ('incremental','full','initial') OR coalesce(p_body->>'direction','inbound') NOT IN ('inbound','outbound','bidirectional') THEN RAISE EXCEPTION 'invalid_sync_request' USING ERRCODE='22023';END IF;
  SELECT * INTO conn FROM tj.platform_connector_connections WHERE id=nullif(p_body->>'connection_id','')::uuid AND organization_id=org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'connection_not_found' USING ERRCODE='P0002';END IF;
  IF conn.status IN ('paused','disconnected') THEN RAISE EXCEPTION 'connection_not_ready' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM tj.platform_sync_jobs WHERE connection_id=conn.id AND status IN ('queued','running')) THEN RAISE EXCEPTION 'sync_already_pending' USING ERRCODE='40001';END IF;
  INSERT INTO tj.platform_sync_jobs(connection_id,job_type,direction,status,requested_by) VALUES(conn.id,coalesce(p_body->>'sync_type','incremental'),coalesce(p_body->>'direction','inbound'),'queued',actor) RETURNING * INTO job;
  RETURN jsonb_build_object('job',jsonb_build_object('id',job.id,'connection_id',job.connection_id,'job_type',job.job_type,'direction',job.direction,'status',job.status,'requested_by',job.requested_by,'created_at',job.created_at));
 END IF;
 RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';
END $$;
REVOKE ALL ON FUNCTION tj_private.connector_runtime(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.connector_runtime(jsonb) TO authenticated;
CREATE FUNCTION public.tj_connector_runtime(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.connector_runtime(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_connector_runtime(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_connector_runtime(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
