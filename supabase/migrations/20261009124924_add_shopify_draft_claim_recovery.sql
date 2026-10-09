-- Internal lifecycle only. No provider call, credential access, package marker or invoice write.
CREATE TABLE tj_private.shopify_draft_attempts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 package_id uuid NOT NULL REFERENCES tj.speciq_packages(id),
 connection_id uuid NOT NULL REFERENCES tj.platform_connector_connections(id),
 native_user uuid NOT NULL REFERENCES auth.users(id),
 request_id uuid NOT NULL,
 payload_hash text NOT NULL CHECK(payload_hash~'^[0-9a-f]{64}$'),
 source_hash text NOT NULL,
 fence uuid NOT NULL DEFAULT gen_random_uuid(),
 state text NOT NULL DEFAULT 'prepared' CHECK(state IN('prepared','dispatched','unknown','succeeded','rejected','cancelled')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 expires_at timestamptz NOT NULL DEFAULT clock_timestamp()+interval '10 minutes',
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 provider_draft_id text,
 response_hash text,
 UNIQUE(native_user,request_id),
 CHECK((state='succeeded')=(provider_draft_id IS NOT NULL)),
 CHECK(provider_draft_id IS NULL OR provider_draft_id~'^gid://shopify/DraftOrder/[1-9][0-9]{0,24}$')
);
CREATE UNIQUE INDEX shopify_draft_package_inflight_idx ON tj_private.shopify_draft_attempts(package_id) WHERE state NOT IN('rejected','cancelled');
CREATE INDEX shopify_draft_attempts_package_idx ON tj_private.shopify_draft_attempts(package_id);
CREATE UNIQUE INDEX shopify_draft_provider_id_idx ON tj_private.shopify_draft_attempts(connection_id,provider_draft_id) WHERE provider_draft_id IS NOT NULL;
CREATE INDEX shopify_draft_attempts_org_idx ON tj_private.shopify_draft_attempts(organization_id);
CREATE INDEX shopify_draft_attempts_conn_idx ON tj_private.shopify_draft_attempts(connection_id);
CREATE TABLE tj_private.shopify_draft_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 attempt_id uuid NOT NULL REFERENCES tj_private.shopify_draft_attempts(id),
 native_user uuid NOT NULL REFERENCES auth.users(id),
 previous_state text,
 next_state text NOT NULL,
 response_hash text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX shopify_draft_events_org_idx ON tj_private.shopify_draft_events(organization_id);
CREATE INDEX shopify_draft_events_attempt_idx ON tj_private.shopify_draft_events(attempt_id);
CREATE INDEX shopify_draft_events_native_idx ON tj_private.shopify_draft_events(native_user);
ALTER TABLE tj_private.shopify_draft_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj_private.shopify_draft_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.shopify_draft_attempts,tj_private.shopify_draft_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON SEQUENCE tj_private.shopify_draft_events_id_seq FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.shopify_draft_attempts IS 'Internal future worker claim journal. Prepared expiry permits cancellation only before dispatch. Dispatched/unknown/succeeded retain a unique package slot indefinitely; never blindly retry a provider mutation. Not wired to live creation.';

CREATE FUNCTION tj_private.shopify_draft_source_hash(p_package uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT encode(extensions.digest(jsonb_build_object('package',to_jsonb(p),'products',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.id),'[]') FROM tj.speciq_package_products c WHERE c.package_id=p.id),'services',(SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.id),'[]') FROM tj.speciq_package_services c WHERE c.package_id=p.id))::text,'sha256'),'hex') FROM tj.speciq_packages p WHERE p.id=p_package;
$$;
REVOKE ALL ON FUNCTION tj_private.shopify_draft_source_hash(uuid) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.shopify_draft_attempt(p_native uuid,p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;operation text;org uuid;pkg tj.speciq_packages%rowtype;c tj.platform_connector_connections%rowtype;a tj_private.shopify_draft_attempts%rowtype;previous text;hash text;
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501'; END IF;
 actor:=tj_private.microsoft_actor(p_native);IF actor IS NULL THEN RAISE EXCEPTION 'verified_identity_required' USING ERRCODE='42501';END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>4096 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','package_id','connection_id','request_id','payload_hash','attempt_id','fence','draft_id','response_hash')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
 operation:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;
 IF operation IS NULL OR operation NOT IN('prepare','status','start','uncertain','reject','confirm','cancel') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.user_id=actor AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
 -- Lock order is package -> attempt everywhere, serializing all request keys for one package.
 SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) OR EXISTS(SELECT 1 FROM tj.speciq_package_services WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=(p_body->>'connection_id')::uuid AND organization_id=org;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM tj.platform_connectors pc WHERE pc.id=c.connector_id AND pc.key='shopify') THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF operation='prepare' THEN
   IF coalesce(p_body->>'payload_hash','')!~'^[0-9a-f]{64}$' OR p_body->>'request_id' IS NULL THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
   hash:=tj_private.shopify_draft_source_hash(pkg.id);
   SELECT * INTO a FROM tj_private.shopify_draft_attempts WHERE native_user=p_native AND request_id=(p_body->>'request_id')::uuid FOR UPDATE;
   IF FOUND THEN
     IF a.package_id<>pkg.id OR a.connection_id<>c.id OR a.organization_id<>org OR a.payload_hash<>p_body->>'payload_hash' THEN RAISE EXCEPTION 'request_key_conflict' USING ERRCODE='40001';END IF;
   ELSE
     IF pkg.shopify_draft_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM tj_private.shopify_draft_attempts WHERE package_id=pkg.id AND state NOT IN('rejected','cancelled')) THEN RAISE EXCEPTION 'package_claimed_or_existing_draft' USING ERRCODE='40001';END IF;
     INSERT INTO tj_private.shopify_draft_attempts(organization_id,package_id,connection_id,native_user,request_id,payload_hash,source_hash) VALUES(org,pkg.id,c.id,p_native,(p_body->>'request_id')::uuid,p_body->>'payload_hash',hash) RETURNING * INTO a;
     INSERT INTO tj_private.shopify_draft_events(organization_id,attempt_id,native_user,next_state) VALUES(org,a.id,p_native,'prepared');
   END IF;
 ELSE
   SELECT * INTO a FROM tj_private.shopify_draft_attempts WHERE id=(p_body->>'attempt_id')::uuid AND organization_id=org AND package_id=pkg.id AND connection_id=c.id AND native_user=p_native FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'attempt_access_denied' USING ERRCODE='42501';END IF;
   IF operation<>'status' THEN
     IF a.fence IS DISTINCT FROM (p_body->>'fence')::uuid THEN RAISE EXCEPTION 'stale_worker' USING ERRCODE='40001';END IF;
     previous:=a.state;
     IF operation='start' THEN
       IF a.state<>'prepared' OR a.expires_at<=clock_timestamp() OR a.source_hash IS DISTINCT FROM tj_private.shopify_draft_source_hash(pkg.id) OR c.status IN('paused','disconnected') OR pkg.shopify_draft_order_id IS NOT NULL THEN RAISE EXCEPTION 'dispatch_not_allowed' USING ERRCODE='40001';END IF;
       a.state:='dispatched';
     ELSIF operation='cancel' THEN
       IF a.state<>'prepared' THEN RAISE EXCEPTION 'cannot_cancel_dispatched_attempt' USING ERRCODE='40001';END IF;a.state:='cancelled';
     ELSIF operation='uncertain' THEN
       IF a.state NOT IN('dispatched','unknown') THEN RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;a.state:='unknown';
     ELSE
       IF coalesce(p_body->>'response_hash','')!~'^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'verified_response_hash_required' USING ERRCODE='22023';END IF;
       IF operation='reject' THEN
         -- Unknown cannot be released based on a retry error: the first request may have succeeded.
         IF a.state<>'dispatched' OR p_body->>'draft_id' IS NOT NULL THEN RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;a.state:='rejected';
       ELSE
         IF coalesce(p_body->>'draft_id','')!~'^gid://shopify/DraftOrder/[1-9][0-9]{0,24}$' THEN RAISE EXCEPTION 'invalid_draft_id' USING ERRCODE='22023';END IF;
         IF a.state='succeeded' THEN
           IF a.provider_draft_id<>p_body->>'draft_id' OR a.response_hash<>p_body->>'response_hash' THEN RAISE EXCEPTION 'completion_conflict' USING ERRCODE='40001';END IF;
         ELSIF a.state IN('dispatched','unknown') THEN a.state:='succeeded';a.provider_draft_id:=p_body->>'draft_id';
         ELSE RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;
       END IF;
       a.response_hash:=p_body->>'response_hash';
     END IF;
     IF previous<>a.state THEN
       UPDATE tj_private.shopify_draft_attempts SET state=a.state,provider_draft_id=a.provider_draft_id,response_hash=a.response_hash,updated_at=clock_timestamp() WHERE id=a.id;
       INSERT INTO tj_private.shopify_draft_events(organization_id,attempt_id,native_user,previous_state,next_state,response_hash) VALUES(org,a.id,p_native,previous,a.state,a.response_hash);
     END IF;
   END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'attempt_id',a.id,'fence',a.fence,'state',a.state,'provider_draft_id',a.provider_draft_id,'provider_execution_enabled',false);
END $$;
REVOKE ALL ON FUNCTION tj_private.shopify_draft_attempt(uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.shopify_draft_attempt(uuid,jsonb) TO service_role;
CREATE FUNCTION public.aiq_shopify_draft_attempt(p_native uuid,p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.shopify_draft_attempt(p_native,p_body); $$;
REVOKE ALL ON FUNCTION public.aiq_shopify_draft_attempt(uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_shopify_draft_attempt(uuid,jsonb) TO service_role;
