CREATE TABLE tj_private.microsoft_credentials(connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),organization_id uuid NOT NULL REFERENCES tj.organizations(id),secret_id uuid UNIQUE NOT NULL REFERENCES vault.secrets(id));
CREATE INDEX microsoft_credentials_org_idx ON tj_private.microsoft_credentials(organization_id);
ALTER TABLE tj_private.microsoft_credentials ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.microsoft_credentials FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE tj_private.microsoft_oauth_review(connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),organization_id uuid NOT NULL REFERENCES tj.organizations(id),tenant_id uuid NOT NULL,approved_by uuid NOT NULL REFERENCES tj.profiles(id),expires_at timestamptz NOT NULL);
CREATE INDEX microsoft_oauth_review_org_idx ON tj_private.microsoft_oauth_review(organization_id);
CREATE INDEX microsoft_oauth_review_actor_idx ON tj_private.microsoft_oauth_review(approved_by);
ALTER TABLE tj_private.microsoft_oauth_review ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.microsoft_oauth_review FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE tj_private.microsoft_oauth_sessions(state_hash text PRIMARY KEY CHECK(state_hash~'^[0-9a-f]{64}$'),organization_id uuid NOT NULL REFERENCES tj.organizations(id),connection_id uuid NOT NULL REFERENCES tj.platform_connector_connections(id),actor uuid NOT NULL REFERENCES tj.profiles(id),native_user uuid NOT NULL REFERENCES auth.users(id),tenant_id uuid NOT NULL,nonce text NOT NULL,verifier_secret uuid UNIQUE NOT NULL REFERENCES vault.secrets(id),client_id uuid NOT NULL,redirect_uri text NOT NULL,return_url text NOT NULL,connection_version timestamptz NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes',claimed_at timestamptz,completed_at timestamptz);
CREATE INDEX microsoft_oauth_sessions_org_idx ON tj_private.microsoft_oauth_sessions(organization_id);
CREATE INDEX microsoft_oauth_sessions_conn_idx ON tj_private.microsoft_oauth_sessions(connection_id);
CREATE INDEX microsoft_oauth_sessions_actor_idx ON tj_private.microsoft_oauth_sessions(actor);
CREATE INDEX microsoft_oauth_sessions_native_idx ON tj_private.microsoft_oauth_sessions(native_user);
ALTER TABLE tj_private.microsoft_oauth_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.microsoft_oauth_sessions FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.microsoft_connection(p_connection uuid,p_actor uuid) RETURNS tj.platform_connector_connections LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c tj.platform_connector_connections%rowtype;BEGIN
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=p_connection FOR UPDATE;
 IF NOT FOUND OR p_actor IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=c.organization_id AND m.user_id=p_actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connectors pc JOIN tj.platform_connector_variants v ON v.connector_id=pc.id AND v.id=c.variant_id WHERE pc.id=c.connector_id AND pc.key='microsoft_dynamics_365' AND v.key='business_central') THEN RAISE EXCEPTION 'unsupported_variant' USING ERRCODE='22023';END IF;
 IF c.status IN('paused','disconnected') THEN RAISE EXCEPTION 'connection_paused' USING ERRCODE='40001';END IF;
 IF c.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=c.store_id AND l.organization_id=c.organization_id AND l.is_active) THEN RAISE EXCEPTION 'invalid_store' USING ERRCODE='42501';END IF;
 RETURN c;
END $$;
REVOKE ALL ON FUNCTION tj_private.microsoft_connection(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.microsoft_begin(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c tj.platform_connector_connections%rowtype;actor uuid:=tj_private.current_source_user_id();tenant uuid;sid uuid;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>10000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('connection_id','state_hash','nonce','verifier','client_id','redirect_uri','return_url')) OR coalesce(p_body->>'state_hash','')!~'^[0-9a-f]{64}$' OR coalesce(p_body->>'nonce','')!~'^[0-9a-f]{64}$' OR coalesce(p_body->>'verifier','')!~'^[0-9a-f]{64}$' OR length(coalesce(p_body->>'redirect_uri','')) NOT BETWEEN 20 AND 2048 OR length(coalesce(p_body->>'return_url','')) NOT BETWEEN 10 AND 2048 OR p_body->>'redirect_uri'!~'^https://' OR p_body->>'return_url'!~'^https://' THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 c:=tj_private.microsoft_connection((p_body->>'connection_id')::uuid,actor);
 SELECT r.tenant_id INTO tenant FROM tj_private.microsoft_oauth_review r JOIN tj.organization_members m ON m.user_id=r.approved_by AND m.organization_id=r.organization_id WHERE r.connection_id=c.id AND r.organization_id=c.organization_id AND r.expires_at>clock_timestamp() AND m.status='active' AND m.role IN('owner','admin','super_admin');
 IF tenant IS NULL THEN RAISE EXCEPTION 'destination_tenant_review_required' USING ERRCODE='40001';END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_sync_jobs WHERE connection_id=c.id AND status IN('queued','running')) THEN RAISE EXCEPTION 'connection_busy' USING ERRCODE='40001';END IF;
 IF (SELECT count(*) FROM tj_private.microsoft_oauth_sessions WHERE connection_id=c.id AND created_at>clock_timestamp()-interval '10 minutes')>=10 THEN RAISE EXCEPTION 'authorization_rate_limit' USING ERRCODE='54000';END IF;
 -- Bounded pending states; starting again invalidates the previous attempt.
 UPDATE tj_private.microsoft_oauth_sessions SET expires_at=clock_timestamp() WHERE connection_id=c.id AND completed_at IS NULL;
 sid:=vault.create_secret(p_body->>'verifier','aiq_ms_pkce_'||gen_random_uuid()::text,'Microsoft PKCE verifier');
 INSERT INTO tj_private.microsoft_oauth_sessions(state_hash,organization_id,connection_id,actor,native_user,tenant_id,nonce,verifier_secret,client_id,redirect_uri,return_url,connection_version)
 VALUES(p_body->>'state_hash',c.organization_id,c.id,actor,auth.uid(),tenant,p_body->>'nonce',sid,(p_body->>'client_id')::uuid,p_body->>'redirect_uri',p_body->>'return_url',c.updated_at);
 RETURN jsonb_build_object('tenant_id',tenant);
END $$;
REVOKE ALL ON FUNCTION tj_private.microsoft_begin(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.microsoft_begin(jsonb) TO authenticated;
CREATE FUNCTION public.tj_microsoft_oauth_begin(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.microsoft_begin(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_microsoft_oauth_begin(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_microsoft_oauth_begin(jsonb) TO authenticated;

CREATE FUNCTION tj_private.microsoft_actor(p_native uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT CASE WHEN count(*)=1 THEN min(m.source_user_id::text)::uuid END FROM tj.source_user_identity_map m JOIN tj.source_auth_users s ON s.id=m.source_user_id JOIN auth.users u ON u.id=m.target_user_id WHERE m.target_user_id=p_native AND m.identity_verified AND m.mapping_status IN('approved_map','approved_create','approved_invite') AND m.approved_at IS NOT NULL AND nullif(btrim(m.approved_by),'') IS NOT NULL AND m.activation_status='activated' AND m.activated_at IS NOT NULL AND s.deleted_at IS NULL AND u.deleted_at IS NULL AND (s.banned_until IS NULL OR s.banned_until<=now()) AND (u.banned_until IS NULL OR u.banned_until<=now()) AND NOT coalesce(s.is_anonymous,false) AND NOT coalesce(u.is_anonymous,false);
$$;
REVOKE ALL ON FUNCTION tj_private.microsoft_actor(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj_private.microsoft_context(p_hash text,p_native uuid DEFAULT NULL,p_claim boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s tj_private.microsoft_oauth_sessions%rowtype;c tj.platform_connector_connections%rowtype;actor uuid;verifier text;BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM tj_private.microsoft_oauth_sessions WHERE state_hash=p_hash;
 IF NOT FOUND OR s.expires_at<=clock_timestamp() OR s.claimed_at IS NOT NULL OR s.completed_at IS NOT NULL THEN RAISE EXCEPTION 'state_expired_or_used' USING ERRCODE='40001';END IF;
 actor:=tj_private.microsoft_actor(s.native_user);
 IF actor IS DISTINCT FROM s.actor OR p_claim AND p_native IS DISTINCT FROM s.native_user THEN RAISE EXCEPTION 'state_actor_denied' USING ERRCODE='42501';END IF;
 c:=tj_private.microsoft_connection(s.connection_id,actor);
 SELECT * INTO s FROM tj_private.microsoft_oauth_sessions WHERE state_hash=p_hash FOR UPDATE;
 IF s.expires_at<=clock_timestamp() OR s.completed_at IS NOT NULL THEN RAISE EXCEPTION 'state_expired_or_used' USING ERRCODE='40001';END IF;
 IF c.updated_at IS DISTINCT FROM s.connection_version OR c.organization_id<>s.organization_id OR NOT EXISTS(SELECT 1 FROM tj_private.microsoft_oauth_review r JOIN tj.organization_members m ON m.user_id=r.approved_by AND m.organization_id=r.organization_id WHERE r.connection_id=c.id AND r.organization_id=c.organization_id AND r.tenant_id=s.tenant_id AND r.expires_at>clock_timestamp() AND m.status='active' AND m.role IN('owner','admin','super_admin')) THEN RAISE EXCEPTION 'connection_or_review_changed' USING ERRCODE='40001';END IF;
 IF p_claim THEN
  IF s.claimed_at IS NOT NULL THEN RAISE EXCEPTION 'state_already_claimed' USING ERRCODE='40001';END IF;
  UPDATE tj_private.microsoft_oauth_sessions SET claimed_at=clock_timestamp() WHERE state_hash=p_hash;
  SELECT decrypted_secret INTO verifier FROM vault.decrypted_secrets WHERE id=s.verifier_secret;
  IF verifier IS NULL THEN RAISE EXCEPTION 'verifier_missing' USING ERRCODE='40001';END IF;
 END IF;
 RETURN jsonb_build_object('connection_id',s.connection_id,'tenant_id',s.tenant_id,'nonce',CASE WHEN p_claim THEN s.nonce END,'verifier',verifier,'client_id',s.client_id,'redirect_uri',s.redirect_uri,'return_url',s.return_url);
END $$;
REVOKE ALL ON FUNCTION tj_private.microsoft_context(text,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.microsoft_context(text,uuid,boolean) TO service_role;
CREATE FUNCTION public.aiq_microsoft_oauth_context(p_hash text,p_native uuid DEFAULT NULL,p_claim boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.microsoft_context(p_hash,p_native,p_claim);$$;
REVOKE ALL ON FUNCTION public.aiq_microsoft_oauth_context(text,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_microsoft_oauth_context(text,uuid,boolean) TO service_role;

CREATE FUNCTION tj_private.microsoft_finish(p_hash text,p_native uuid,p_credential jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE s tj_private.microsoft_oauth_sessions%rowtype;c tj.platform_connector_connections%rowtype;actor uuid;sid uuid;BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM tj_private.microsoft_oauth_sessions WHERE state_hash=p_hash;
 IF NOT FOUND OR s.native_user IS DISTINCT FROM p_native OR s.claimed_at IS NULL OR s.completed_at IS NOT NULL OR s.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'state_expired_or_used' USING ERRCODE='40001';END IF;
 actor:=tj_private.microsoft_actor(p_native);
 IF actor IS DISTINCT FROM s.actor THEN RAISE EXCEPTION 'actor_changed' USING ERRCODE='42501';END IF;
 c:=tj_private.microsoft_connection(s.connection_id,actor);
 SELECT * INTO s FROM tj_private.microsoft_oauth_sessions WHERE state_hash=p_hash FOR UPDATE;
 IF s.expires_at<=clock_timestamp() OR s.completed_at IS NOT NULL THEN RAISE EXCEPTION 'state_expired_or_used' USING ERRCODE='40001';END IF;
 IF c.updated_at IS DISTINCT FROM s.connection_version OR c.organization_id<>s.organization_id OR NOT EXISTS(SELECT 1 FROM tj_private.microsoft_oauth_review r JOIN tj.organization_members m ON m.user_id=r.approved_by AND m.organization_id=r.organization_id WHERE r.connection_id=c.id AND r.organization_id=c.organization_id AND r.tenant_id=s.tenant_id AND r.expires_at>clock_timestamp() AND m.status='active' AND m.role IN('owner','admin','super_admin')) OR EXISTS(SELECT 1 FROM tj.platform_sync_jobs WHERE connection_id=c.id AND status IN('queued','running')) THEN RAISE EXCEPTION 'configuration_or_review_changed' USING ERRCODE='40001';END IF;
 IF p_credential IS NULL OR jsonb_typeof(p_credential)<>'object' OR octet_length(p_credential::text)>64000 OR p_credential->>'tenant_id' IS DISTINCT FROM s.tenant_id::text OR p_credential->>'token_type' IS DISTINCT FROM 'Bearer' OR length(coalesce(p_credential->>'access_token','')) NOT BETWEEN 1 AND 16000 OR length(coalesce(p_credential->>'refresh_token','')) NOT BETWEEN 1 AND 16000 OR length(coalesce(p_credential->>'subject','')) NOT BETWEEN 1 AND 300 THEN RAISE EXCEPTION 'invalid_verified_credential' USING ERRCODE='22023';END IF;
 SELECT secret_id INTO sid FROM tj_private.microsoft_credentials WHERE connection_id=c.id AND organization_id=c.organization_id;
 IF sid IS NULL THEN sid:=vault.create_secret(p_credential::text,'aiq_us_microsoft_'||c.id::text,'Verified Microsoft Business Central credential');INSERT INTO tj_private.microsoft_credentials VALUES(c.id,c.organization_id,sid);
 ELSE PERFORM vault.update_secret(sid,p_credential::text);END IF;
 UPDATE tj.platform_connector_connections SET credential_ref=sid::text,auth_status='valid',status='pending',settings=coalesce(settings,'{}')||'{"destination_connection_verified":false}',auth_metadata=jsonb_build_object('provider','microsoft','variant','business_central','tenant_id',s.tenant_id,'identity_connected',true,'api_consent_pending',false,'scope',p_credential->>'scope','connected_at',clock_timestamp()),last_error=NULL,updated_at=clock_timestamp() WHERE id=c.id;
 UPDATE tj_private.microsoft_oauth_sessions SET completed_at=clock_timestamp() WHERE state_hash=p_hash;
 RETURN jsonb_build_object('ok',true,'connection_id',c.id,'status','pending','requires_api_verification',true);
END $$;
REVOKE ALL ON FUNCTION tj_private.microsoft_finish(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.microsoft_finish(text,uuid,jsonb) TO service_role;
CREATE FUNCTION public.aiq_microsoft_oauth_finish(p_hash text,p_native uuid,p_credential jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.microsoft_finish(p_hash,p_native,p_credential);$$;
REVOKE ALL ON FUNCTION public.aiq_microsoft_oauth_finish(text,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_microsoft_oauth_finish(text,uuid,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
