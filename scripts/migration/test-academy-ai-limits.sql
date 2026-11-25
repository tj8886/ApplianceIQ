-- Academy AI spending limits: rollback-only checks. Run on a database where
-- 20261125170000_academy_ai_spending_limits.sql is applied (locally:
-- scripts/migration/run-academy-ai-limits-sql.sh). Fails if a learner or a
-- company can go past a limit, if a switch is ignored, or if the private
-- tables or service functions are reachable from clients.
BEGIN;

-- 1. Private storage: RLS on, no policies, no table grants, no client access to service functions.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['academy_ai_platform_controls','academy_ai_company_controls','academy_ai_roleplays','academy_ai_calls'] LOOP
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid=('tj_private.'||t)::regclass) THEN RAISE EXCEPTION 'rls_disabled:%',t; END IF;
  IF EXISTS(SELECT 1 FROM pg_policy WHERE polrelid=('tj_private.'||t)::regclass) THEN RAISE EXCEPTION 'unexpected_policy:%',t; END IF;
  IF has_table_privilege('anon','tj_private.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('authenticated','tj_private.'||t,'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('service_role','tj_private.'||t,'SELECT,INSERT,UPDATE,DELETE') OR has_table_privilege('public','tj_private.'||t,'SELECT') THEN RAISE EXCEPTION 'table_exposed:%',t; END IF;
 END LOOP;
 IF has_function_privilege('anon','public.aiq_academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean)','EXECUTE')
    OR has_function_privilege('authenticated','public.aiq_academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean)','EXECUTE')
    OR has_function_privilege('authenticated','tj_private.academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean)','EXECUTE')
    OR has_function_privilege('authenticated','public.aiq_academy_ai_settle(uuid,text,integer,integer,text)','EXECUTE')
    OR has_function_privilege('anon','public.aiq_academy_ai_settle(uuid,text,integer,integer,text)','EXECUTE')
    OR has_function_privilege('anon','public.tj_runtime_academy_ai_admin(uuid,text,jsonb)','EXECUTE')
    OR has_function_privilege('authenticated','public.aiq_academy_ai_link_roleplay(uuid,text,text)','EXECUTE')
    OR NOT has_function_privilege('authenticated','public.tj_runtime_academy_ai_admin(uuid,text,jsonb)','EXECUTE')
    OR NOT has_function_privilege('service_role','public.aiq_academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean)','EXECUTE') THEN
  RAISE EXCEPTION 'function_grants_wrong';
 END IF;
END $$;

-- 2. Fixtures: a one-seat company with two learners and an owner, plus an outsider and a platform admin.
DO $$ DECLARE users uuid[]; pa uuid; org uuid:=gen_random_uuid(); other uuid:=gen_random_uuid(); BEGIN
 SELECT array_agg(target_user_id ORDER BY target_user_id) INTO users FROM (
  SELECT im.target_user_id FROM tj.source_user_identity_map im
  WHERE tj_private.handoff_source_user(im.target_user_id)=im.source_user_id AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id)
  ORDER BY im.target_user_id LIMIT 4) x;
 SELECT im.target_user_id INTO pa FROM tj.source_user_identity_map im JOIN tj.platform_admins a ON a.user_id=im.source_user_id WHERE tj_private.handoff_source_user(im.target_user_id)=im.source_user_id LIMIT 1;
 IF coalesce(array_length(users,1),0)<4 OR pa IS NULL THEN RAISE EXCEPTION 'identity_fixtures_unavailable'; END IF;
 INSERT INTO tj.organizations(id,name,slug,status) VALUES(org,'Academy AI limits rollback','academy-ai-'||org,'active'),(other,'Other rollback','academy-ai-'||other,'active');
 INSERT INTO tj.organization_members(organization_id,user_id,role,status)
  SELECT org,tj_private.handoff_source_user(u),r,'active' FROM unnest(users[1:3],ARRAY['member','member','owner']) AS f(u,r);
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(other,tj_private.handoff_source_user(users[4]),'member','active');
 INSERT INTO tj.org_app_entitlements(organization_id,app_key,tier,seats_included,status) VALUES(org,'iq_academy','starter',1,'active');
 PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.a',users[1]::text,true);PERFORM set_config('test.b',users[2]::text,true);
 PERFORM set_config('test.owner',users[3]::text,true);PERFORM set_config('test.outsider',users[4]::text,true);PERFORM set_config('test.pa',pa::text,true);
END $$;
CREATE FUNCTION pg_temp.res(who text,feature text,bytes integer DEFAULT 4000,session_key text DEFAULT NULL,new_turn boolean DEFAULT false,max_out integer DEFAULT 500) RETURNS jsonb
LANGUAGE sql AS $$ SELECT public.aiq_academy_ai_reserve(current_setting('test.'||who)::uuid,current_setting('test.org')::uuid,feature,
 CASE WHEN feature='grading' THEN 'claude-sonnet-5-5' ELSE 'claude-haiku-5-5' END,max_out,bytes,session_key,new_turn) $$;
CREATE FUNCTION pg_temp.admin(who text,action text,payload jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE plpgsql AS $$ DECLARE r jsonb; BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.'||who),true);
 SET LOCAL ROLE authenticated; r:=public.tj_runtime_academy_ai_admin(current_setting('test.org')::uuid,action,payload); SET LOCAL ROLE service_role; RETURN r; END $$;
SET LOCAL ROLE service_role;

-- 3. Service-only entry, identity and model checks.
DO $$ DECLARE r jsonb; BEGIN
 SET LOCAL ROLE authenticated;
 BEGIN PERFORM pg_temp.res('a','trainer'); RAISE EXCEPTION 'reserve_open_to_clients'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 SET LOCAL ROLE service_role;
 BEGIN PERFORM public.aiq_academy_ai_reserve(current_setting('test.a')::uuid,current_setting('test.org')::uuid,'trainer','claude-sonnet-5-5',500,4000); RAISE EXCEPTION 'browser_model_accepted'; EXCEPTION WHEN invalid_parameter_value THEN IF SQLERRM<>'model_not_allowed_for_feature' THEN RAISE; END IF; END;
 BEGIN PERFORM public.aiq_academy_ai_reserve(current_setting('test.a')::uuid,current_setting('test.org')::uuid,'grading','claude-haiku-5-5',500,4000,'h2h:'||gen_random_uuid()); RAISE EXCEPTION 'grading_model_not_pinned'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.aiq_academy_ai_reserve(current_setting('test.a')::uuid,current_setting('test.org')::uuid,'trainer','claude-opus-5-5',500,4000); RAISE EXCEPTION 'unpriced_model_accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM pg_temp.res('a','trainer',4000,NULL,false,4000); RAISE EXCEPTION 'answer_cap_not_enforced'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM pg_temp.res('a','freeform'); RAISE EXCEPTION 'unknown_feature_accepted'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM pg_temp.res('outsider','trainer'); RAISE EXCEPTION 'outsider_accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 r:=pg_temp.res('a','trainer'); IF r->>'reason' IS DISTINCT FROM 'budget_not_set' THEN RAISE EXCEPTION 'unset_budget_not_paused: %',r; END IF;
END $$;

-- 4. Only the company admin sets the budget; members and outsiders cannot.
DO $$ DECLARE r jsonb; BEGIN
 BEGIN PERFORM pg_temp.admin('a','set_budget','{"monthly_budget_usd":1000}'); RAISE EXCEPTION 'member_set_budget'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM pg_temp.admin('outsider','status'); RAISE EXCEPTION 'outsider_read_status'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM pg_temp.admin('owner','set_budget','{"monthly_budget_usd":-1}'); RAISE EXCEPTION 'negative_budget'; EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 r:=pg_temp.admin('owner','set_budget','{"monthly_budget_usd":50}'); IF (r->>'monthly_budget_usd')::numeric<>50 THEN RAISE EXCEPTION 'budget_not_saved'; END IF;
 RESET ROLE; IF NOT EXISTS(SELECT 1 FROM tj_private.company_admin_audit WHERE organization_id=current_setting('test.org')::uuid AND action='academy_ai_set_budget') THEN RAISE EXCEPTION 'budget_change_not_audited'; END IF; SET LOCAL ROLE service_role;
END $$;

-- 5. Trainer questions: 200 per learner, failed calls do not count, one-seat pool is shared.
DO $$ DECLARE r jsonb; i integer; BEGIN
 r:=pg_temp.res('a','trainer'); PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'failed',0,0,'provider_rejected');
 FOR i IN 1..200 LOOP
  r:=pg_temp.res('a','trainer'); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'question_% refused early: %',i,r; END IF;
  PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',1000,200);
 END LOOP;
 r:=pg_temp.res('a','trainer'); IF r->>'reason' IS DISTINCT FROM 'trainer_question_limit' THEN RAISE EXCEPTION 'learner_passed_question_limit: %',r; END IF;
 r:=pg_temp.res('a','content_ideas'); IF r->>'reason' IS DISTINCT FROM 'trainer_question_limit' THEN RAISE EXCEPTION 'content_ideas_bypass: %',r; END IF;
 r:=pg_temp.res('b','trainer'); IF r->>'reason' IS DISTINCT FROM 'company_trainer_question_pool' THEN RAISE EXCEPTION 'company_passed_question_pool: %',r; END IF;
 RESET ROLE; UPDATE tj.org_app_entitlements SET seats_included=2 WHERE organization_id=current_setting('test.org')::uuid; SET LOCAL ROLE service_role;
 r:=pg_temp.res('b','trainer'); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'second_seat_not_pooled: %',r; END IF;
 PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',1000,200);
 RESET ROLE; IF (SELECT cost_usd FROM tj_private.academy_ai_calls WHERE id=(r->>'call_id')::uuid)<>0.0002 THEN RAISE EXCEPTION 'haiku_cost_wrong'; END IF; SET LOCAL ROLE service_role;
END $$;

-- 6. Graded role-plays: 10 per learner per month.
DO $$ DECLARE r jsonb; i integer; BEGIN
 FOR i IN 1..10 LOOP
  r:=pg_temp.res('a','showroom',4000,'kpi:'||gen_random_uuid()); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'roleplay_% refused early: %',i,r; END IF;
  PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',500,100);
 END LOOP;
 r:=pg_temp.res('a','beat_the_bot',4000,'perf:'||gen_random_uuid()); IF r->>'reason' IS DISTINCT FROM 'graded_roleplay_limit' THEN RAISE EXCEPTION 'learner_passed_graded_limit: %',r; END IF;
 r:=pg_temp.res('a','grading',4000,'h2h:'||gen_random_uuid()); IF r->>'reason' IS DISTINCT FROM 'graded_roleplay_limit' THEN RAISE EXCEPTION 'h2h_grading_bypass: %',r; END IF;
 -- The KPI role-play's temporary key moves to its session id, owner only.
 r:=pg_temp.res('b','showroom',4000,'kpi:00000000-0000-4000-8000-000000000aaa');
 IF NOT public.aiq_academy_ai_link_roleplay(current_setting('test.b')::uuid,'kpi:00000000-0000-4000-8000-000000000aaa','kpi:00000000-0000-4000-8000-000000000bbb') THEN RAISE EXCEPTION 'link_failed'; END IF;
 IF public.aiq_academy_ai_link_roleplay(current_setting('test.a')::uuid,'kpi:00000000-0000-4000-8000-000000000bbb','kpi:00000000-0000-4000-8000-000000000ccc') THEN RAISE EXCEPTION 'link_hijacked'; END IF;
 r:=pg_temp.res('b','showroom',4000,'kpi:00000000-0000-4000-8000-000000000bbb',true); IF NOT (r->>'allowed')::boolean OR (r->>'turns')::int<>1 THEN RAISE EXCEPTION 'linked_session_not_continued: %',r; END IF;
 -- A failed opening gives the role-play back.
 r:=pg_temp.res('b','beat_the_bot',4000,'perf:'||gen_random_uuid()); PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'failed',0,0,'provider_rejected');
 RESET ROLE; IF EXISTS(SELECT 1 FROM tj_private.academy_ai_roleplays WHERE id=(r->>'roleplay_id')::uuid) THEN RAISE EXCEPTION 'failed_opening_counted'; END IF; SET LOCAL ROLE service_role;
END $$;

-- 7. Role-play turns and minutes; grading once, after the role-play stops.
DO $$ DECLARE r jsonb; i integer; k text:='proxy:'||gen_random_uuid(); g text:='perf:'||gen_random_uuid(); BEGIN
 FOR i IN 1..20 LOOP
  r:=pg_temp.res('b','showroom',4000,k,true); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'turn_% refused early: %',i,r; END IF;
  PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',500,100);
 END LOOP;
 r:=pg_temp.res('b','showroom',4000,k,true); IF r->>'reason' IS DISTINCT FROM 'roleplay_turn_limit' THEN RAISE EXCEPTION 'learner_passed_turn_limit: %',r; END IF;
 r:=pg_temp.res('b','grading',4000,k); IF r->>'reason' IS DISTINCT FROM 'not_gradable' THEN RAISE EXCEPTION 'ungraded_session_graded: %',r; END IF;
 BEGIN PERFORM pg_temp.res('a','showroom',4000,k,true); RAISE EXCEPTION 'session_hijacked'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 r:=pg_temp.res('b','beat_the_bot',4000,g); PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',500,100);
 RESET ROLE; UPDATE tj_private.academy_ai_roleplays SET started_at=now()-interval '15 minutes 1 second' WHERE session_key=g; SET LOCAL ROLE service_role;
 r:=pg_temp.res('b','beat_the_bot',4000,g,true); IF r->>'reason' IS DISTINCT FROM 'roleplay_time_limit' THEN RAISE EXCEPTION 'learner_passed_time_limit: %',r; END IF;
 r:=pg_temp.res('b','grading',20000,g,false,1500); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'stopped_roleplay_not_graded: %',r; END IF;
 PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',1000,500);
 RESET ROLE; IF (SELECT cost_usd FROM tj_private.academy_ai_calls WHERE id=(r->>'call_id')::uuid)<>0.007 THEN RAISE EXCEPTION 'sonnet_cost_wrong'; END IF; SET LOCAL ROLE service_role;
 BEGIN PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'ok',1,1); RAISE EXCEPTION 'double_settle'; EXCEPTION WHEN serialization_failure THEN NULL; END;
 r:=pg_temp.res('b','grading',20000,g,false,1500); IF r->>'reason' IS DISTINCT FROM 'already_graded' THEN RAISE EXCEPTION 'graded_twice: %',r; END IF;
 r:=pg_temp.res('b','beat_the_bot',4000,g,false); IF r->>'reason' IS DISTINCT FROM 'roleplay_ended' THEN RAISE EXCEPTION 'turn_after_grade: %',r; END IF;
END $$;

-- 8. Monthly dollar budget: reservations at maximum cost never let spend pass the budget.
DO $$ DECLARE r jsonb; spent numeric; budget numeric; i integer; refused boolean:=false; BEGIN
 RESET ROLE; SELECT sum(coalesce(cost_usd,reserved_usd)) INTO spent FROM tj_private.academy_ai_calls WHERE organization_id=current_setting('test.org')::uuid AND status IN ('reserved','settled','unknown'); SET LOCAL ROLE service_role;
 budget:=ceil((spent+0.10)*100)/100;
 PERFORM pg_temp.admin('owner','set_budget',jsonb_build_object('monthly_budget_usd',budget));
 FOR i IN 1..10 LOOP
  r:=pg_temp.res('b','trainer',400000);
  IF NOT (r->>'allowed')::boolean THEN IF r->>'reason'<>'company_budget_reached' THEN RAISE EXCEPTION 'wrong_budget_reason: %',r; END IF; refused:=true; EXIT; END IF;
  IF i%2=0 THEN PERFORM public.aiq_academy_ai_settle((r->>'call_id')::uuid,'unknown',0,0,'timeout'); END IF;
 END LOOP;
 RESET ROLE; SELECT sum(coalesce(cost_usd,reserved_usd)) INTO spent FROM tj_private.academy_ai_calls WHERE organization_id=current_setting('test.org')::uuid AND status IN ('reserved','settled','unknown'); SET LOCAL ROLE service_role;
 IF NOT refused OR spent>budget THEN RAISE EXCEPTION 'company_passed_budget: spent % budget %',spent,budget; END IF;
 IF (pg_temp.admin('owner','status')->>'spent_usd')::numeric>budget THEN RAISE EXCEPTION 'status_spend_wrong'; END IF;
 PERFORM pg_temp.admin('owner','set_budget','{"monthly_budget_usd":1000}');
END $$;

-- 9. Off switches: per company (company admin) and for everyone (platform admin only).
DO $$ DECLARE r jsonb; BEGIN
 PERFORM pg_temp.admin('owner','set_enabled','{"enabled":false}');
 r:=pg_temp.res('b','trainer'); IF r->>'reason' IS DISTINCT FROM 'ai_paused_company' THEN RAISE EXCEPTION 'company_switch_ignored: %',r; END IF;
 PERFORM pg_temp.admin('owner','set_enabled','{"enabled":true}');
 BEGIN PERFORM pg_temp.admin('owner','set_platform_enabled','{"enabled":false}'); RAISE EXCEPTION 'company_admin_flipped_platform'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM pg_temp.admin('pa','set_platform_enabled','{"enabled":false}');
 r:=pg_temp.res('b','trainer'); IF r->>'reason' IS DISTINCT FROM 'ai_paused_platform' THEN RAISE EXCEPTION 'platform_switch_ignored: %',r; END IF;
 PERFORM pg_temp.admin('pa','set_platform_enabled','{"enabled":true}');
 r:=pg_temp.res('b','trainer'); IF NOT (r->>'allowed')::boolean THEN RAISE EXCEPTION 'switch_not_restored: %',r; END IF;
END $$;

-- 10. Costs are recorded per call by company; usage shows to learners and admins.
DO $$ DECLARE r jsonb; BEGIN
 RESET ROLE; IF EXISTS(SELECT 1 FROM tj_private.academy_ai_calls WHERE organization_id=current_setting('test.org')::uuid AND status='settled' AND (cost_usd IS NULL OR input_tokens IS NULL)) THEN RAISE EXCEPTION 'settled_call_without_cost'; END IF; SET LOCAL ROLE service_role;
 r:=pg_temp.admin('a','my_usage'); IF (r->>'trainer_questions_used')::int<>200 OR (r->>'graded_roleplays_used')::int<>10 THEN RAISE EXCEPTION 'my_usage_wrong: %',r; END IF;
 r:=pg_temp.admin('owner','status'); IF (r->>'trainer_questions_pool')::int<>400 OR (r->'cost_by_feature'->>'grading')::numeric<>0.007 THEN RAISE EXCEPTION 'status_wrong: %',r; END IF;
END $$;
ROLLBACK;
SELECT 'PASS: private storage, service-only reserve/settle, pinned models and answer caps, admin-only budget, 200 questions and 10 graded role-plays per learner, shared seat pool, 20 turns / 15 minutes, single grading, budget never exceeded, company and platform switches, cost by company; fixtures rolled back' AS result;
