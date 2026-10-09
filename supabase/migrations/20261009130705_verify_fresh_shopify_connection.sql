CREATE TABLE tj_private.shopify_verification_sessions(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES tj.organizations(id),connection_id uuid NOT NULL REFERENCES tj.platform_connector_connections(id),native_user uuid NOT NULL REFERENCES auth.users(id),secret_id uuid NOT NULL REFERENCES vault.secrets(id),secret_updated_at timestamptz NOT NULL,connection_version timestamptz NOT NULL,shop_domain text NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '2 minutes',completed_at timestamptz
);
CREATE INDEX shopify_verification_sessions_org_idx ON tj_private.shopify_verification_sessions(organization_id);
CREATE INDEX shopify_verification_sessions_conn_idx ON tj_private.shopify_verification_sessions(connection_id);
CREATE INDEX shopify_verification_sessions_native_idx ON tj_private.shopify_verification_sessions(native_user);
CREATE INDEX shopify_verification_sessions_secret_idx ON tj_private.shopify_verification_sessions(secret_id);
CREATE TABLE tj_private.shopify_verified_connections(
 connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),organization_id uuid NOT NULL REFERENCES tj.organizations(id),secret_id uuid NOT NULL REFERENCES vault.secrets(id),secret_updated_at timestamptz NOT NULL,connection_version timestamptz NOT NULL,shop_id text NOT NULL,shop_domain text NOT NULL,currency text NOT NULL,scopes jsonb NOT NULL,verified_at timestamptz NOT NULL DEFAULT clock_timestamp(),expires_at timestamptz NOT NULL
);
CREATE INDEX shopify_verified_connections_org_idx ON tj_private.shopify_verified_connections(organization_id);
CREATE INDEX shopify_verified_connections_secret_idx ON tj_private.shopify_verified_connections(secret_id);
ALTER TABLE tj_private.shopify_verification_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj_private.shopify_verified_connections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.shopify_verification_sessions,tj_private.shopify_verified_connections FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.shopify_verified_connections IS 'Short-lived read-only API identity/currency/scope evidence tied to a fresh OAuth Vault version and connection version; not activation or permission to create drafts. Private, no client access.';
CREATE FUNCTION tj_private.shopify_verify_begin(p_native uuid,p_connection uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;c tj.platform_connector_connections%rowtype;credential tj_private.shopify_credentials%rowtype;secret_row record;tokens jsonb;session_id uuid;
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 actor:=tj_private.microsoft_actor(p_native);IF actor IS NULL THEN RAISE EXCEPTION 'identity_required' USING ERRCODE='42501';END IF;
 c:=tj_private.shopify_connection(p_connection,actor);
 SELECT * INTO credential FROM tj_private.shopify_credentials WHERE connection_id=c.id AND organization_id=c.organization_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'fresh_authorization_required' USING ERRCODE='55000';END IF;
 IF credential.shop_domain!~'^[a-z0-9][a-z0-9-]{0,62}\.myshopify\.com$' OR credential.shop_domain IS DISTINCT FROM c.external_account_id OR c.credential_ref IS DISTINCT FROM credential.secret_id::text THEN RAISE EXCEPTION 'credential_binding_changed' USING ERRCODE='40001';END IF;
 IF (SELECT count(*) FROM tj_private.shopify_verification_sessions WHERE native_user=p_native AND created_at>clock_timestamp()-interval '10 minutes')>=10 THEN RAISE EXCEPTION 'verification_rate_limit' USING ERRCODE='55000';END IF;
 SELECT updated_at,decrypted_secret INTO secret_row FROM vault.decrypted_secrets WHERE id=credential.secret_id;tokens:=secret_row.decrypted_secret::jsonb;
 IF secret_row.updated_at IS NULL OR tokens->>'shop' IS DISTINCT FROM credential.shop_domain OR length(coalesce(tokens->>'access_token','')) NOT BETWEEN 1 AND 16000 OR tokens->>'expires_at' IS NULL OR (tokens->>'expires_at')::timestamptz<=clock_timestamp()+interval '30 seconds' THEN RAISE EXCEPTION 'fresh_authorization_required' USING ERRCODE='55000';END IF;
 UPDATE tj_private.shopify_verification_sessions SET expires_at=clock_timestamp() WHERE connection_id=c.id AND completed_at IS NULL;
 DELETE FROM tj_private.shopify_verified_connections WHERE connection_id=c.id;
 INSERT INTO tj_private.shopify_verification_sessions(organization_id,connection_id,native_user,secret_id,secret_updated_at,connection_version,shop_domain) VALUES(c.organization_id,c.id,p_native,credential.secret_id,secret_row.updated_at,c.updated_at,credential.shop_domain) RETURNING id INTO session_id;
 RETURN jsonb_build_object('session_id',session_id,'shop',credential.shop_domain,'access_token',tokens->>'access_token');
END $$;
CREATE FUNCTION tj_private.shopify_verify_finish(p_native uuid,p_session uuid,p_result jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;s tj_private.shopify_verification_sessions%rowtype;c tj.platform_connector_connections%rowtype;updated timestamptz;tokens jsonb;expiry timestamptz;
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 SELECT * INTO s FROM tj_private.shopify_verification_sessions WHERE id=p_session AND native_user=p_native;
 IF NOT FOUND THEN RAISE EXCEPTION 'session_access_denied' USING ERRCODE='42501';END IF;
 actor:=tj_private.microsoft_actor(p_native);IF actor IS NULL THEN RAISE EXCEPTION 'identity_required' USING ERRCODE='42501';END IF;
 c:=tj_private.shopify_connection(s.connection_id,actor);
 SELECT * INTO s FROM tj_private.shopify_verification_sessions WHERE id=p_session AND native_user=p_native FOR UPDATE;
 SELECT updated_at,decrypted_secret::jsonb INTO updated,tokens FROM vault.decrypted_secrets WHERE id=s.secret_id;
 IF s.completed_at IS NOT NULL OR s.expires_at<=clock_timestamp() OR c.updated_at IS DISTINCT FROM s.connection_version OR updated IS DISTINCT FROM s.secret_updated_at OR NOT EXISTS(SELECT 1 FROM tj_private.shopify_credentials x WHERE x.connection_id=c.id AND x.secret_id=s.secret_id AND x.organization_id=s.organization_id AND x.shop_domain=s.shop_domain) OR c.credential_ref IS DISTINCT FROM s.secret_id::text OR c.external_account_id IS DISTINCT FROM s.shop_domain OR tokens->>'expires_at' IS NULL OR (tokens->>'expires_at')::timestamptz<=clock_timestamp() THEN RAISE EXCEPTION 'verification_context_changed' USING ERRCODE='40001';END IF;
 IF p_result IS NULL OR jsonb_typeof(p_result)<>'object' OR octet_length(p_result::text)>20000 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_result) k WHERE k NOT IN('shop_id','shop','currency','scopes')) OR coalesce(p_result->>'shop_id','')!~'^gid://shopify/Shop/[1-9][0-9]{0,24}$' OR p_result->>'shop' IS DISTINCT FROM s.shop_domain OR coalesce(p_result->>'currency','')!~'^[A-Z]{3}$' OR jsonb_typeof(p_result->'scopes') IS DISTINCT FROM 'array' OR jsonb_array_length(p_result->'scopes')>128 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_result->'scopes') e WHERE jsonb_typeof(e)<>'string' OR (e#>>'{}')!~'^[a-z_]{1,100}$') THEN RAISE EXCEPTION 'invalid_provider_result' USING ERRCODE='22023';END IF;
 expiry:=least(clock_timestamp()+interval '15 minutes',(tokens->>'expires_at')::timestamptz);
 INSERT INTO tj_private.shopify_verified_connections VALUES(c.id,c.organization_id,s.secret_id,updated,c.updated_at,p_result->>'shop_id',s.shop_domain,p_result->>'currency',p_result->'scopes',clock_timestamp(),expiry)
 ON CONFLICT(connection_id) DO UPDATE SET organization_id=excluded.organization_id,secret_id=excluded.secret_id,secret_updated_at=excluded.secret_updated_at,connection_version=excluded.connection_version,shop_id=excluded.shop_id,shop_domain=excluded.shop_domain,currency=excluded.currency,scopes=excluded.scopes,verified_at=excluded.verified_at,expires_at=excluded.expires_at;
 UPDATE tj_private.shopify_verification_sessions SET completed_at=clock_timestamp() WHERE id=s.id;
 RETURN jsonb_build_object('ok',true,'connection_id',c.id,'shop',s.shop_domain,'currency',p_result->>'currency','shop_identity_verified',true,'draft_order_scope_granted',(p_result->'scopes')?'write_draft_orders','draft_creation_enabled',false,'connection_activated',false,'verification_expires_at',expiry);
END $$;
REVOKE ALL ON FUNCTION tj_private.shopify_verify_begin(uuid,uuid),tj_private.shopify_verify_finish(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.shopify_verify_begin(uuid,uuid),tj_private.shopify_verify_finish(uuid,uuid,jsonb) TO service_role;
CREATE FUNCTION public.aiq_shopify_verify_begin(p_native uuid,p_connection uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.shopify_verify_begin(p_native,p_connection);$$;
CREATE FUNCTION public.aiq_shopify_verify_finish(p_native uuid,p_session uuid,p_result jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.shopify_verify_finish(p_native,p_session,p_result);$$;
REVOKE ALL ON FUNCTION public.aiq_shopify_verify_begin(uuid,uuid),public.aiq_shopify_verify_finish(uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_shopify_verify_begin(uuid,uuid),public.aiq_shopify_verify_finish(uuid,uuid,jsonb) TO service_role;
