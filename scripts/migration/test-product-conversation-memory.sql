BEGIN;SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid;src uuid;org uuid;other_src uuid;c uuid:=gen_random_uuid();BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO other_src FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR other_src IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.foreign_conversation',c::text,true);
 INSERT INTO tj.ai_conversations(id,user_id,organization_id,title) VALUES(c,other_src,org,'Rollback other owner');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE state jsonb;result jsonb;c uuid; BEGIN
 state:=public.tj_product_conversation_state(NULL,current_setting('test.org')::uuid,'Rollback conversation');c:=(state->>'conversation_id')::uuid;PERFORM set_config('test.conversation',c::text,true);
 IF state->>'memory_version'<>'0' THEN RAISE EXCEPTION 'Initial version';END IF;
 result:=public.tj_commit_product_conversation(c,0,'Fridge budget $1500','{"category":"refrigeration","budget_max":1500,"opening_width":30,"finish":"black stainless"}','["MODEL123"]');
 IF result->>'memory_version'<>'1' OR result->'profile'->>'budget_max'<>'1500' OR result->>'completeness_score'<>'54' THEN RAISE EXCEPTION 'Atomic result mismatch: %',result;END IF;
 BEGIN PERFORM public.tj_commit_product_conversation(c,0,'Stale write','{}');RAISE EXCEPTION 'Stale write accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 result:=public.tj_commit_product_conversation(c,1,'Updated budget $1800','{"budget_max":1800,"must_have":["quiet"]}');
 IF result->>'memory_version'<>'2' OR jsonb_array_length(result->'contradictions')<>1 OR result->>'stage'<>'qualification' THEN RAISE EXCEPTION 'Merged facts/stage';END IF;
 BEGIN PERFORM public.tj_commit_product_conversation(c,2,'Bad fact','{"service_role":"forged"}');RAISE EXCEPTION 'Unknown key accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.tj_commit_product_conversation(c,2,'Bad number','{"budget_max":false}');RAISE EXCEPTION 'Boolean number accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM public.tj_product_conversation_state(current_setting('test.foreign_conversation')::uuid,NULL);RAISE EXCEPTION 'Foreign conversation read';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.tj_commit_product_conversation(current_setting('test.foreign_conversation')::uuid,0,'Foreign message','{}');RAISE EXCEPTION 'Foreign conversation write';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_product_conversation_state(c,NULL);RAISE EXCEPTION 'Unmapped conversation';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ DECLARE c uuid:=current_setting('test.conversation')::uuid;BEGIN
 IF (SELECT count(*) FROM tj.ai_conversation_turns WHERE conversation_id=c)<>2 OR EXISTS(SELECT 1 FROM tj.ai_conversation_turns WHERE conversation_id=c AND user_id<>current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Turn count/source actor';END IF;
 IF (SELECT memory_version FROM tj.ai_conversation_memory WHERE conversation_id=c)<>2 THEN RAISE EXCEPTION 'Failed updates changed memory';END IF;
 IF has_table_privilege('authenticated','tj.ai_conversations','INSERT') OR has_table_privilege('authenticated','tj.ai_conversation_turns','INSERT') THEN RAISE EXCEPTION 'Direct conversation writes exposed';END IF;
END $$;
ROLLBACK;
