BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid;src uuid;org uuid;other_src uuid;f uuid:=gen_random_uuid();BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 SELECT id INTO other_src FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR other_src IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('test.native',u::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.foreign',f::text,true);
 INSERT INTO tj.ai_roleplay_sessions(id,user_id,organization_id,scenario_type) VALUES(f,other_src,org,'cold_call');
END $$;
SET LOCAL ROLE service_role;
DO $$ DECLARE r jsonb;c uuid;BEGIN
 r:=public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,NULL,current_setting('test.org')::uuid,NULL,'{"scenario_type":"cold_call","transcript":[{"role":"customer","content":"Rollback opening"}],"kpi_scores":{}}');c:=(r->>'id')::uuid;PERFORM set_config('test.session',c::text,true);
 r:=public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,c,NULL,'[{"role":"customer","content":"Rollback opening"}]','{"transcript":[{"role":"customer","content":"Rollback opening"},{"role":"rep","content":"Rollback response"}],"total_turns":1}');
 BEGIN PERFORM public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,c,NULL,'[]','{}');RAISE EXCEPTION 'Stale transcript accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,current_setting('test.foreign')::uuid,NULL,'[]','{}');RAISE EXCEPTION 'Foreign session accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_commit_roleplay_session(gen_random_uuid(),c,NULL,'[]','{}');RAISE EXCEPTION 'Unmapped actor accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,NULL,current_setting('test.org')::uuid,NULL,'{"scenario_type":"cold_call","transcript":[{"content":"Missing role"}]}');RAISE EXCEPTION 'Invalid role accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 r:=public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,c,NULL,'[{"role":"customer","content":"Rollback opening"},{"role":"rep","content":"Rollback response"}]','{"status":"completed","session_score":null,"feedback":"Unknown score"}');
 BEGIN PERFORM public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,c,NULL,'[]','{}');RAISE EXCEPTION 'Completed session edited';EXCEPTION WHEN serialization_failure THEN NULL;END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub',current_setting('test.native'),true) IS NOT NULL AS identity_set;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.ai_roleplay_sessions WHERE id=current_setting('test.session')::uuid AND user_id=current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Own session hidden';END IF;
 IF EXISTS(SELECT 1 FROM tj.ai_roleplay_sessions WHERE id=current_setting('test.foreign')::uuid) THEN RAISE EXCEPTION 'Foreign session readable';END IF;
 BEGIN PERFORM public.aiq_commit_roleplay_session(current_setting('test.native')::uuid,current_setting('test.session')::uuid,NULL,'[]','{}');RAISE EXCEPTION 'Browser commit accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF EXISTS(SELECT 1 FROM tj.ai_roleplay_sessions) OR EXISTS(SELECT 1 FROM tj.performance_scenarios) OR EXISTS(SELECT 1 FROM tj.performance_roleplay_links) THEN RAISE EXCEPTION 'Unmapped training read';END IF;
END $$;
RESET ROLE;
DO $$BEGIN IF has_table_privilege('authenticated','tj.ai_roleplay_sessions','INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Browser session writes granted';END IF;END $$;
ROLLBACK;
