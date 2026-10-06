-- Resumable caller-initiated imports; approval is created only after real provider contract review.
CREATE TABLE tj_private.xstore_sync_contracts(
 connection_id uuid PRIMARY KEY REFERENCES tj.platform_connector_connections(id),
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),config_version timestamptz NOT NULL,
 config_digest text NOT NULL CHECK(config_digest ~ '^[0-9a-f]{64}$'),approved_by uuid NOT NULL REFERENCES tj.profiles(id),expires_at timestamptz NOT NULL);
CREATE INDEX xstore_sync_contracts_org_idx ON tj_private.xstore_sync_contracts(organization_id);
CREATE INDEX xstore_sync_contracts_approver_idx ON tj_private.xstore_sync_contracts(approved_by);
ALTER TABLE tj_private.xstore_sync_contracts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.xstore_sync_contracts FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE tj_private.xstore_sync_runs(
 job_id uuid PRIMARY KEY REFERENCES tj.platform_sync_jobs(id),organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 connection_id uuid NOT NULL REFERENCES tj.platform_connector_connections(id),actor uuid NOT NULL REFERENCES tj.profiles(id),
 config_version timestamptz NOT NULL,config_digest text NOT NULL,resources text[] NOT NULL,resource_index integer NOT NULL DEFAULT 1,
 phase text NOT NULL DEFAULT 'fetch' CHECK(phase IN('fetch','bridge','done')),next_url text,bridge_cursor text,
 pages integer NOT NULL DEFAULT 0,processed integer NOT NULL DEFAULT 0,failed integer NOT NULL DEFAULT 0,
 lease uuid,lease_until timestamptz,seen_urls jsonb NOT NULL DEFAULT '[]',retry_count integer NOT NULL DEFAULT 0);
CREATE INDEX xstore_sync_runs_connection_idx ON tj_private.xstore_sync_runs(connection_id);
CREATE INDEX xstore_sync_runs_org_idx ON tj_private.xstore_sync_runs(organization_id);
CREATE INDEX xstore_sync_runs_actor_idx ON tj_private.xstore_sync_runs(actor);
ALTER TABLE tj_private.xstore_sync_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.xstore_sync_runs FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.xstore_sync_approved(conn tj.platform_connector_connections) RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$
 SELECT conn.status NOT IN('paused','disconnected') AND EXISTS(
 SELECT 1 FROM tj_private.xstore_sync_contracts c JOIN tj.organization_members m ON m.user_id=c.approved_by AND m.organization_id=c.organization_id
 JOIN tj_private.xstore_credentials v ON v.connection_id=c.connection_id
 WHERE c.connection_id=conn.id AND c.organization_id=conn.organization_id AND c.config_version=conn.updated_at AND c.config_digest=encode(sha256(convert_to((conn.settings->'xstore_api')::text,'UTF8')),'hex') AND c.expires_at>clock_timestamp()
 AND m.status='active' AND m.role IN('owner','admin','super_admin') AND conn.credential_ref=v.secret_id::text AND v.organization_id=conn.organization_id AND conn.settings#>>'{xstore_api,base_url}' IS NOT NULL AND conn.settings#>>'{xstore_api,token_url}' IS NOT NULL);
$$;
REVOKE ALL ON FUNCTION tj_private.xstore_sync_approved(tj.platform_connector_connections) FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION tj_private.xstore_sync_claim(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.xstore_actor(auth.uid());conn tj.platform_connector_connections%rowtype;r tj_private.xstore_sync_runs%rowtype;j tj.platform_sync_jobs%rowtype;cfg jsonb;resources text[];jid uuid;token uuid;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','connection_id','sync_type','resources','job_id','cancel')) OR coalesce(p_body->>'sync_type','full') NOT IN('full','initial') THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 conn:=tj_private.xstore_connection((p_body->>'connection_id')::uuid,actor);
 IF p_body ? 'cancel' THEN
  IF jsonb_typeof(p_body->'cancel') IS DISTINCT FROM 'boolean' OR p_body->>'cancel'<>'true' OR p_body->>'job_id' IS NULL THEN RAISE EXCEPTION 'invalid_cancel' USING ERRCODE='22023';END IF;
  SELECT * INTO r FROM tj_private.xstore_sync_runs WHERE job_id=(p_body->>'job_id')::uuid FOR UPDATE;
  IF NOT FOUND OR r.connection_id<>conn.id OR r.organization_id<>conn.organization_id OR r.actor<>actor THEN RAISE EXCEPTION 'job_access_denied' USING ERRCODE='42501';END IF;
  UPDATE tj_private.xstore_sync_runs SET phase='done',lease=NULL,lease_until=NULL WHERE job_id=r.job_id;
  UPDATE tj.platform_sync_jobs SET status='canceled',completed_at=clock_timestamp() WHERE id=r.job_id AND status IN('queued','running');
  RETURN jsonb_build_object('ok',true,'done',true,'status',(SELECT status FROM tj.platform_sync_jobs WHERE id=r.job_id),'job_id',r.job_id,'processed',r.processed,'failed',r.failed,'metrics_refreshed',false);
 END IF;
 IF NOT tj_private.xstore_sync_approved(conn) THEN RETURN jsonb_build_object('ok',false,'error','xstore_destination_verification_required');END IF;
 cfg:=conn.settings->'xstore_api';jid:=nullif(p_body->>'job_id','')::uuid;
 IF p_body ? 'resources' AND (jsonb_typeof(p_body->'resources') IS DISTINCT FROM 'array' OR jsonb_array_length(p_body->'resources') NOT BETWEEN 1 AND 7 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_body->'resources') x WHERE jsonb_typeof(x)<>'string')) THEN RAISE EXCEPTION 'invalid_resources' USING ERRCODE='22023';END IF;
 IF jid IS NULL THEN
  SELECT x.id INTO jid FROM tj.platform_sync_jobs x WHERE x.connection_id=conn.id AND x.status IN('queued','running') ORDER BY x.created_at DESC LIMIT 1;
 END IF;
 IF jid IS NULL THEN
  IF p_body ? 'resources' THEN
   IF jsonb_typeof(p_body->'resources')<>'array' OR jsonb_array_length(p_body->'resources') NOT BETWEEN 1 AND 7 OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_body->'resources') x WHERE jsonb_typeof(x)<>'string') THEN RAISE EXCEPTION 'invalid_resources' USING ERRCODE='22023';END IF;
   SELECT array_agg(x ORDER BY x) INTO resources FROM (SELECT DISTINCT x FROM jsonb_array_elements_text(p_body->'resources') x) z;
  ELSE SELECT array_agg(k ORDER BY k) INTO resources FROM jsonb_object_keys(cfg->'endpoints') k;END IF;
  IF resources IS NULL OR EXISTS(SELECT 1 FROM unnest(resources) k WHERE k NOT IN('customers','products','employees','locations','inventory','prices','transactions') OR NOT (cfg->'endpoints' ? k)) THEN RAISE EXCEPTION 'unconfigured_resource' USING ERRCODE='22023';END IF;
  INSERT INTO tj.platform_sync_jobs(connection_id,job_type,direction,status,requested_by,started_at) VALUES(conn.id,'xstore_sync','inbound','running',actor,clock_timestamp()) RETURNING id INTO jid;
  INSERT INTO tj_private.xstore_sync_runs(job_id,organization_id,connection_id,actor,config_version,config_digest,resources) VALUES(jid,conn.organization_id,conn.id,actor,conn.updated_at,encode(sha256(convert_to(cfg::text,'UTF8')),'hex'),resources);
 END IF;
 SELECT * INTO j FROM tj.platform_sync_jobs WHERE id=jid;
 SELECT * INTO r FROM tj_private.xstore_sync_runs WHERE job_id=jid FOR UPDATE;
 IF NOT FOUND OR r.connection_id<>conn.id OR r.organization_id<>conn.organization_id OR r.actor<>actor OR j.connection_id<>conn.id OR j.requested_by<>actor THEN RAISE EXCEPTION 'job_access_denied' USING ERRCODE='42501';END IF;
 IF r.config_version IS DISTINCT FROM conn.updated_at OR r.config_digest IS DISTINCT FROM encode(sha256(convert_to((conn.settings->'xstore_api')::text,'UTF8')),'hex') THEN RAISE EXCEPTION 'configuration_changed' USING ERRCODE='40001';END IF;
 IF r.phase='done' THEN RETURN jsonb_build_object('ok',true,'job_id',jid,'done',true,'status',j.status,'processed',r.processed,'failed',r.failed,'metrics_refreshed',false);END IF;
 IF j.status<>'running' OR r.retry_count>=5 OR r.pages>=1000 OR r.lease_until>clock_timestamp() THEN RAISE EXCEPTION 'job_busy_or_bounded' USING ERRCODE='40001';END IF;
 IF p_body ? 'resources' AND (SELECT array_agg(x ORDER BY x) FROM (SELECT DISTINCT x FROM jsonb_array_elements_text(p_body->'resources') x) z) IS DISTINCT FROM r.resources THEN RAISE EXCEPTION 'resources_changed' USING ERRCODE='22023';END IF;
 token:=gen_random_uuid();
 UPDATE tj_private.xstore_sync_runs SET lease=token,lease_until=clock_timestamp()+interval '120 seconds' WHERE job_id=jid;
 RETURN jsonb_build_object('ok',true,'job_id',jid,'lease',token,'version',conn.updated_at,'phase',r.phase,'resource',r.resources[r.resource_index],'next_url',r.next_url,'configuration',cfg,'done',false);
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_sync_claim(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.xstore_sync_claim(jsonb) TO authenticated;

CREATE FUNCTION tj_private.xstore_sync_context(p_connection_id uuid,p_native_user uuid,p_job_id uuid,p_lease uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;conn tj.platform_connector_connections%rowtype;r tj_private.xstore_sync_runs%rowtype;credential jsonb;BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501';END IF;
 actor:=tj_private.xstore_actor(p_native_user);
 conn:=tj_private.xstore_connection(p_connection_id,actor);
 SELECT * INTO r FROM tj_private.xstore_sync_runs WHERE job_id=p_job_id FOR UPDATE;
 IF NOT FOUND OR r.connection_id<>conn.id OR r.organization_id<>conn.organization_id OR r.actor<>actor THEN RAISE EXCEPTION 'job_access_denied' USING ERRCODE='42501';END IF;
 IF r.lease IS DISTINCT FROM p_lease OR r.lease_until IS NULL OR r.lease_until<=clock_timestamp() OR r.phase='done' OR r.config_version IS DISTINCT FROM conn.updated_at OR r.config_digest IS DISTINCT FROM encode(sha256(convert_to((conn.settings->'xstore_api')::text,'UTF8')),'hex') OR NOT tj_private.xstore_sync_approved(conn) OR NOT EXISTS(SELECT 1 FROM tj.platform_sync_jobs j WHERE j.id=r.job_id AND j.connection_id=conn.id AND j.status='running' AND j.requested_by=actor) THEN RAISE EXCEPTION 'stale_lease_or_configuration' USING ERRCODE='40001';END IF;
 SELECT s.decrypted_secret::jsonb INTO credential FROM tj_private.xstore_credentials c JOIN vault.decrypted_secrets s ON s.id=c.secret_id WHERE c.connection_id=conn.id AND c.organization_id=conn.organization_id AND conn.credential_ref=c.secret_id::text;
 IF credential IS NULL THEN RAISE EXCEPTION 'credential_required' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('configuration',conn.settings->'xstore_api','credential',credential,'version',conn.updated_at,'phase',r.phase,'resource',r.resources[r.resource_index],'next_url',r.next_url,'bridge_cursor',r.bridge_cursor);
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_sync_context(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.xstore_sync_context(uuid,uuid,uuid,uuid) TO service_role;
CREATE FUNCTION public.aiq_xstore_sync_context(p_connection_id uuid,p_native_user uuid,p_job_id uuid,p_lease uuid) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.xstore_sync_context(p_connection_id,p_native_user,p_job_id,p_lease);$$;
REVOKE ALL ON FUNCTION public.aiq_xstore_sync_context(uuid,uuid,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_xstore_sync_context(uuid,uuid,uuid,uuid) TO service_role;

CREATE FUNCTION tj_private.xstore_sync_finish(p_connection_id uuid,p_native_user uuid,p_job_id uuid,p_lease uuid,p_result jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE context jsonb;r tj_private.xstore_sync_runs%rowtype;kind text;processed integer;failed integer;next_url text;next_cursor text;sync_status text;bounded boolean:=false;BEGIN
 context:=tj_private.xstore_sync_context(p_connection_id,p_native_user,p_job_id,p_lease);
 SELECT * INTO r FROM tj_private.xstore_sync_runs WHERE job_id=p_job_id FOR UPDATE;
 IF p_result IS NULL OR jsonb_typeof(p_result)<>'object' OR octet_length(p_result::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_result)k WHERE k NOT IN('kind','processed','failed','next_url','page_url','next_cursor','has_more')) THEN RAISE EXCEPTION 'invalid_result' USING ERRCODE='22023';END IF;
 kind:=p_result->>'kind';
 IF kind='retry' THEN
  UPDATE tj_private.xstore_sync_runs SET lease=NULL,lease_until=NULL,retry_count=retry_count+1 WHERE job_id=r.job_id;
  UPDATE tj.platform_sync_jobs SET error_details=jsonb_build_object('error','xstore_step_failed','resumable',r.retry_count<4),
   status=CASE WHEN r.retry_count>=4 THEN 'failed' ELSE status END,completed_at=CASE WHEN r.retry_count>=4 THEN clock_timestamp() ELSE completed_at END WHERE id=r.job_id;
  IF r.retry_count>=4 THEN UPDATE tj_private.xstore_sync_runs SET phase='done' WHERE job_id=r.job_id;END IF;
  RETURN jsonb_build_object('ok',false,'job_id',r.job_id,'resumable',r.retry_count<4,'done',r.retry_count>=4,'status',CASE WHEN r.retry_count>=4 THEN 'failed' ELSE 'running' END);
 END IF;
 processed:=(p_result->>'processed')::integer;failed:=(p_result->>'failed')::integer;
 IF processed IS NULL OR failed IS NULL OR processed<0 OR failed<0 OR processed+failed>100 THEN RAISE EXCEPTION 'invalid_counts' USING ERRCODE='22023';END IF;
 IF kind='page' AND r.phase='fetch' THEN
  next_url:=nullif(p_result->>'next_url','');
  IF p_result->>'page_url' IS NULL OR length(p_result->>'page_url')>4096 OR (r.next_url IS NOT NULL AND p_result->>'page_url' IS DISTINCT FROM r.next_url) OR (next_url IS NOT NULL AND (length(next_url)>4096 OR next_url!~'^https://' OR next_url=p_result->>'page_url' OR r.seen_urls ? next_url)) THEN RAISE EXCEPTION 'invalid_page_cursor' USING ERRCODE='22023';END IF;
  r.seen_urls:=r.seen_urls||to_jsonb(p_result->>'page_url');r.next_url:=next_url;r.pages:=r.pages+1;
  IF next_url IS NULL THEN r.resource_index:=r.resource_index+1;r.seen_urls:='[]';END IF;
  IF r.resource_index>array_length(r.resources,1) THEN r.phase:=CASE WHEN 'transactions'=ANY(r.resources) THEN 'bridge' ELSE 'done' END;END IF;
 ELSIF kind='bridge' AND r.phase='bridge' THEN
  next_cursor:=nullif(p_result->>'next_cursor','');
  IF processed<>0 OR jsonb_typeof(p_result->'has_more') IS DISTINCT FROM 'boolean' OR ((p_result->>'has_more')::boolean AND (next_cursor IS NULL OR length(next_cursor)>500 OR next_cursor<=coalesce(r.bridge_cursor,''))) THEN RAISE EXCEPTION 'invalid_bridge_cursor' USING ERRCODE='22023';END IF;
  r.bridge_cursor:=next_cursor;r.pages:=r.pages+1;
  IF NOT (p_result->>'has_more')::boolean THEN r.phase:='done';END IF;
 ELSE RAISE EXCEPTION 'invalid_phase' USING ERRCODE='22023';END IF;
 r.processed:=r.processed+processed;r.failed:=r.failed+failed;
 IF r.pages>=1000 AND r.phase<>'done' THEN r.phase:='done';r.failed:=r.failed+1;bounded:=true;END IF;
 UPDATE tj_private.xstore_sync_runs SET resource_index=r.resource_index,phase=r.phase,next_url=r.next_url,bridge_cursor=r.bridge_cursor,pages=r.pages,processed=r.processed,failed=r.failed,seen_urls=r.seen_urls,lease=NULL,lease_until=NULL,retry_count=0 WHERE job_id=r.job_id;
 sync_status:=CASE WHEN bounded THEN 'failed' WHEN r.phase<>'done' THEN 'running' WHEN r.failed>0 THEN 'partial' ELSE 'success' END;
 UPDATE tj.platform_sync_jobs SET status=sync_status,cursor=jsonb_build_object('phase',r.phase,'resource_index',r.resource_index,'pages',r.pages),stats=jsonb_build_object('processed',r.processed,'failed',r.failed),completed_at=CASE WHEN r.phase='done' THEN clock_timestamp() END,error_details=CASE WHEN r.failed>0 THEN '{"error":"xstore_records_or_bridge_failed"}'::jsonb END WHERE id=r.job_id;
 -- Import completion is staging completion. Never activate connections or refresh metrics here.
 IF r.phase='done' THEN UPDATE tj.platform_connector_connections SET last_sync_at=clock_timestamp(),last_success_at=CASE WHEN r.failed=0 THEN clock_timestamp() ELSE last_success_at END,last_error=CASE WHEN r.failed>0 THEN 'xstore_records_or_bridge_failed' END WHERE id=p_connection_id;END IF;
 RETURN jsonb_build_object('ok',true,'job_id',r.job_id,'status',sync_status,'done',r.phase='done','processed',r.processed,'failed',r.failed,'pages',r.pages,'metrics_refreshed',false,'requires_mapping_and_metric_review',true);
END $$;
REVOKE ALL ON FUNCTION tj_private.xstore_sync_finish(uuid,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.xstore_sync_finish(uuid,uuid,uuid,uuid,jsonb) TO service_role;
CREATE FUNCTION public.aiq_xstore_sync_finish(p_connection_id uuid,p_native_user uuid,p_job_id uuid,p_lease uuid,p_result jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.xstore_sync_finish(p_connection_id,p_native_user,p_job_id,p_lease,p_result);$$;
REVOKE ALL ON FUNCTION public.aiq_xstore_sync_finish(uuid,uuid,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_xstore_sync_finish(uuid,uuid,uuid,uuid,jsonb) TO service_role;
CREATE OR REPLACE FUNCTION tj_private.xstore_setup(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE conn tj.platform_connector_connections%rowtype;act text:=coalesce(p_body->>'action','status'); cfg jsonb;credential jsonb;sid uuid;path text;resource text;base text;token text;kh text;sh text;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('action','connection_id','base_url','endpoints','sync_type','resources','token_url','client_id','client_secret','scope','tenancy_id','org_id','api_version','job_id','cancel')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
 conn:=tj_private.xstore_connection(nullif(p_body->>'connection_id','')::uuid,tj_private.xstore_actor(auth.uid()));cfg:=coalesce(conn.settings->'xstore_api','{}');
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
  RETURN tj_private.xstore_sync_claim(p_body);
 ELSIF act NOT IN('status','test') THEN RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';END IF;
 SELECT secret_id INTO sid FROM tj_private.xstore_credentials WHERE connection_id=conn.id AND organization_id=conn.organization_id;
 IF act='test' AND (conn.status IN('paused','disconnected') OR sid IS NULL OR cfg->>'base_url' IS NULL) THEN RAISE EXCEPTION 'xstore_not_configured' USING ERRCODE='40001';END IF;
 RETURN jsonb_build_object('ok',true,'connection',jsonb_build_object('id',conn.id,'status',conn.status,'auth_status',CASE WHEN sid IS NULL THEN 'not_configured' ELSE conn.auth_status END,'last_sync_at',conn.last_sync_at,'last_success_at',conn.last_success_at),'configuration',jsonb_build_object('base_url',cfg->>'base_url','endpoints',coalesce(cfg->'endpoints','{}'),'token_url',cfg->>'token_url','tenancy_id',cfg->>'tenancy_id','org_id',cfg->>'org_id','api_version',cfg->>'api_version','configured',sid IS NOT NULL AND cfg->>'base_url' IS NOT NULL),'version',conn.updated_at,'sync_ready',tj_private.xstore_sync_approved(conn),'requires_provider_review',true);
END $$;
NOTIFY pgrst,'reload schema';
