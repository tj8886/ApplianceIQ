BEGIN;SET LOCAL statement_timeout='30s';
DO $$DECLARE native uuid;actor uuid;org uuid:=gen_random_uuid();other uuid:=gen_random_uuid();course_key text;req uuid:=gen_random_uuid();p jsonb;r jsonb;r2 jsonb;id1 bigint;feed jsonb;n int;snap uuid;
BEGIN
 SELECT target_user_id,source_user_id INTO native,actor FROM tj.source_user_identity_map i WHERE activation_status='activated' AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=i.source_user_id) LIMIT 1;
 SELECT c.course_key INTO course_key FROM tj.iq_courses c ORDER BY id LIMIT 1;
 INSERT INTO tj.organizations(id,name,slug) VALUES(org,'Rollback learning',org::text),(other,'Rollback foreign',other::text);
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'owner','active');
 INSERT INTO tj.org_app_entitlements(organization_id,app_key,status) VALUES(org,'iq_academy','active');
 -- Isolate the fixture context without modifying live memberships after rollback.
 UPDATE tj.organization_members SET status='suspended' WHERE user_id=actor AND organization_id<>org;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);EXECUTE 'SET LOCAL ROLE authenticated';
 p:=jsonb_build_object('action','record','request_id',req,'event_type','course_open','course_key',course_key,'content','Untrusted course title');r:=public.tj_runtime_academy_learning(p);r2:=public.tj_runtime_academy_learning(p);IF r<>r2 OR r->>'saved'<>'true' THEN RAISE EXCEPTION 'Save/retry failed';END IF;id1:=(r->>'event_id')::bigint;
 BEGIN PERFORM public.tj_runtime_academy_learning(p||jsonb_build_object('user_id',gen_random_uuid()));RAISE EXCEPTION 'Actor spoof accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.tj_runtime_academy_learning(p||jsonb_build_object('content','Conflicting replay'));RAISE EXCEPTION 'Replay conflict accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.tj_runtime_academy_learning(p||jsonb_build_object('request_id',gen_random_uuid(),'event_type','quiz_pass'));RAISE EXCEPTION 'Invented completion accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.tj_runtime_academy_learning(jsonb_build_object('action','record','request_id',gen_random_uuid(),'event_type','ai_question','course_key',course_key,'content','Rollback question'));
 feed:=public.tj_runtime_academy_learning('{}');IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(feed->'events') e WHERE (e->>'id')::bigint=id1) THEN RAISE EXCEPTION 'Analytics receipt missing';END IF;
 EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM tj.academy_learning_events e JOIN tj.iq_courses c ON c.course_key=e.course_key WHERE e.id=id1 AND e.user_id=actor AND e.content=c.name AND e.pillar=c.pillar AND e.created_at IS NOT NULL) THEN RAISE EXCEPTION 'Source identity/course/date invalid';END IF;
 IF (SELECT count(*) FROM tj_private.academy_record_events WHERE source_user_id=actor AND request_id=req)<>1 OR (tj_private.command_centre_academy_evidence(org)->'learning_activity'->>'received_events')::int<>2 OR (tj_private.command_centre_academy_evidence(other)->'learning_activity'->>'received_events')::int<>0 THEN RAISE EXCEPTION 'History/report scopes invalid';END IF;
 snap:=tj_private.command_centre_rebuild(org,actor);IF NOT EXISTS(SELECT 1 FROM tj.executive_intelligence_snapshots WHERE id=snap AND (metrics->'training'->'learning_activity'->>'received_events')::int=2) THEN RAISE EXCEPTION 'Learning snapshot publication failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=org) THEN RAISE EXCEPTION 'Report enqueue missing';END IF;
 UPDATE tj.organization_members SET status='suspended' WHERE user_id=actor;EXECUTE 'SET LOCAL ROLE authenticated';BEGIN PERFORM public.tj_runtime_academy_learning('{}');RAISE EXCEPTION 'Suspended access accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;EXECUTE 'RESET ROLE';
 IF has_function_privilege('anon','public.tj_runtime_academy_learning(jsonb)','EXECUTE') OR has_sequence_privilege('authenticated','tj_private.academy_learning_event_id_seq','USAGE') THEN RAISE EXCEPTION 'Private access leak';END IF;
END $$;
SELECT jsonb_build_object('passed',true,'fixtures_persisted',0,'checks',jsonb_build_array('mapped identity','authoritative course context','receipt timestamp','idempotent replay','actor spoof/conflicting replay/false completion denial','saved analytics read','organization report scope','refresh enqueue','suspended/anonymous denial')) verification;
ROLLBACK;
