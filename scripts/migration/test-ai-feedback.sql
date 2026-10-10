BEGIN;
DO $$DECLARE u uuid;src uuid;org uuid;foreign_actor uuid;cid uuid;tid uuid;foreign_cid uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO foreign_actor FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR foreign_actor IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.ai_conversations(user_id,organization_id,title) VALUES(src,org,'Rollback feedback') RETURNING id INTO cid;
 INSERT INTO tj.ai_conversation_turns(conversation_id,user_id,role,content) VALUES(cid,src,'user','Bosch warranty unavailable') RETURNING id INTO tid;
 INSERT INTO tj.ai_conversations(user_id,organization_id,title) VALUES(foreign_actor,org,'Rollback foreign') RETURNING id INTO foreign_cid;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.feedback_org',org::text,true);PERFORM set_config('test.feedback_actor',src::text,true);PERFORM set_config('test.feedback_cid',cid::text,true);PERFORM set_config('test.feedback_tid',tid::text,true);PERFORM set_config('test.feedback_foreign',foreign_cid::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE payload jsonb;result jsonb;BEGIN
 payload:=jsonb_build_object('organization_id',current_setting('test.feedback_org'),'conversation_id',current_setting('test.feedback_cid'),'turn_id',current_setting('test.feedback_tid'),'signal_type','correction','correction_text','Warranty details are missing here','routing_snapshot',jsonb_build_object('tier','fast','reason','warranty_query'));
 result:=public.tj_submit_ai_feedback(jsonb_build_array(payload));IF result->>'signals_processed'<>'1' THEN RAISE EXCEPTION 'Signal result failed';END IF;
 BEGIN PERFORM public.tj_submit_ai_feedback(jsonb_build_array(payload||jsonb_build_object('conversation_id',current_setting('test.feedback_foreign'))));RAISE EXCEPTION 'Foreign conversation accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_submit_ai_feedback(jsonb_build_array(payload||jsonb_build_object('organization_id',gen_random_uuid())));RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_submit_ai_feedback(jsonb_build_array(payload||jsonb_build_object('turn_id',gen_random_uuid())));RAISE EXCEPTION 'Foreign turn accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_submit_ai_feedback(jsonb_build_array(payload,payload||jsonb_build_object('signal_type','invalid')));RAISE EXCEPTION 'Bad batch accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_submit_ai_feedback(jsonb_build_array(payload));RAISE EXCEPTION 'Unmapped actor accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF (SELECT count(*) FROM tj.ai_feedback_signals WHERE conversation_id=current_setting('test.feedback_cid')::uuid)<>1 THEN RAISE EXCEPTION 'Failed batch was not atomic';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.ai_routing_weights WHERE user_id=current_setting('test.feedback_actor')::uuid AND organization_id=current_setting('test.feedback_org')::uuid AND signal_keyword='warranty' AND failure_count>=1) THEN RAISE EXCEPTION 'Scoped routing counter failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.ai_knowledge_gaps WHERE organization_id=current_setting('test.feedback_org')::uuid AND sample_conversation_ids=ARRAY[current_setting('test.feedback_cid')::uuid]) THEN RAISE EXCEPTION 'Scoped knowledge gap failed';END IF;
 IF has_function_privilege('anon','public.tj_submit_ai_feedback(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Anon exposed';END IF;
END $$;
ROLLBACK;
