BEGIN; SET LOCAL statement_timeout='25s';
DO $$ DECLARE u uuid; src uuid; org uuid; foreign_org uuid; i uuid:=gen_random_uuid(); fi uuid:=gen_random_uuid(); entity uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=src AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 IF u IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Batch identities unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.foreign',foreign_org::text,true); PERFORM set_config('test.source',src::text,true); PERFORM set_config('test.intervention',i::text,true); PERFORM set_config('test.foreign_i',fi::text,true); PERFORM set_config('test.entity',entity::text,true);
 INSERT INTO tj.ai_coaching_interventions(id,organization_id,user_id,trigger_type,diagnosis) VALUES(i,org,src,'migration_fixture','Rollback batch fixture'),(fi,foreign_org,src,'migration_fixture','Hidden rollback fixture');
 INSERT INTO tj.ai_intervention_steps(intervention_id,step_order,step_type,title) VALUES(i,1,'lesson','Rollback step'),(i,2,'review','Rollback review');
 INSERT INTO tj.ai_intervention_evaluations(organization_id,intervention_id,evaluation_due_at) VALUES(org,i,now()+interval '1 day');
 INSERT INTO tj.platform_identity_links(organization_id,entity_type,canonical_id,canonical_table,source_system,source_table,source_record_id) VALUES(org,'contact',entity,'contacts','migration_fixture','contacts',entity::text);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; foreign_org uuid:=current_setting('test.foreign')::uuid; src uuid:=current_setting('test.source')::uuid; i uuid:=current_setting('test.intervention')::uuid; fi uuid:=current_setting('test.foreign_i')::uuid; r jsonb; BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.platform_resolve_identity(org,'contact','migration_fixture',p_source_record_id=>current_setting('test.entity')) WHERE canonical_id=current_setting('test.entity')::uuid) THEN RAISE EXCEPTION 'Identity resolution failed'; END IF;
 IF EXISTS(SELECT 1 FROM tj.platform_resolve_identity(foreign_org,'contact')) THEN RAISE EXCEPTION 'Foreign identity lookup'; END IF;
 r:=tj.phase5_select_strategy(org,src,NULL); IF r->>'strategy_key' IS NULL OR jsonb_array_length(r->'sequence')<>4 THEN RAISE EXCEPTION 'Strategy selection failed'; END IF;
 r:=tj.phase4_complete_step(i,1); IF (r->>'remaining_steps')::int<>1 OR (r->>'intervention_completed')::boolean THEN RAISE EXCEPTION 'Step progress failed'; END IF;
 r:=tj.phase4_complete_step(i,2); IF NOT (r->>'intervention_completed')::boolean THEN RAISE EXCEPTION 'Step completion failed'; END IF;
 r:=tj.phase4_evaluate_intervention(i,false); IF r->>'status'<>'not_due' THEN RAISE EXCEPTION 'Evaluation due gate failed'; END IF;
 r:=tj.phase4_evaluate_intervention(i,true); IF r->>'status'<>'insufficient_data' THEN RAISE EXCEPTION 'Missing evidence gate failed'; END IF;
 PERFORM tj.phase4_generate_coaching(org,src,CURRENT_DATE);
 PERFORM tj.phase5_generate_adaptive_coaching(org,src,CURRENT_DATE);
 PERFORM tj.phase4_generate_org_coaching(org,CURRENT_DATE,1);
 PERFORM tj.phase5_generate_org_adaptive_coaching(org,CURRENT_DATE,1);
 PERFORM tj.phase4_evaluate_due_org(org,1);
 PERFORM tj.performance_get_next_scenario(org);
 PERFORM tj.performance_start_adaptive_roleplay(org,'you_sell');
 BEGIN PERFORM tj.phase4_complete_step(fi,1); RAISE EXCEPTION 'Foreign completion'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase4_evaluate_intervention(fi,true); RAISE EXCEPTION 'Foreign evaluation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase4_generate_coaching(foreign_org,src); RAISE EXCEPTION 'Foreign generation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_generate_adaptive_coaching(foreign_org,src); RAISE EXCEPTION 'Foreign adaptation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase4_generate_org_coaching(foreign_org); RAISE EXCEPTION 'Foreign org generation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_generate_org_adaptive_coaching(foreign_org); RAISE EXCEPTION 'Foreign org adaptation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase4_evaluate_due_org(foreign_org); RAISE EXCEPTION 'Foreign org evaluation'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_select_strategy(foreign_org,src,NULL); RAISE EXCEPTION 'Foreign strategy'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.performance_get_next_scenario(foreign_org); RAISE EXCEPTION 'Foreign scenario'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.performance_start_adaptive_roleplay(foreign_org); RAISE EXCEPTION 'Foreign roleplay'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT p.oid,n.nspname,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN('tj','tj_private') AND p.proname IN('phase4_generate_coaching','phase4_generate_org_coaching','phase4_evaluate_due_org','phase4_evaluate_intervention','phase4_complete_step','phase5_generate_adaptive_coaching','phase5_generate_org_adaptive_coaching','phase5_select_strategy','performance_get_next_scenario','performance_start_adaptive_roleplay','platform_resolve_identity') LOOP
 IF has_function_privilege('anon',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous batch privilege'; END IF;
 END LOOP;
END $$;
ROLLBACK;
