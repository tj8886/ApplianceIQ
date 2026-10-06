-- Scoped setup only. External import stays blocked until its ingestion and bridge contracts migrate.
CREATE TABLE tj_private.xstore_credentials(connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),organization_id uuid NOT NULL REFERENCES tj.organizations(id),secret_id uuid UNIQUE NOT NULL REFERENCES vault.secrets(id));
CREATE INDEX xstore_credentials_org_idx ON tj_private.xstore_credentials(organization_id);
ALTER TABLE tj_private.xstore_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.xstore_credentials FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.xstore_connection(p_connection_id uuid,p_actor uuid) RETURNS tj.platform_connector_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE conn tj.platform_connector_connections%rowtype;BEGIN
 SELECT * INTO conn FROM tj.platform_connector_connections WHERE id=p_connection_id FOR UPDATE;
 IF NOT FOUND OR p_actor IS NULL THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=conn.organization_id AND m.user_id=p_actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connectors c WHERE c.id=conn.connector_id AND c.key='oracle_xstore') THEN RAISE EXCEPTION 'not_xstore_connection' USING ERRCODE='22023';END IF;
 IF conn.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=conn.store_id AND l.organization_id=conn.organization_id AND l.is_active) THEN RAISE EXCEPTION 'invalid_connection_store' USING ERRCODE='42501';END IF;
 RETURN conn;
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_connection(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.xstore_setup(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE conn tj.platform_connector_connections%rowtype;act text:=coalesce(p_body->>'action','status'); cfg jsonb;credential jsonb;sid uuid;path text;resource text;base text;token text;kh text;sh text;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('action','connection_id','base_url','endpoints','sync_type','resources','token_url','client_id','client_secret','scope','tenancy_id','org_id','api_version')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 conn:=tj_private.xstore_connection(nullif(p_body->>'connection_id','')::uuid,tj_private.current_source_user_id());cfg:=coalesce(conn.settings->'xstore_api','{}');
 IF act='configure' THEN
  IF conn.status IN('paused','disconnected') OR EXISTS(SELECT 1 FROM tj.platform_sync_jobs j WHERE j.connection_id=conn.id AND j.status IN('queued','running')) THEN RAISE EXCEPTION 'connection_busy_or_paused' USING ERRCODE='40001';END IF;
  base:=coalesce(p_body->>'base_url',cfg->>'base_url');
  IF base IS NULL OR length(base)>2048 OR base!~'^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(/[A-Za-z0-9._~/-]*)?$' OR base~'\.\.' THEN RAISE EXCEPTION 'https_base_url_required' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(p_body->'endpoints') IS DISTINCT FROM 'object' OR p_body->'endpoints'='{}'::jsonb THEN RAISE EXCEPTION 'endpoints_required' USING ERRCODE='22023';END IF;
  FOR resource,path IN SELECT key,value FROM jsonb_each_text(p_body->'endpoints') LOOP
   IF resource NOT IN('customers','products','employees','locations','inventory','prices','transactions') OR path IS NULL OR length(path)>500 OR path!~'^/?[A-Za-z0-9_/-]+$' OR path~'//' THEN RAISE EXCEPTION 'relative_endpoint_required' USING ERRCODE='22023';END IF;
  END LOOP;
  token:=coalesce(p_body->>'token_url',cfg->>'token_url');
  IF token IS NULL OR length(token)>2048 OR token!~'^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(/[A-Za-z0-9._~/-]*)?$' OR token~'\.\.' THEN RAISE EXCEPTION 'https_token_url_required' USING ERRCODE='22023';END IF;
  IF EXISTS(SELECT 1 FROM jsonb_each(p_body) kv WHERE kv.key IN('tenancy_id','org_id','api_version') AND (jsonb_typeof(kv.value)<>'string' OR length(kv.value#>>'{}')>200 OR (kv.value#>>'{}')~'[\r\n]')) THEN RAISE EXCEPTION 'invalid_context_fields' USING ERRCODE='22023';END IF;
  credential:=CASE WHEN coalesce(p_body->>'client_id','')<>'' OR coalesce(p_body->>'client_secret','')<>'' THEN jsonb_build_object('client_id',p_body->>'client_id','client_secret',p_body->>'client_secret','scope',p_body->>'scope') END;

  IF credential IS NOT NULL AND credential<>'null'::jsonb THEN
   IF length(coalesce(credential->>'client_id','')) NOT BETWEEN 1 AND 4096 OR length(coalesce(credential->>'client_secret','')) NOT BETWEEN 1 AND 4096 OR length(coalesce(credential->>'scope','')) NOT BETWEEN 1 AND 2000 OR jsonb_typeof(credential)<>'object' OR NOT EXISTS(SELECT 1 FROM jsonb_each_text(credential) WHERE coalesce(value,'')<>'') OR EXISTS(SELECT 1 FROM jsonb_each(credential)kv WHERE kv.key NOT IN('client_id','client_secret','scope') OR jsonb_typeof(kv.value)<>'string' OR length(kv.value#>>'{}')>4096 OR (kv.value#>>'{}')~'[\r\n]') THEN RAISE EXCEPTION 'invalid_credential' USING ERRCODE='22023';END IF;
   SELECT secret_id INTO sid FROM tj_private.xstore_credentials WHERE connection_id=conn.id AND organization_id=conn.organization_id;
   IF sid IS NULL THEN sid:=vault.create_secret(credential::text,'aiq_us_xstore_'||conn.id::text,'US Oracle Xstore connection credential');INSERT INTO tj_private.xstore_credentials VALUES(conn.id,conn.organization_id,sid);
   ELSE PERFORM vault.update_secret(sid,credential::text);END IF;
  ELSE SELECT secret_id INTO sid FROM tj_private.xstore_credentials WHERE connection_id=conn.id AND organization_id=conn.organization_id;END IF;
  cfg:=jsonb_build_object('base_url',base,'endpoints',p_body->'endpoints','token_url',token,'tenancy_id',p_body->>'tenancy_id','org_id',coalesce(p_body->>'org_id','DEFAULT'),'api_version',p_body->>'api_version','configured_at',clock_timestamp());
  UPDATE tj.platform_connector_connections SET settings=(coalesce(conn.settings,'{}')-'destination_connection_verified')||jsonb_build_object('xstore_api',cfg,'destination_connection_verified',false),credential_ref=sid::text,auth_status='not_configured',status='pending',last_error=NULL,updated_at=clock_timestamp() WHERE id=conn.id;
  RETURN jsonb_build_object('ok',true,'resources',(SELECT jsonb_agg(k) FROM jsonb_object_keys(cfg->'endpoints') k));
 ELSIF act='sync' THEN
  RETURN jsonb_build_object('ok',false,'error','xstore_import_dependencies_pending','dependencies',jsonb_build_array('oracle-xstore-performance-bridge','resumable_xstore_import'));
 ELSIF act NOT IN('status','test') THEN RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';END IF;
 SELECT secret_id INTO sid FROM tj_private.xstore_credentials WHERE connection_id=conn.id AND organization_id=conn.organization_id;
 IF act='test' AND (conn.status IN('paused','disconnected') OR sid IS NULL OR cfg->>'base_url' IS NULL) THEN RAISE EXCEPTION 'xstore_not_configured' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('ok',true,'connection',jsonb_build_object('id',conn.id,'status',conn.status,'auth_status',CASE WHEN sid IS NULL THEN 'not_configured' ELSE conn.auth_status END,'last_sync_at',conn.last_sync_at,'last_success_at',conn.last_success_at),'configuration',jsonb_build_object('base_url',cfg->>'base_url','endpoints',coalesce(cfg->'endpoints','{}'),'token_url',cfg->>'token_url','tenancy_id',cfg->>'tenancy_id','org_id',cfg->>'org_id','api_version',cfg->>'api_version','configured',sid IS NOT NULL AND cfg->>'base_url' IS NOT NULL),'version',conn.updated_at,'sync_ready',false,'dependencies',jsonb_build_array('oracle-xstore-performance-bridge','resumable_xstore_import'));
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_setup(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.xstore_setup(jsonb) TO authenticated;
CREATE FUNCTION public.tj_xstore_setup(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.xstore_setup(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_xstore_setup(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_xstore_setup(jsonb) TO authenticated;
CREATE FUNCTION tj_private.xstore_actor(p_native uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid END FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id JOIN auth.users u ON u.id=m.target_user_id WHERE m.target_user_id=p_native AND m.identity_verified AND m.mapping_status IN('approved_map','approved_create','approved_invite') AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL AND m.activation_status='activated' AND m.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);
$$;
REVOKE ALL ON FUNCTION tj_private.xstore_actor(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.xstore_test_context(p_connection_id uuid,p_native_user uuid,p_version timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;conn tj.platform_connector_connections%rowtype;credential jsonb;BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 actor:=tj_private.xstore_actor(p_native_user);
 conn:=tj_private.xstore_connection(p_connection_id,actor);
 IF conn.updated_at IS DISTINCT FROM p_version OR conn.status IN('paused','disconnected') THEN RAISE EXCEPTION 'configuration_changed' USING ERRCODE='40001';END IF;
 SELECT s.decrypted_secret::jsonb INTO credential FROM tj_private.xstore_credentials c JOIN vault.decrypted_secrets s ON s.id=c.secret_id WHERE c.connection_id=conn.id AND c.organization_id=conn.organization_id AND conn.credential_ref=c.secret_id::text;
 IF credential IS NULL THEN RAISE EXCEPTION 'destination_credential_required' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('configuration',conn.settings->'xstore_api','credential',credential);
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_test_context(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.xstore_test_context(uuid,uuid,timestamptz) TO service_role;
CREATE FUNCTION public.aiq_xstore_test_context(p_connection_id uuid,p_native_user uuid,p_version timestamptz) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.xstore_test_context(p_connection_id,p_native_user,p_version);$$;
REVOKE ALL ON FUNCTION public.aiq_xstore_test_context(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_xstore_test_context(uuid,uuid,timestamptz) TO service_role;
NOTIFY pgrst,'reload schema';
