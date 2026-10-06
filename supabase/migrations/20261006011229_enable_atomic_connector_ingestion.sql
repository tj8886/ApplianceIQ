-- Caller broker: one record, one transaction; imported payload is evidence, never authorization.
CREATE FUNCTION tj_private.connector_ingest(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();conn tj.platform_connector_connections%rowtype;rule tj.platform_connector_canonical_rules%rowtype;
 seen tj.platform_connector_ingestion_keys%rowtype;ctype text;etype text;external text;connector_key text;variant_key text;source_system text;source_record text;canonical_name text;occurred timestamptz;job uuid;payload jsonb;hash text;validation jsonb;entity uuid;event uuid;ingestion uuid;qid uuid;state text;retryable boolean;BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>262144 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)k WHERE k NOT IN('connection_id','external_entity_type','external_id','sync_job_id','payload','canonical_name','canonical_entity_type','canonical_event_type','occurred_at','title','summary')) THEN RAISE EXCEPTION 'invalid_body' USING ERRCODE='22023';END IF;
 SELECT * INTO conn FROM tj.platform_connector_connections WHERE id=nullif(p_body->>'connection_id','')::uuid FOR UPDATE;
 IF NOT FOUND OR actor IS NULL THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=conn.organization_id AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF conn.status IN('paused','disconnected') THEN RAISE EXCEPTION 'connection_not_ready' USING ERRCODE='40001';END IF;
 IF conn.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=conn.store_id AND l.organization_id=conn.organization_id AND l.is_active) THEN RAISE EXCEPTION 'invalid_connection_store' USING ERRCODE='42501';END IF;
 job:=nullif(p_body->>'sync_job_id','')::uuid;
 IF job IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.platform_sync_jobs j WHERE j.id=job AND j.connection_id=conn.id AND j.status='running') THEN RAISE EXCEPTION 'invalid_sync_job' USING ERRCODE='42501';END IF;
 etype:=p_body->>'external_entity_type';external:=p_body->>'external_id';payload:=p_body->'payload';
 IF etype IS NULL OR etype!~'^[a-z][a-z0-9_]{0,79}$' OR external IS NULL OR trim(external)='' OR length(external)>500 OR jsonb_typeof(payload) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_record' USING ERRCODE='22023';END IF;
 canonical_name:=coalesce(nullif(p_body->>'canonical_name',''),nullif(payload->>'canonical_name',''),nullif(payload->>'name',''),nullif(payload->>'displayName',''),nullif(payload->>'number',''),external);
 IF length(canonical_name)>500 OR length(coalesce(p_body->>'title',''))>500 OR length(coalesce(p_body->>'summary',''))>4000 THEN RAISE EXCEPTION 'invalid_text_limits' USING ERRCODE='22023';END IF;
 occurred:=coalesce(nullif(p_body->>'occurred_at','')::timestamptz,clock_timestamp());IF NOT isfinite(occurred) OR occurred>clock_timestamp()+interval '1 day' OR occurred<'1900-01-01'::timestamptz THEN RAISE EXCEPTION 'invalid_record_date' USING ERRCODE='22023';END IF;
 SELECT c.key,v.key INTO connector_key,variant_key FROM tj.platform_connectors c LEFT JOIN tj.platform_connector_variants v ON v.id=conn.variant_id AND v.connector_id=c.id WHERE c.id=conn.connector_id;
 IF connector_key IS NULL OR (conn.variant_id IS NOT NULL AND variant_key IS NULL) THEN RAISE EXCEPTION 'invalid_connector' USING ERRCODE='40001';END IF;
 source_system:=connector_key||CASE WHEN variant_key IS NULL THEN '' ELSE ':'||variant_key END;
 SELECT * INTO rule FROM tj.platform_connector_canonical_rules r WHERE r.connector_id=conn.connector_id AND r.external_entity_type=etype AND r.active AND r.direction IN('inbound','bidirectional') AND (r.variant_id IS NULL OR r.variant_id=conn.variant_id) ORDER BY (r.variant_id IS NULL),r.priority,r.id LIMIT 1;
 IF NOT FOUND THEN qid:=tj_private.platform_enqueue_connector_quarantine(conn.id,job,etype,external,'mapping','canonical_mapping_not_found','No inbound canonical mapping',payload,false);RETURN jsonb_build_object('ok',false,'error','canonical_mapping_not_found','quarantine_id',qid,'http_status',422);END IF;
 ctype:=coalesce(rule.canonical_entity_type,'other');
 IF (p_body ? 'canonical_entity_type' AND p_body->>'canonical_entity_type' IS DISTINCT FROM ctype) OR (p_body ? 'canonical_event_type' AND p_body->>'canonical_event_type' IS DISTINCT FROM coalesce(rule.canonical_event_type,ctype||'.updated')) THEN RAISE EXCEPTION 'canonical_override_denied' USING ERRCODE='22023';END IF;
 validation:=tj_private.platform_validate_connector_record(connector_key,etype,payload);
 IF validation->>'valid' IS DISTINCT FROM 'true' THEN qid:=tj_private.platform_enqueue_connector_quarantine(conn.id,job,etype,external,'validation','record_validation_failed','Validation failed',payload,false);RETURN jsonb_build_object('ok',false,'error','record_validation_failed','quarantine_id',qid,'http_status',422);END IF;
 hash:=encode(sha256(convert_to(payload::text,'UTF8')),'hex');
 SELECT * INTO seen FROM tj.platform_connector_ingestion_keys k WHERE k.connection_id=conn.id AND k.external_entity_type=etype AND k.external_id=external AND k.canonical_event_type=coalesce(rule.canonical_event_type,ctype||'.updated') AND k.payload_hash=hash;
 IF FOUND THEN
  IF NOT EXISTS(SELECT 1 FROM tj.intelligence_entities e JOIN tj.intelligence_events ev ON ev.entity_id=e.id WHERE e.id=seen.intelligence_entity_id AND ev.id=seen.intelligence_event_id AND e.organization_id=conn.organization_id AND ev.organization_id=conn.organization_id AND ev.payload->>'connector_connection_id'=conn.id::text) THEN RAISE EXCEPTION 'invalid_existing_ingestion_scope' USING ERRCODE='42501';END IF;
  UPDATE tj.platform_connector_ingestion_keys SET last_seen_at=clock_timestamp() WHERE id=seen.id;
  RETURN jsonb_build_object('ok',true,'deduped',true,'intelligence_entity_id',seen.intelligence_entity_id,'intelligence_event_id',seen.intelligence_event_id);
 END IF;
 -- Namespace entity identity by connection so two same-provider connections cannot overwrite one another.
 source_record:=conn.id::text||':'||etype||':'||external;
 BEGIN
  INSERT INTO tj.intelligence_entities(organization_id,entity_type,canonical_name,source_system,source_record_id,status,metadata,created_by,updated_by)
   VALUES(conn.organization_id,ctype,canonical_name,source_system,source_record,'active',payload||jsonb_build_object('connector_connection_id',conn.id,'external_entity_type',etype,'external_id',external),actor,actor)
   ON CONFLICT(organization_id,source_system,source_record_id) DO UPDATE SET entity_type=excluded.entity_type,canonical_name=excluded.canonical_name,metadata=excluded.metadata,updated_by=actor,updated_at=clock_timestamp() RETURNING id INTO entity;
  INSERT INTO tj.platform_connector_entity_map(connection_id,external_entity_type,external_id,local_entity_type,local_id,payload_hash,metadata,last_synced_at)
   VALUES(conn.id,etype,external,'intelligence_entity',entity,hash,jsonb_build_object('canonical_entity_type',ctype,'canonical_event_type',coalesce(rule.canonical_event_type,ctype||'.updated'),'source_system',source_system),clock_timestamp())
   ON CONFLICT(connection_id,external_entity_type,external_id) DO UPDATE SET local_id=excluded.local_id,payload_hash=excluded.payload_hash,metadata=excluded.metadata,last_synced_at=excluded.last_synced_at WHERE tj.platform_connector_entity_map.local_entity_type='intelligence_entity';
  INSERT INTO tj.intelligence_events(organization_id,store_id,entity_id,event_type,canonical_event_type,source_system,source_record_id,actor_id,payload,occurred_at)
   VALUES(conn.organization_id,conn.store_id,entity,coalesce(rule.canonical_event_type,ctype||'.updated'),coalesce(rule.canonical_event_type,ctype||'.updated'),source_system,source_record||':'||hash,actor,payload||jsonb_build_object('title',coalesce(p_body->>'title',canonical_name||' '||coalesce(rule.canonical_event_type,ctype||'.updated')),'summary',p_body->>'summary','connector_connection_id',conn.id,'external_entity_type',etype,'external_id',external),occurred) RETURNING id INTO event;
  INSERT INTO tj.platform_connector_ingestion_keys(connection_id,external_entity_type,external_id,canonical_event_type,payload_hash,intelligence_entity_id,intelligence_event_id,metadata)
   VALUES(conn.id,etype,external,coalesce(rule.canonical_event_type,ctype||'.updated'),hash,entity,event,jsonb_build_object('source_system',source_system,'canonical_entity_type',ctype)) RETURNING id INTO ingestion;
  -- Resolve both retryable and nonretryable quarantine entries only after successful atomic ingestion.
  DELETE FROM tj.platform_connector_retry_queue rq USING tj.platform_connector_quarantine q WHERE rq.quarantine_id=q.id AND q.connection_id=conn.id AND q.external_entity_type=etype AND q.external_id=external AND q.status IN('quarantined','retrying');
  UPDATE tj.platform_connector_quarantine SET status='resolved',resolved_at=clock_timestamp(),resolution=jsonb_build_object('method','scoped_ingestion_success','actor',actor) WHERE connection_id=conn.id AND external_entity_type=etype AND external_id=external AND status IN('quarantined','retrying');
 EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS state=RETURNED_SQLSTATE;retryable:=state IN('40001','40P01','55P03','57014');
  qid:=tj_private.platform_enqueue_connector_quarantine(conn.id,job,etype,external,'ingestion','ingestion_error','Atomic ingestion failed: '||state,payload,retryable);
  RETURN jsonb_build_object('ok',false,'error','ingestion_failed','retryable',retryable,'quarantine_id',qid,'http_status',CASE WHEN retryable THEN 503 ELSE 500 END);
 END;
 RETURN jsonb_build_object('ok',true,'deduped',false,'canonical_entity_type',ctype,'canonical_event_type',coalesce(rule.canonical_event_type,ctype||'.updated'),'intelligence_entity_id',entity,'intelligence_event_id',event,'ingestion_id',ingestion,'http_status',201);
END $$;
REVOKE ALL ON FUNCTION tj_private.connector_ingest(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.connector_ingest(jsonb) TO authenticated;
CREATE FUNCTION public.tj_connector_ingest(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.connector_ingest(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_connector_ingest(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_connector_ingest(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
