-- All fixtures and workflow mutations roll back.
BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid; src uuid; org uuid; other uuid; prod uuid:=gen_random_uuid(); package uuid:=gen_random_uuid(); comparison uuid:=gen_random_uuid(); project uuid:=gen_random_uuid(); account uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND NOT EXISTS(SELECT 1 FROM tj.platform_admins x WHERE x.user_id=im.source_user_id) LIMIT 1;
 SELECT o.id INTO other FROM tj.organizations o WHERE o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=src AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 IF u IS NULL OR other IS NULL THEN RAISE EXCEPTION 'Management fixtures unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.foreign',other::text,true); PERFORM set_config('test.source',src::text,true); PERFORM set_config('test.package',package::text,true); PERFORM set_config('test.comparison',comparison::text,true);
 INSERT INTO tj.aiq_products(id,organization_id,manufacturer_name,brand_name,model,msrp) VALUES(prod,org,'Rollback fixture','Rollback fixture',prod::text,1000);
 INSERT INTO tj.speciq_projects(id,organization_id,customer_name,project_name) VALUES(project,org,'Rollback fixture','Rollback fixture');
 INSERT INTO tj.speciq_packages(id,organization_id,project_id,package_name,created_by) VALUES(package,org,project,'Rollback fixture',src);
 INSERT INTO tj.ai_product_comparisons(id,organization_id,user_id,winner_product_id) VALUES(comparison,org,src,prod);
 INSERT INTO tj.aicrm_accounts(id,organization_id,company_name) VALUES(account,org,'Rollback fixture');
 INSERT INTO tj.aicrm_opportunities(organization_id,account_id,title,stage,status,opportunity_value,probability) VALUES(org,account,'Rollback fixture','prospecting','open',1000,50);
 INSERT INTO tj.metric_snapshots(organization_id,period_type,period_key,metric_key,actual_value,target_value) VALUES
 (org,'monthly','2099-06','revenue',10000,20000),(org,'monthly','2099-06','avg_order',1000,1000),(org,'monthly','2099-06','floor_conversion',10,20),(org,'monthly','2099-06','walk_ins',100,100),(org,'monthly','2099-06','training_completion',50,100);
 PERFORM set_config('test.hidden_count',(SELECT count(*)::text FROM tj.decision_predictions p WHERE p.organization_id=org AND NOT EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids a WHERE a.prediction_id=p.id)),true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; other uuid:=current_setting('test.foreign')::uuid; r jsonb; id uuid; second uuid; f text; BEGIN
 r:=public.tj_runtime_check_app_access('crm'); IF r->>'allowed' IS NULL THEN RAISE EXCEPTION 'Entitlement response'; END IF;
 r:=public.tj_runtime_evaluate_sla_rules(org); IF r->>'events_created' IS NULL THEN RAISE EXCEPTION 'SLA response'; END IF;
 r:=public.tj_runtime_evaluate_sla_rules(org); IF (r->>'events_created')::int<>0 THEN RAISE EXCEPTION 'Repeat SLA duplicated events'; END IF;
 id:=public.tj_runtime_executive_refresh_command_centre(org); IF id IS NULL THEN RAISE EXCEPTION 'Executive refresh'; END IF;
 r:=public.tj_runtime_executive_answer_question(org,'What are the current sales priorities?'); IF r->>'query_id' IS NULL OR r->>'intent' IS NULL THEN RAISE EXCEPTION 'Executive answer'; END IF;
 PERFORM public.tj_runtime_decision_sync_executive_insights(org);
 r:=public.tj_runtime_decision_generate_operational_forecasts(org); IF (r->>'predictions_generated')::int<>3 THEN RAISE EXCEPTION 'Three forecasts expected: %',r; END IF;
 PERFORM public.tj_runtime_decision_generate_operational_forecasts(org);
 r:=public.tj_runtime_ai_manager_run_cycle(org); IF r->>'new_assignments' IS NULL THEN RAISE EXCEPTION 'Management cycle'; END IF;
 r:=public.tj_runtime_ai_manager_run_cycle(org); IF (r->>'new_assignments')::int<>0 OR (r->>'new_escalations')::int<>0 THEN RAISE EXCEPTION 'Repeat cycle created duplicates'; END IF;
 r:=public.tj_runtime_ai_manager_generate_executive_brief(org,'morning','2099-06-01'); IF r IS NULL THEN RAISE EXCEPTION 'Executive brief'; END IF;
 id:=public.tj_runtime_speciq_add_comparison_winner(current_setting('test.package')::uuid,current_setting('test.comparison')::uuid);
 second:=public.tj_runtime_speciq_add_comparison_winner(current_setting('test.package')::uuid,current_setting('test.comparison')::uuid); IF id IS NULL OR second<>id THEN RAISE EXCEPTION 'Winner idempotency'; END IF;
 FOREACH f IN ARRAY ARRAY['ai_manager_generate_executive_brief','ai_manager_run_cycle','decision_generate_operational_forecasts','decision_sync_executive_insights','executive_refresh_command_centre','evaluate_sla_rules'] LOOP
  BEGIN EXECUTE format('SELECT public.tj_runtime_%I($1)',f) USING other; RAISE EXCEPTION 'Cross-org allowed: %',f; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM public.tj_runtime_executive_answer_question(other,'sales'); RAISE EXCEPTION 'Cross-org answer'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 IF (public.tj_runtime_check_app_access('crm')->>'allowed')::boolean THEN RAISE EXCEPTION 'Unmapped entitlement'; END IF;
 FOREACH f IN ARRAY ARRAY['ai_manager_generate_executive_brief','ai_manager_run_cycle','decision_generate_operational_forecasts','decision_sync_executive_insights','executive_refresh_command_centre','evaluate_sla_rules'] LOOP
  BEGIN EXECUTE format('SELECT public.tj_runtime_%I($1)',f) USING org; RAISE EXCEPTION 'Unmapped allowed: %',f; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM public.tj_runtime_speciq_add_comparison_winner(current_setting('test.package')::uuid,current_setting('test.comparison')::uuid); RAISE EXCEPTION 'Unmapped package'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; f record; BEGIN
 IF (SELECT count(*) FROM tj.decision_predictions p WHERE p.organization_id=org AND NOT EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids a WHERE a.prediction_id=p.id))<>current_setting('test.hidden_count')::int THEN RAISE EXCEPTION 'Withheld predictions changed'; END IF;
 IF EXISTS(SELECT 1 FROM tj.decision_predictions p JOIN tj.decision_cases c ON c.id=p.decision_case_id WHERE p.organization_id=org AND c.source_system='prediction_engine' AND NOT EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids a WHERE a.prediction_id=p.id)) THEN RAISE EXCEPTION 'Generated forecast not registered'; END IF;
 IF (SELECT count(*) FROM tj.speciq_package_products WHERE package_id=current_setting('test.package')::uuid)<>1 THEN RAISE EXCEPTION 'Winner count'; END IF;
 IF (SELECT updated_by FROM tj.speciq_packages WHERE id=current_setting('test.package')::uuid)<>current_setting('test.source')::uuid THEN RAISE EXCEPTION 'Winner mapped audit'; END IF;
 FOR f IN SELECT p.oid,n.nspname,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN('tj_runtime_ai_manager_generate_executive_brief','tj_runtime_ai_manager_run_cycle','tj_runtime_decision_generate_operational_forecasts','tj_runtime_decision_sync_executive_insights','tj_runtime_executive_answer_question','tj_runtime_executive_refresh_command_centre','tj_runtime_evaluate_sla_rules','tj_runtime_check_app_access','tj_runtime_speciq_add_comparison_winner') LOOP
 IF has_function_privilege('anon',f.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous privilege'; END IF;
 END LOOP;
END $$;
UPDATE tj.speciq_packages SET locked=true WHERE id=current_setting('test.package')::uuid;
UPDATE tj.organization_members SET role='member' WHERE organization_id=current_setting('test.org')::uuid AND user_id=current_setting('test.source')::uuid;
SELECT set_config('request.jwt.claim.sub',(SELECT target_user_id::text FROM tj.source_user_identity_map WHERE source_user_id=current_setting('test.source')::uuid AND activation_status='activated' LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; f text; BEGIN
 FOREACH f IN ARRAY ARRAY['ai_manager_generate_executive_brief','ai_manager_run_cycle','decision_generate_operational_forecasts','decision_sync_executive_insights','executive_refresh_command_centre','evaluate_sla_rules'] LOOP
  BEGIN EXECUTE format('SELECT public.tj_runtime_%I($1)',f) USING org; RAISE EXCEPTION 'Nonadmin allowed: %',f; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 END LOOP;
 BEGIN PERFORM public.tj_runtime_speciq_add_comparison_winner(current_setting('test.package')::uuid,current_setting('test.comparison')::uuid); RAISE EXCEPTION 'Locked package accepted'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
