-- Native caller broker: external identifiers are review suggestions, never identity authorization.
CREATE FUNCTION tj_private.onboarding_normalize(p_text text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT trim(regexp_replace(lower(translate(coalesce(p_text,''),'àáâãäåèéêëìíîïòóôõöùúûüçñ','aaaaaaeeeeiiiiooooouuuucn')),'[^a-z0-9]+',' ','g'));
$$;
CREATE FUNCTION tj_private.onboarding_field(p_payload jsonb,p_fields text[]) RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE field text;value jsonb;BEGIN
 FOREACH field IN ARRAY coalesce(p_fields,ARRAY[]::text[]) LOOP
  value:=p_payload #> string_to_array(field,'.');
  IF jsonb_typeof(value) IN('string','number','boolean') AND trim(value#>>'{}')<>'' THEN RETURN left(value#>>'{}',500);END IF;
 END LOOP;RETURN NULL;
END $$;
CREATE FUNCTION tj_private.onboarding_similarity(a text,b text) RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 WITH texts AS(SELECT ' '||tj_private.onboarding_normalize(a)||' ' x,' '||tj_private.onboarding_normalize(b)||' ' y),
 aa AS(SELECT substring(x FROM i FOR 2) gram,count(*) n FROM texts,generate_series(1,length(x)-1)i GROUP BY 1),
 bb AS(SELECT substring(y FROM i FOR 2) gram,count(*) n FROM texts,generate_series(1,length(y)-1)i GROUP BY 1)
 SELECT CASE WHEN tj_private.onboarding_normalize(a)='' OR tj_private.onboarding_normalize(b)='' THEN 0
 ELSE 2.0*coalesce((SELECT sum(least(aa.n,bb.n)) FROM aa JOIN bb USING(gram)),0)/(length(x)+length(y)-2) END FROM texts;
$$;
CREATE FUNCTION tj_private.connector_onboarding(p_body jsonb) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();act text:=coalesce(p_body->>'action','status');
 conn tj.platform_connector_connections%rowtype;prof tj.platform_connector_onboarding_profiles%rowtype;
 q tj.platform_connector_match_queue%rowtype;k record;payload jsonb;kind text;code text;ename text;em text;city text;addr text;external text;
 candidate uuid;candidate_count bigint;score numeric;method text;location uuid;person uuid;store uuid;next_key uuid;processed integer:=0;
 queue_json jsonb;users_json jsonb;locations_json jsonb;summary jsonb;et bigint;ec bigint;er bigint;lt bigint;lc bigint;lr bigint;
 mapping_ready boolean;destination_verified boolean;queue_total bigint;members_total bigint;locations_total bigint;
BEGIN
 IF actor IS NULL THEN RAISE EXCEPTION 'organization_access_denied' USING ERRCODE='42501';END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 OR
 EXISTS(SELECT 1 FROM jsonb_object_keys(p_body)x WHERE x NOT IN('action','connection_id','external_id','user_id','store_id','location_id','create','match_id','after_ingestion_key')) THEN RAISE EXCEPTION 'invalid_body' USING ERRCODE='22023';END IF;
 IF act NOT IN('status','auto_match','resolve_employee','resolve_location','reject','activate') THEN RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023';END IF;
 SELECT * INTO conn FROM tj.platform_connector_connections WHERE id=nullif(p_body->>'connection_id','')::uuid FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=conn.organization_id AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501';END IF;
 IF conn.store_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=conn.store_id AND l.organization_id=conn.organization_id AND l.is_active) THEN RAISE EXCEPTION 'invalid_connection_store' USING ERRCODE='42501';END IF;
 SELECT * INTO prof FROM tj.platform_connector_onboarding_profiles p WHERE p.connector_id=conn.connector_id AND p.variant_id IS NOT DISTINCT FROM conn.variant_id AND p.is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'onboarding_profile_not_configured' USING ERRCODE='40001';END IF;
 -- Serialize maps shared by multiple connections for one organization/POS system.
 IF act<>'status' THEN PERFORM pg_advisory_xact_lock(hashtextextended(conn.organization_id::text||':'||prof.pos_system_key,0));END IF;
 SELECT count(*) INTO members_total FROM tj.organization_members m WHERE m.organization_id=conn.organization_id AND m.status='active';
 SELECT count(*) INTO locations_total FROM tj.org_locations l WHERE l.organization_id=conn.organization_id AND l.is_active;
 IF members_total>1000 OR locations_total>1000 THEN RAISE EXCEPTION 'candidate_scope_requires_pagination' USING ERRCODE='54000';END IF;
 IF act='auto_match' THEN
  FOR k IN SELECT ik.id,ik.external_id,ik.external_entity_type,e.payload FROM tj.platform_connector_ingestion_keys ik JOIN tj.intelligence_events e ON e.id=ik.intelligence_event_id
   WHERE ik.connection_id=conn.id AND e.organization_id=conn.organization_id AND
   (e.store_id IS NULL OR EXISTS(SELECT 1 FROM tj.org_locations l WHERE l.id=e.store_id AND l.organization_id=conn.organization_id AND l.is_active) AND (conn.store_id IS NULL OR e.store_id=conn.store_id)) AND
   ik.external_entity_type=ANY(prof.employee_entity_types||prof.location_entity_types) AND
   (nullif(p_body->>'after_ingestion_key','') IS NULL OR ik.id>(p_body->>'after_ingestion_key')::uuid) ORDER BY ik.id LIMIT 500 LOOP
   next_key:=k.id;processed:=processed+1;payload:=k.payload;
   IF octet_length(payload::text)>65536 THEN CONTINUE;END IF;
   kind:=CASE WHEN k.external_entity_type=ANY(prof.employee_entity_types) THEN 'employee' ELSE 'location' END;
   external:=coalesce(tj_private.onboarding_field(payload,ARRAY['id','uuid','recordId']),k.external_id);
   IF length(external)>500 THEN CONTINUE;END IF;
   SELECT * INTO q FROM tj.platform_connector_match_queue mq WHERE mq.connection_id=conn.id AND mq.external_entity_type=kind AND mq.external_id=external;
   IF FOUND AND q.metadata->>'us_onboarding_reviewed'='true' THEN CONTINUE;END IF;
   candidate:=NULL;score:=NULL;method:=NULL;
   IF kind='employee' THEN
    code:=coalesce(tj_private.onboarding_field(payload,prof.employee_code_fields),k.external_id);ename:=coalesce(tj_private.onboarding_field(payload,prof.employee_name_fields),code);
    em:=lower(trim(tj_private.onboarding_field(payload,prof.employee_email_fields)));
    SELECT count(*),(array_agg(p.user_id))[1] INTO candidate_count,candidate FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id AND m.organization_id=conn.organization_id AND m.status='active'
     WHERE em IS NOT NULL AND em<>'' AND lower(trim(p.email))=em;
    IF candidate_count=1 THEN score:=1;method:='email_exact';ELSE candidate:=NULL;END IF;
    IF candidate IS NULL THEN
     SELECT count(*),(array_agg(p.user_id))[1] INTO candidate_count,candidate FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id AND m.organization_id=conn.organization_id AND m.status='active'
      WHERE tj_private.onboarding_normalize(ename)<>'' AND tj_private.onboarding_normalize(p.full_name)=tj_private.onboarding_normalize(ename);
     IF candidate_count=1 THEN score:=.98;method:='name_exact';ELSE candidate:=NULL;END IF;
    END IF;
    IF candidate IS NULL THEN
     SELECT p.user_id,tj_private.onboarding_similarity(ename,p.full_name) INTO candidate,score FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id AND m.organization_id=conn.organization_id AND m.status='active'
      WHERE tj_private.onboarding_similarity(ename,p.full_name)>=.80 ORDER BY tj_private.onboarding_similarity(ename,p.full_name) DESC,p.user_id LIMIT 1;
     IF candidate IS NOT NULL THEN method:='name_similarity';END IF;
    END IF;
    city:=NULL;addr:=NULL;
   ELSE
    code:=tj_private.onboarding_field(payload,prof.location_code_fields);ename:=coalesce(tj_private.onboarding_field(payload,prof.location_name_fields),code,external);
    em:=NULL;city:=tj_private.onboarding_field(payload,prof.location_city_fields);addr:=tj_private.onboarding_field(payload,prof.location_address_fields);
    SELECT count(*),(array_agg(l.id))[1] INTO candidate_count,candidate FROM tj.org_locations l WHERE l.organization_id=conn.organization_id AND l.is_active AND code IS NOT NULL AND tj_private.onboarding_normalize(l.code)=tj_private.onboarding_normalize(code);
    IF candidate_count=1 THEN score:=1;method:='code_exact';ELSE candidate:=NULL;END IF;
    IF candidate IS NULL THEN
     SELECT count(*),(array_agg(l.id))[1] INTO candidate_count,candidate FROM tj.org_locations l WHERE l.organization_id=conn.organization_id AND l.is_active AND tj_private.onboarding_normalize(ename)<>'' AND tj_private.onboarding_normalize(l.name)=tj_private.onboarding_normalize(ename) AND (city IS NULL OR tj_private.onboarding_normalize(l.city)=tj_private.onboarding_normalize(city));
     IF candidate_count=1 THEN score:=.98;method:='name_city_exact';ELSE candidate:=NULL;END IF;
    END IF;
    IF candidate IS NULL THEN
     SELECT l.id,.65*tj_private.onboarding_similarity(ename,l.name)+.20*tj_private.onboarding_similarity(city,l.city)+.15*tj_private.onboarding_similarity(addr,l.address) INTO candidate,score FROM tj.org_locations l WHERE l.organization_id=conn.organization_id AND l.is_active AND .65*tj_private.onboarding_similarity(ename,l.name)+.20*tj_private.onboarding_similarity(city,l.city)+.15*tj_private.onboarding_similarity(addr,l.address)>=.68
      ORDER BY .65*tj_private.onboarding_similarity(ename,l.name)+.20*tj_private.onboarding_similarity(city,l.city)+.15*tj_private.onboarding_similarity(addr,l.address) DESC,l.id LIMIT 1;
     IF candidate IS NOT NULL THEN method:='location_similarity';END IF;
    END IF;
   END IF;
   INSERT INTO tj.platform_connector_match_queue(connection_id,organization_id,external_entity_type,external_id,external_code,external_name,external_email,candidate_type,candidate_id,confidence,match_method,status,metadata)
    VALUES(conn.id,conn.organization_id,kind,external,code,ename,em,CASE WHEN candidate IS NULL THEN NULL WHEN kind='employee' THEN 'user' ELSE 'location' END,candidate,score,method,CASE WHEN candidate IS NULL THEN 'unmatched' ELSE 'suggested' END,
     jsonb_build_object('source_entity_type',k.external_entity_type,'source_label',prof.source_label,'address',addr,'city',city,'us_onboarding_generated',true,'us_onboarding_reviewed',false))
    ON CONFLICT(connection_id,external_entity_type,external_id) DO UPDATE SET external_code=excluded.external_code,external_name=excluded.external_name,external_email=excluded.external_email,candidate_type=excluded.candidate_type,candidate_id=excluded.candidate_id,confidence=excluded.confidence,match_method=excluded.match_method,status=excluded.status,metadata=excluded.metadata,reviewed_by=NULL,reviewed_at=NULL,updated_at=clock_timestamp()
    WHERE tj.platform_connector_match_queue.organization_id=conn.organization_id AND tj.platform_connector_match_queue.metadata->>'us_onboarding_reviewed' IS DISTINCT FROM 'true';
  END LOOP;
 END IF;
 IF act IN('resolve_employee','resolve_location','reject') THEN
  IF length(coalesce(p_body->>'external_id',''))>500 THEN RAISE EXCEPTION 'invalid_external_id' USING ERRCODE='22023';END IF;
  IF act='reject' THEN SELECT * INTO q FROM tj.platform_connector_match_queue WHERE id=nullif(p_body->>'match_id','')::uuid AND connection_id=conn.id AND organization_id=conn.organization_id FOR UPDATE;
  ELSE SELECT * INTO q FROM tj.platform_connector_match_queue WHERE connection_id=conn.id AND organization_id=conn.organization_id AND external_entity_type=CASE WHEN act='resolve_employee' THEN 'employee' ELSE 'location' END AND external_id=p_body->>'external_id' FOR UPDATE;END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'match_row_not_found' USING ERRCODE='P0002';END IF;
  IF act='reject' THEN
   IF q.status='confirmed' AND q.metadata->>'us_onboarding_reviewed'='true' THEN RAISE EXCEPTION 'confirmed_match_cannot_be_ignored' USING ERRCODE='40001';END IF;
   UPDATE tj.platform_connector_match_queue SET status='rejected',reviewed_by=actor,reviewed_at=clock_timestamp(),metadata=metadata||'{"us_onboarding_reviewed":true,"decision_locked":true}'::jsonb,updated_at=clock_timestamp() WHERE id=q.id;
  ELSE
   IF act='resolve_employee' THEN
    person:=nullif(p_body->>'user_id','')::uuid;store:=coalesce(nullif(p_body->>'store_id','')::uuid,conn.store_id);
    IF person IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE user_id=person AND organization_id=conn.organization_id AND status='active') THEN RAISE EXCEPTION 'user_not_active_org_member' USING ERRCODE='42501';END IF;
    IF store IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=store AND organization_id=conn.organization_id AND is_active) THEN RAISE EXCEPTION 'store_access_denied' USING ERRCODE='42501';END IF;
    code:=coalesce(nullif(q.external_code,''),q.external_id);
    INSERT INTO tj.iq_pos_employee_map(organization_id,store_id,salesperson_user_id,pos_employee_id,pos_system,display_name,is_active,created_by,updated_at)
     VALUES(conn.organization_id,store,person,code,prof.pos_system_key,q.external_name,true,actor,clock_timestamp())
     ON CONFLICT(organization_id,pos_system,pos_employee_id) DO UPDATE SET store_id=excluded.store_id,salesperson_user_id=excluded.salesperson_user_id,display_name=excluded.display_name,is_active=true,updated_at=clock_timestamp();
    candidate:=person;
   ELSE
    location:=nullif(p_body->>'location_id','')::uuid;
    IF location IS NULL AND p_body->'create'='true'::jsonb THEN
     IF q.metadata->>'us_onboarding_generated' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'run_auto_match_before_creation' USING ERRCODE='40001';END IF;
     -- Repeated create requests reuse the manually reviewed location.
     IF q.status='confirmed' AND q.metadata->>'us_onboarding_reviewed'='true' THEN location:=q.candidate_id;
     ELSE INSERT INTO tj.org_locations(organization_id,location_type,name,code,address,city,metadata) VALUES(conn.organization_id,'store',left(coalesce(q.external_name,q.external_code,q.external_id),160),left(q.external_code,100),left(q.metadata->>'address',500),left(q.metadata->>'city',120),jsonb_build_object('source',prof.pos_system_key,'source_connection_id',conn.id,'external_location_id',q.external_id,'created_by',actor)) RETURNING id INTO location;END IF;
    END IF;
    IF location IS NULL OR NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=location AND organization_id=conn.organization_id AND is_active) THEN RAISE EXCEPTION 'location_not_in_org' USING ERRCODE='42501';END IF;
    IF nullif(q.metadata->>'source_entity_type','') IS NULL OR NOT(q.metadata->>'source_entity_type'=ANY(prof.location_entity_types)) THEN RAISE EXCEPTION 'invalid_source_entity_type' USING ERRCODE='22023';END IF;
    INSERT INTO tj.platform_connector_entity_map(connection_id,external_entity_type,external_id,local_entity_type,local_id,metadata,last_synced_at) VALUES(conn.id,q.metadata->>'source_entity_type',q.external_id,'org_location',location,jsonb_build_object('confirmed_by',actor,'method','manual','us_onboarding_reviewed',true),clock_timestamp())
     ON CONFLICT(connection_id,external_entity_type,external_id) DO UPDATE SET local_entity_type='org_location',local_id=excluded.local_id,metadata=excluded.metadata,last_synced_at=clock_timestamp();
    candidate:=location;
   END IF;
   UPDATE tj.platform_connector_match_queue SET candidate_type=CASE WHEN act='resolve_employee' THEN 'user' ELSE 'location' END,candidate_id=candidate,confidence=1,match_method='manual',status='confirmed',reviewed_by=actor,reviewed_at=clock_timestamp(),metadata=metadata||'{"us_onboarding_reviewed":true,"decision_locked":true}'::jsonb,updated_at=clock_timestamp() WHERE id=q.id;
   IF act='resolve_location' AND (SELECT count(*) FROM tj.platform_connector_match_queue mq WHERE mq.connection_id=conn.id AND mq.organization_id=conn.organization_id AND mq.external_entity_type='location' AND mq.status='confirmed' AND mq.metadata->>'us_onboarding_reviewed'='true')=1 THEN UPDATE tj.platform_connector_connections SET store_id=location,updated_at=clock_timestamp() WHERE id=conn.id;conn.store_id:=location;END IF;
  END IF;
 END IF;
 SELECT count(*) FILTER(WHERE external_entity_type='employee'),count(*) FILTER(WHERE external_entity_type='employee' AND status='confirmed' AND metadata->>'us_onboarding_reviewed'='true'),count(*) FILTER(WHERE external_entity_type='employee' AND NOT(status IN('confirmed','rejected') AND coalesce(metadata->>'us_onboarding_reviewed'='true',false))),
 count(*) FILTER(WHERE external_entity_type='location'),count(*) FILTER(WHERE external_entity_type='location' AND status='confirmed' AND metadata->>'us_onboarding_reviewed'='true'),count(*) FILTER(WHERE external_entity_type='location' AND NOT(status IN('confirmed','rejected') AND coalesce(metadata->>'us_onboarding_reviewed'='true',false))) INTO et,ec,er,lt,lc,lr FROM tj.platform_connector_match_queue WHERE connection_id=conn.id AND organization_id=conn.organization_id;
 mapping_ready:=et>0 AND lt>0 AND ec>0 AND lc>0 AND er=0 AND lr=0;
 -- Source auth/credential references are not proof of working destination credentials.
 destination_verified:=conn.settings->>'destination_connection_verified'='true';
 summary:=jsonb_build_object('employees_total',et,'employees_confirmed',ec,'employees_review',er,'locations_total',lt,'locations_confirmed',lc,'locations_review',lr,'mapping_ready',mapping_ready,'destination_connection_verified',coalesce(destination_verified,false),'ready',mapping_ready AND coalesce(destination_verified,false));
 IF act='activate' THEN
  IF NOT(mapping_ready AND coalesce(destination_verified,false)) THEN RETURN jsonb_build_object('error','onboarding_review_incomplete','summary',summary,'ok',false);END IF;
  -- A reviewed mapping may become inactive between review and activation.
  IF EXISTS(SELECT 1 FROM tj.platform_connector_match_queue mq WHERE mq.connection_id=conn.id AND mq.status='confirmed' AND ((mq.external_entity_type='employee' AND NOT EXISTS(SELECT 1 FROM tj.organization_members WHERE user_id=mq.candidate_id AND organization_id=conn.organization_id AND status='active')) OR (mq.external_entity_type='location' AND NOT EXISTS(SELECT 1 FROM tj.org_locations WHERE id=mq.candidate_id AND organization_id=conn.organization_id AND is_active)))) THEN RAISE EXCEPTION 'reviewed_candidate_no_longer_active' USING ERRCODE='40001';END IF;
  UPDATE tj.platform_connector_connections SET status='active',settings=settings||jsonb_build_object('onboarding_completed_at',clock_timestamp(),'onboarding_profile',prof.pos_system_key),updated_at=clock_timestamp() WHERE id=conn.id;conn.status:='active';
 END IF;
 SELECT count(*) INTO queue_total FROM tj.platform_connector_match_queue WHERE connection_id=conn.id AND organization_id=conn.organization_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',mq.id,'external_entity_type',mq.external_entity_type,'external_id',mq.external_id,'external_code',mq.external_code,'external_name',mq.external_name,'external_email',mq.external_email,'candidate_type',mq.candidate_type,'candidate_id',mq.candidate_id,'confidence',mq.confidence,'match_method',mq.match_method,'status',CASE WHEN mq.status IN('confirmed','rejected') AND mq.metadata->>'us_onboarding_reviewed' IS DISTINCT FROM 'true' THEN 'needs_review' ELSE mq.status END,'reviewed_at',CASE WHEN mq.metadata->>'us_onboarding_reviewed'='true' THEN mq.reviewed_at ELSE NULL END,'metadata',jsonb_build_object('decision_locked',mq.metadata->>'us_onboarding_reviewed'='true')) ORDER BY mq.external_entity_type,mq.external_name),'[]') INTO queue_json FROM (SELECT * FROM tj.platform_connector_match_queue WHERE connection_id=conn.id AND organization_id=conn.organization_id ORDER BY external_entity_type,external_name,id LIMIT 1000)mq;
 SELECT coalesce(jsonb_agg(jsonb_build_object('user_id',p.user_id,'full_name',p.full_name,'email',p.email) ORDER BY p.full_name),'[]') INTO users_json FROM tj.profiles p JOIN tj.organization_members m ON m.user_id=p.user_id WHERE m.organization_id=conn.organization_id AND m.status='active';
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',l.id,'name',l.name,'code',l.code,'address',l.address,'city',l.city,'province_state',l.province_state,'country',l.country,'is_active',l.is_active) ORDER BY l.name),'[]') INTO locations_json FROM tj.org_locations l WHERE l.organization_id=conn.organization_id AND l.is_active;
 RETURN jsonb_build_object('ok',true,'connector',(SELECT jsonb_build_object('key',c.key,'name',c.name,'variant_key',v.key,'variant_name',v.name,'source_label',prof.source_label,'pos_system_key',prof.pos_system_key) FROM tj.platform_connectors c LEFT JOIN tj.platform_connector_variants v ON v.id=conn.variant_id AND v.connector_id=c.id WHERE c.id=conn.connector_id),
 'connection',jsonb_build_object('id',conn.id,'status',conn.status,'auth_status',conn.auth_status,'last_sync_at',conn.last_sync_at,'last_success_at',conn.last_success_at,'last_error',NULL),'summary',summary,'queue',queue_json,'queue_truncated',queue_total>1000,'queue_total',queue_total,'auto_match',jsonb_build_object('processed',processed,'next_cursor',CASE WHEN processed=500 THEN next_key ELSE NULL END),'candidates',jsonb_build_object('users',users_json,'locations',locations_json));
END $$;
REVOKE ALL ON FUNCTION tj_private.onboarding_normalize(text),tj_private.onboarding_field(jsonb,text[]),tj_private.onboarding_similarity(text,text),tj_private.connector_onboarding(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.connector_onboarding(jsonb) TO authenticated;
CREATE FUNCTION public.tj_connector_onboarding(p_body jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.connector_onboarding(p_body);$$;
REVOKE ALL ON FUNCTION public.tj_connector_onboarding(jsonb) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.tj_connector_onboarding(jsonb) TO authenticated;
