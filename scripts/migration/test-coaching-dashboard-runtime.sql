-- Coaching computation/read fixtures. No AI calls; all writes roll back.
BEGIN;
SET LOCAL statement_timeout='25s';
DO $$ DECLARE u uuid; src uuid; org uuid; foreign_org uuid; other uuid; intervention uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin')
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL
 AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=src AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 SELECT id INTO other FROM tj.source_auth_users WHERE id<>src LIMIT 1;
 IF u IS NULL OR foreign_org IS NULL OR other IS NULL THEN RAISE EXCEPTION 'Coaching identities unavailable'; END IF;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,other,'member','active')
 ON CONFLICT(organization_id,user_id) DO UPDATE SET status='active';
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.foreign',foreign_org::text,true);
 PERFORM set_config('test.source',src::text,true); PERFORM set_config('test.other',other::text,true); PERFORM set_config('test.intervention',intervention::text,true);
 INSERT INTO tj.ai_roleplay_sessions(organization_id,user_id,scenario_type,status,session_score)
 VALUES(org,src,'cold_call','completed',90),(org,src,'cold_call','completed',95),(org,src,'cold_call','completed',85);
 INSERT INTO tj.ai_coaching_interventions(id,organization_id,user_id,trigger_type,diagnosis,due_at)
 VALUES(intervention,org,src,'migration_fixture','Synthetic rollback fixture',now()-interval '1 day');
 INSERT INTO tj.ai_intervention_evaluations(organization_id,intervention_id,status,success,delta,measured_at)
 VALUES(org,intervention,'measured',false,-2,now());
 PERFORM set_config('test.roleplay',(SELECT round(avg(session_score),2)::text FROM tj.ai_roleplay_sessions WHERE organization_id=org AND user_id=src AND status='completed' AND session_score IS NOT NULL AND created_at>=now()-interval '90 days'),true);
 PERFORM set_config('test.active',(SELECT count(*)::text FROM tj.ai_coaching_interventions WHERE organization_id=org AND status IN('recommended','assigned','in_progress')),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; other_org uuid:=current_setting('test.foreign')::uuid; src uuid:=current_setting('test.source')::uuid; other uuid:=current_setting('test.other')::uuid; r jsonb; BEGIN
 r:=tj.phase4_coaching_dashboard(org);
 IF (r->>'active_interventions')::int<>current_setting('test.active')::int
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'latest') i WHERE i->>'id'=current_setting('test.intervention'))
 THEN RAISE EXCEPTION 'Coaching dashboard totals/fixture missing'; END IF;
 IF tj.phase4_coaching_dashboard(other_org) IS NOT NULL THEN RAISE EXCEPTION 'Foreign phase4 dashboard exposed'; END IF;
 r:=tj.phase5_refresh_profile(org,src);
 IF (r->>'roleplay_score')::numeric<>current_setting('test.roleplay')::numeric OR r->>'user_id'<>src::text THEN RAISE EXCEPTION 'Profile roleplay calculation failed'; END IF;
 r:=tj.phase5_rep_plan(org,src);
 IF r->'profile'->>'user_id'<>src::text
 OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'active_interventions') i WHERE i->>'id'=current_setting('test.intervention'))
 THEN RAISE EXCEPTION 'Own rep plan failed'; END IF;
 PERFORM tj.phase5_rep_plan(org,other);
 r:=tj.phase5_manager_dashboard(org);
 IF jsonb_typeof(r->'profiles')<>'array' OR (r->'summary'->>'adaptive_users')::int<2 THEN RAISE EXCEPTION 'Manager dashboard failed'; END IF;
 IF jsonb_typeof(tj.phase5_manager_recommendations(org,1))<>'array' OR jsonb_array_length(tj.phase5_manager_recommendations(org,1))<>1 THEN RAISE EXCEPTION 'Recommendation limit failed'; END IF;
 BEGIN PERFORM tj.phase5_manager_dashboard(other_org); RAISE EXCEPTION 'Foreign manager dashboard allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_manager_recommendations(other_org); RAISE EXCEPTION 'Foreign recommendations allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_refresh_profile(other_org,src); RAISE EXCEPTION 'Foreign profile refresh allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_rep_plan(other_org,src); RAISE EXCEPTION 'Foreign plan allowed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.org')::uuid AND user_id=current_setting('test.source')::uuid;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; src uuid:=current_setting('test.source')::uuid; other uuid:=current_setting('test.other')::uuid; BEGIN
 PERFORM tj.phase5_rep_plan(org,src);
 BEGIN PERFORM tj.phase5_rep_plan(org,other); RAISE EXCEPTION 'Rep accessed another plan'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_refresh_profile(org,other); RAISE EXCEPTION 'Rep changed another profile'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_manager_dashboard(org); RAISE EXCEPTION 'Rep accessed manager dashboard'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.phase5_manager_recommendations(org); RAISE EXCEPTION 'Rep accessed manager recommendations'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF tj.phase4_coaching_dashboard(org) IS NOT NULL THEN RAISE EXCEPTION 'Unmapped phase4 dashboard'; END IF;
 BEGIN PERFORM tj.phase5_rep_plan(org,src); RAISE EXCEPTION 'Unmapped rep plan'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE fn text; BEGIN
 FOREACH fn IN ARRAY ARRAY['phase4_coaching_dashboard(uuid)','phase5_manager_dashboard(uuid)','phase5_manager_recommendations(uuid,integer)','phase5_rep_plan(uuid,uuid)','phase5_refresh_profile(uuid,uuid)'] LOOP
 IF has_function_privilege('anon','tj.'||fn,'EXECUTE') OR has_function_privilege('anon','tj_private.'||fn,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous coaching privilege'; END IF;
 END LOOP;
END $$;
ROLLBACK;
