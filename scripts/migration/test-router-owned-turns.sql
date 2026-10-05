BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid;src uuid;org uuid;other_src uuid;c uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO other_src FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR other_src IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.native',u::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.foreign',c::text,true);
 INSERT INTO tj.ai_conversations(id,user_id,organization_id,title) VALUES(c,other_src,org,'Rollback foreign');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE state jsonb;ctx jsonb;c uuid; BEGIN
 ctx:=public.tj_runtime_my_platform_context();IF ctx->>'source_user_id'<>current_setting('test.source') OR ctx->>'user_id'<>current_setting('test.native') THEN RAISE EXCEPTION 'Identity context mismatch';END IF;
 state:=public.tj_product_conversation_state(NULL,current_setting('test.org')::uuid,'Rollback router');c:=(state->>'conversation_id')::uuid;PERFORM set_config('test.conversation',c::text,true);
 IF public.tj_latest_product_conversation(current_setting('test.org')::uuid)<>c THEN RAISE EXCEPTION 'Latest conversation owner mismatch';END IF;
 BEGIN PERFORM public.aiq_append_router_assistant_turn(c,current_setting('test.native')::uuid,0,'Forbidden browser','Natalie');RAISE EXCEPTION 'Browser assistant write accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_latest_product_conversation(current_setting('test.org')::uuid);RAISE EXCEPTION 'Unmapped latest accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE; SET LOCAL ROLE service_role;
DO $$ DECLARE c uuid:=current_setting('test.conversation')::uuid;u uuid:=current_setting('test.native')::uuid; BEGIN
 PERFORM public.aiq_append_router_assistant_turn(c,u,0,'Rollback assistant answer','Natalie');
 BEGIN PERFORM public.aiq_append_router_assistant_turn(c,u,99,'Stale answer','Natalie');RAISE EXCEPTION 'Stale answer accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_append_router_assistant_turn(current_setting('test.foreign')::uuid,u,0,'Foreign answer','Natalie');RAISE EXCEPTION 'Foreign answer accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_append_router_assistant_turn(c,gen_random_uuid(),0,'Unmapped answer','Natalie');RAISE EXCEPTION 'Unmapped actor accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF (SELECT count(*) FROM tj.ai_conversation_turns WHERE conversation_id=current_setting('test.conversation')::uuid AND role='assistant' AND user_id=current_setting('test.source')::uuid)<>1 THEN RAISE EXCEPTION 'Assistant actor/count mismatch';END IF;
 IF has_table_privilege('authenticated','tj.ai_conversations','SELECT') OR has_table_privilege('authenticated','tj.field_clients','SELECT') OR NOT has_column_privilege('authenticated','tj.field_clients','id','SELECT') THEN RAISE EXCEPTION 'Reference grants too broad or missing';END IF;
END $$;
ROLLBACK;
