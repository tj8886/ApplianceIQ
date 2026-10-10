BEGIN;SET LOCAL statement_timeout='60s';
DO $$DECLARE u uuid;src uuid;org uuid;other_src uuid;other_req uuid;key text:='rollback-'||gen_random_uuid();BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO other_src FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR other_src IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.ai_assistants(assistant_key,label,category,config) VALUES(key,'Rollback assistant','test','{"model_tier":"light"}');
 INSERT INTO tj.ai_requests(organization_id,user_id,assistant_key,prompt,request_status) VALUES(org,other_src,key,'Foreign prompt','pending') RETURNING id INTO other_req;
 PERFORM set_config('test.intel.count',(SELECT count(*)::text FROM tj.intel_news),true);PERFORM set_config('test.recalls.count',(SELECT count(*)::text FROM tj.aiq_recalls),true);PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.ai_key',key,true);PERFORM set_config('test.ai_org',org::text,true);PERFORM set_config('test.ai_target',u::text,true);PERFORM set_config('test.ai_actor',src::text,true);PERFORM set_config('test.ai_foreign',other_req::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE gov jsonb;ctx jsonb;BEGIN
 gov:=public.tj_runtime_ai_submit_request(current_setting('test.ai_org')::uuid,current_setting('test.ai_key'),'Rollback intelligence research','{}');PERFORM set_config('test.ai_request',gov->>'request_id',true);
 ctx:=public.tj_ai_request_context((gov->>'request_id')::uuid,NULL);
 IF ctx->'assistant'->>'assistant_key'<>current_setting('test.ai_key') OR jsonb_typeof(ctx->'knowledge')<>'array' THEN RAISE EXCEPTION 'Context failed';END IF;
 BEGIN PERFORM public.tj_ai_request_context(current_setting('test.ai_foreign')::uuid,NULL);RAISE EXCEPTION 'Foreign request read';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_runtime_ai_submit_request(gen_random_uuid(),current_setting('test.ai_key'),'Foreign org question','{}');RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_function_privilege('authenticated','public.aiq_finish_ai_request(uuid,uuid,jsonb,text,text,integer,text)','EXECUTE') THEN RAISE EXCEPTION 'Browser completion exposed';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_runtime_ai_submit_request(current_setting('test.ai_org')::uuid,current_setting('test.ai_key'),'Unmapped user','{}');RAISE EXCEPTION 'Unmapped accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF (SELECT request_status FROM tj.ai_requests WHERE id=current_setting('test.ai_request')::uuid)<>'pending' OR (SELECT completed_at FROM tj.ai_requests WHERE id=current_setting('test.ai_request')::uuid) IS NOT NULL THEN RAISE EXCEPTION 'Premature completion';END IF;
END $$;
SET LOCAL ROLE service_role;
DO $$BEGIN
 BEGIN PERFORM public.aiq_finish_ai_request(current_setting('test.ai_foreign')::uuid,current_setting('test.ai_target')::uuid,'{}','test','configured-model',1,NULL);RAISE EXCEPTION 'Foreign request finalized';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM public.aiq_finish_ai_request(current_setting('test.ai_request')::uuid,current_setting('test.ai_target')::uuid,'{"mode":"intelligence_research_proposal","requires_review":true,"items":[],"sources":[]}','test','configured-model',12,NULL);
 BEGIN PERFORM public.aiq_finish_ai_request(current_setting('test.ai_request')::uuid,current_setting('test.ai_target')::uuid,'{}','test','configured-model',1,NULL);RAISE EXCEPTION 'Double completion';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF (SELECT request_status FROM tj.ai_requests WHERE id=current_setting('test.ai_request')::uuid)<>'completed' THEN RAISE EXCEPTION 'Completion failed';END IF;
 IF (SELECT count(*) FROM tj.ai_usage_meter WHERE request_id=current_setting('test.ai_request')::uuid AND usage_kind='token' AND quantity=12)<>1 THEN RAISE EXCEPTION 'Usage write failed';END IF;
 IF (SELECT output->>'mode' FROM tj.ai_requests WHERE id=current_setting('test.ai_request')::uuid)<>'intelligence_research_proposal' OR (SELECT count(*) FROM tj.intel_news)<>current_setting('test.intel.count')::bigint OR (SELECT count(*) FROM tj.aiq_recalls)<>current_setting('test.recalls.count')::bigint THEN RAISE EXCEPTION 'Unsafe intelligence persistence';END IF;
 IF has_function_privilege('anon','public.tj_runtime_ai_submit_request(uuid,text,text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Anonymous request exposed';END IF;
END $$;
ROLLBACK;
