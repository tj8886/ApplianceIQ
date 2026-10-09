BEGIN;
SET LOCAL statement_timeout='15s';
DO $$DECLARE actor uuid;native uuid;other_actor uuid;own_conversation uuid;foreign_conversation uuid;own_turn uuid;foreign_turn uuid;BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,native FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO other_actor FROM tj.source_auth_users WHERE id<>actor LIMIT 1;
 IF native IS NULL OR other_actor IS NULL THEN RAISE EXCEPTION 'missing_identity_fixture';END IF;
 INSERT INTO tj.ai_conversations(user_id,title) VALUES(actor,'Rollback analytics ownership fixture') RETURNING id INTO own_conversation;
 INSERT INTO tj.ai_conversations(user_id,title) VALUES(other_actor,'Rollback analytics foreign fixture') RETURNING id INTO foreign_conversation;
 INSERT INTO tj.ai_conversation_turns(conversation_id,user_id,role,content,metadata) VALUES(own_conversation,actor,'assistant','PRIVATE_OWNER_RESPONSE','{"tier":"cached"}') RETURNING id INTO own_turn;
 INSERT INTO tj.ai_conversation_turns(conversation_id,user_id,role,content,metadata) VALUES(foreign_conversation,other_actor,'assistant','PRIVATE_FOREIGN_RESPONSE','{"tier":"cached"}') RETURNING id INTO foreign_turn;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 PERFORM set_config('test.analytics.own',own_turn::text,true);PERFORM set_config('test.analytics.foreign',foreign_turn::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$BEGIN
 IF (SELECT count(*) FROM tj.ai_conversation_turns WHERE id=current_setting('test.analytics.own')::uuid)<>1 OR EXISTS(SELECT 1 FROM tj.ai_conversation_turns WHERE id=current_setting('test.analytics.foreign')::uuid) THEN RAISE EXCEPTION 'owner_scope_failed';END IF;
 IF has_table_privilege('authenticated','tj.ai_response_cache','SELECT') OR has_any_column_privilege('authenticated','tj.ai_response_cache','SELECT') THEN RAISE EXCEPTION 'global_cache_opened';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF EXISTS(SELECT 1 FROM tj.ai_conversation_turns WHERE id IN(current_setting('test.analytics.own')::uuid,current_setting('test.analytics.foreign')::uuid)) THEN RAISE EXCEPTION 'unmapped_scope_failed';END IF;
END $$;
ROLLBACK;
SELECT 'PASS: native owner sees own cached conversation only; other owner/unmapped denied; shared cache remains private; fixtures rolled back' result;
