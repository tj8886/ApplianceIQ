-- Scoped setup only. External import stays blocked until its ingestion and bridge contracts migrate.
CREATE TABLE tj_private.epass_credentials(connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),secret_id uuid UNIQUE NOT NULL REFERENCES vault.secrets(id));
ALTER TABLE tj_private.epass_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.epass_credentials FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.epass_connection(p_connection_id uuid,p_actor uuid) RETURNS tj.platform_connector_connections
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE conn tj.platform_connector_connections%rowtype;BEGIN
 SELECT * INTO conn FROM tj.platform_connector_connections WHERE id=p_connection_id FOR UPDATE;
 IF NOT FOUND OR p_actor IS NULL THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=conn.organization_id AND m.user_id=p_actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connectors c WHERE c.id=conn.connector_id AND c.key='epass') THEN RAISE EXCEPTION 'not_epass_connection' USING ERRCODE='22023';END IF;
 IF conn.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=conn.store_id AND l.organization_id=conn.organization_id AND l.is_active) THEN RAISE EXCEPTION 'invalid_connection_store' USING ERRCODE='42501';END IF;
 RETURN conn;
END $$;
REVOKE ALL ON FUNCTION tj_private.epass_connection(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.epass_setup(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE conn tj.platform_connector_connections%rowtype;act text:=coalesce(p_body->>'action','status'); cfg jsonb;credential jsonb;sid uuid;path text;resource text;base text;kh text;sh text;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('action','connection_id','base_url','endpoints','credential','api_key_header','api_secret_header','sync_type','resources')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 conn:=tj_private.epass_connection(nullif(p_body->>'connection_id','')::uuid,tj_private.current_source_user_id());cfg:=coalesce(conn.settings->'epass_api','{}');
 IF act='configure' THEN
  IF conn.status IN('paused','disconnected') OR EXISTS(SELECT 1 FROM tj.platform_sync_jobs j WHERE j.connection_id=conn.id AND j.status IN('queued','running')) THEN RAISE EXCEPTION 'connection_busy_or_paused' USING ERRCODE='40001';END IF;
  base:=coalesce(p_body->>'base_url',cfg->>'base_url');
  IF base IS NULL OR length(base)>2048 OR base!~'^https://[a-z0-9]([a-z0-9.-]*[a-z0-9])?(/[A-Za-z0-9._~/-]*)?$' OR base~'\.\.' THEN RAISE EXCEPTION 'https_base_url_required' USING ERRCODE='22023';END IF;
  IF jsonb_typeof(p_body->'endpoints') IS DISTINCT FROM 'object' OR p_body->'endpoints'='{}'::jsonb THEN RAISE EXCEPTION 'endpoints_required' USING ERRCODE='22023';END IF;
  FOR resource,path IN SELECT key,value FROM jsonb_each_text(p_body->'endpoints') LOOP
   IF resource NOT IN('customers','invoices','models','service','salespeople','locations') OR path IS NULL OR length(path)>500 OR path!~'^/?[A-Za-z0-9_/-]+$' OR path~'//' THEN RAISE EXCEPTION 'relative_endpoint_required' USING ERRCODE='22023';END IF;
  END LOOP;
  kh:=coalesce(p_body->>'api_key_header',cfg->>'api_key_header','X-API-Key');sh:=coalesce(p_body->>'api_secret_header',cfg->>'api_secret_header','X-API-Secret');
  IF kh!~'^[A-Za-z][A-Za-z0-9-]{0,63}$' OR sh!~'^[A-Za-z][A-Za-z0-9-]{0,63}$' OR lower(kh)=lower(sh) OR lower(kh) IN('host','authorization','cookie','accept','content-type','connection','proxy-authorization') OR lower(sh) IN('host','authorization','cookie','accept','content-type','connection','proxy-authorization') THEN RAISE EXCEPTION 'invalid_credential_header' USING ERRCODE='22023';END IF;
  credential:=p_body->'credential';
  IF credential IS NOT NULL AND credential<>'null'::jsonb THEN
   IF jsonb_typeof(credential)<>'object' OR NOT EXISTS(SELECT 1 FROM jsonb_each_text(credential) WHERE coalesce(value,'')<>'') OR EXISTS(SELECT 1 FROM jsonb_each(credential)kv WHERE kv.key NOT IN('api_key','api_secret','token') OR jsonb_typeof(kv.value)<>'string' OR length(kv.value#>>'{}')>4096 OR (kv.value#>>'{}')~'[\r\n]') THEN RAISE EXCEPTION 'invalid_credential' USING ERRCODE='22023';END IF;
   SELECT secret_id INTO sid FROM tj_private.epass_credentials WHERE connection_id=conn.id;
   IF sid IS NULL THEN sid:=vault.create_secret(credential::text,'aiq_us_epass_'||conn.id::text,'US ePASS connection credential');INSERT INTO tj_private.epass_credentials VALUES(conn.id,sid);
   ELSE PERFORM vault.update_secret(sid,credential::text);END IF;
  ELSE SELECT secret_id INTO sid FROM tj_private.epass_credentials WHERE connection_id=conn.id;END IF;
  cfg:=jsonb_build_object('base_url',base,'endpoints',p_body->'endpoints','api_key_header',kh,'api_secret_header',sh,'configured_at',clock_timestamp());
  UPDATE tj.platform_connector_connections SET settings=(coalesce(conn.settings,'{}')-'destination_connection_verified')||jsonb_build_object('epass_api',cfg,'destination_connection_verified',false),credential_ref=sid::text,auth_status='not_configured',status='pending',last_error=NULL,updated_at=clock_timestamp() WHERE id=conn.id;
  RETURN jsonb_build_object('ok',true,'resources',(SELECT jsonb_agg(k) FROM jsonb_object_keys(cfg->'endpoints') k));
 ELSIF act='sync' THEN
  RETURN jsonb_build_object('ok',false,'error','epass_import_dependencies_pending','dependencies',jsonb_build_array('connector-ingest','epass-performance-bridge'));
 ELSIF act NOT IN('status','test') THEN RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';END IF;
 SELECT secret_id INTO sid FROM tj_private.epass_credentials WHERE connection_id=conn.id;
 IF act='test' AND (conn.status IN('paused','disconnected') OR sid IS NULL OR cfg->>'base_url' IS NULL) THEN RAISE EXCEPTION 'epass_not_configured' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('ok',true,'connection',jsonb_build_object('id',conn.id,'status',conn.status,'auth_status',CASE WHEN sid IS NULL THEN 'not_configured' ELSE conn.auth_status END,'last_sync_at',conn.last_sync_at,'last_success_at',conn.last_success_at),'configuration',jsonb_build_object('base_url',cfg->>'base_url','endpoints',coalesce(cfg->'endpoints','{}'),'api_key_header',cfg->>'api_key_header','api_secret_header',cfg->>'api_secret_header','configured',sid IS NOT NULL AND cfg->>'base_url' IS NOT NULL),'version',conn.updated_at,'sync_ready',false,'dependencies',jsonb_build_array('connector-ingest','epass-performance-bridge'));
END $$;
REVOKE ALL ON FUNCTION tj_private.epass_setup(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.epass_setup(jsonb) TO authenticated;
CREATE FUNCTION public.tj_epass_setup(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.epass_setup(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_epass_setup(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_epass_setup(jsonb) TO authenticated;
CREATE FUNCTION tj_private.epass_test_context(p_connection_id uuid,p_native_user uuid,p_version timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;conn tj.platform_connector_connections%rowtype;credential jsonb;BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 SELECT source_user_id INTO actor FROM tj.source_user_identity_map WHERE target_user_id=p_native_user AND activation_status='activated';
 conn:=tj_private.epass_connection(p_connection_id,actor);
 IF conn.updated_at IS DISTINCT FROM p_version OR conn.status IN('paused','disconnected') THEN RAISE EXCEPTION 'configuration_changed' USING ERRCODE='40001';END IF;
 SELECT s.decrypted_secret::jsonb INTO credential FROM tj_private.epass_credentials c JOIN vault.decrypted_secrets s ON s.id=c.secret_id WHERE c.connection_id=conn.id AND conn.credential_ref=c.secret_id::text;
 IF credential IS NULL THEN RAISE EXCEPTION 'destination_credential_required' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('configuration',conn.settings->'epass_api','credential',credential);
END $$;
REVOKE ALL ON FUNCTION tj_private.epass_test_context(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.epass_test_context(uuid,uuid,timestamptz) TO service_role;
CREATE FUNCTION public.aiq_epass_test_context(p_connection_id uuid,p_native_user uuid,p_version timestamptz) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.epass_test_context(p_connection_id,p_native_user,p_version);$$;
REVOKE ALL ON FUNCTION public.aiq_epass_test_context(uuid,uuid,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_epass_test_context(uuid,uuid,timestamptz) TO service_role;
NOTIFY pgrst,'reload schema';
