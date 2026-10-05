-- Command Centre positives and access checks; all business writes roll back.
BEGIN; SET LOCAL statement_timeout='25s';
DO $$ DECLARE u uuid; src uuid; org uuid; foreign_org uuid; c uuid:=gen_random_uuid(); fc uuid:=gen_random_uuid(); a uuid:=gen_random_uuid(); fa uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); hidden uuid:=gen_random_uuid(); metric text:='migration-'||gen_random_uuid()::text; BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND NOT EXISTS(SELECT 1 FROM tj.platform_admins x WHERE x.user_id=im.source_user_id) LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=src AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 IF u IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Command Centre fixtures unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true); PERFORM set_config('test.org',org::text,true); PERFORM set_config('test.foreign',foreign_org::text,true); PERFORM set_config('test.source',src::text,true); PERFORM set_config('test.case',c::text,true); PERFORM set_config('test.action',a::text,true); PERFORM set_config('test.foreign_action',fa::text,true); PERFORM set_config('test.prediction',p::text,true); PERFORM set_config('test.hidden',hidden::text,true); PERFORM set_config('test.metric',metric,true);
 INSERT INTO tj.decision_cases(id,organization_id,module,title,summary,recommendation) VALUES(c,org,'command_center','Rollback fixture','Synthetic','Synthetic'),(fc,foreign_org,'command_center','Hidden fixture','Synthetic','Synthetic');
 INSERT INTO tj.decision_actions(id,organization_id,decision_case_id,action_text) VALUES(a,org,c,'Rollback action'),(fa,foreign_org,fc,'Hidden action');
 INSERT INTO tj.decision_predictions(id,organization_id,decision_case_id,prediction_type,predicted_value,model_name) VALUES(p,org,c,'migration_fixture',100,p::text),(hidden,org,c,'withheld_fixture',100,p::text);
 INSERT INTO tj_private.approved_prediction_ids(prediction_id,basis) VALUES(p,'rollback_fixture');
 INSERT INTO tj.iq_score_weights(organization_id,metric_key,metric_label,max_points,source_type) VALUES(org,metric,'Rollback metric',40,'metric_snapshot');
 INSERT INTO tj.metric_snapshots(organization_id,period_type,period_key,metric_key,actual_value,target_value,user_id) VALUES(org,'monthly','2099-01',metric,50,100,src);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; other uuid:=current_setting('test.foreign')::uuid; src uuid:=current_setting('test.source')::uuid; r jsonb; BEGIN
 r:=tj.decision_get_feed(org,100);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r) x WHERE x->>'id'=current_setting('test.case')) THEN RAISE EXCEPTION 'Decision feed fixture missing'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(r) x,jsonb_array_elements(x->'predictions') p WHERE p->>'type'='withheld_fixture') THEN RAISE EXCEPTION 'Unapproved prediction in feed'; END IF;
 r:=tj.decision_get_prediction_dashboard(org);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'predictions') x WHERE x->>'id'=current_setting('test.prediction')) OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'predictions') x WHERE x->>'id'=current_setting('test.hidden')) THEN RAISE EXCEPTION 'Prediction allowlist failed'; END IF;
 IF jsonb_typeof(tj.executive_get_command_centre(org)->'top_risks')<>'array' THEN RAISE EXCEPTION 'Executive response failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.compute_iq_score(org,'2099-01',p_user_id=>src) WHERE metric_key=current_setting('test.metric') AND actual_value=50 AND earned_points=20 AND pct_of_target=50) THEN RAISE EXCEPTION 'IQ score calculation failed'; END IF;
 r:=tj.decision_update_action(current_setting('test.action')::uuid,'accepted',p_owner_id=>src); IF r->>'status'<>'accepted' THEN RAISE EXCEPTION 'Action acceptance failed'; END IF;
 r:=tj.decision_record_prediction_outcome(current_setting('test.prediction')::uuid,120); IF (r->>'error_pct')::numeric<>20 OR r->>'direction'<>'over' THEN RAISE EXCEPTION 'Prediction measurement failed'; END IF;
 PERFORM tj.decision_record_prediction_outcome(current_setting('test.prediction')::uuid,110);
 BEGIN PERFORM tj.decision_record_prediction_outcome(current_setting('test.hidden')::uuid,110); RAISE EXCEPTION 'Unapproved prediction measured'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.decision_update_action(current_setting('test.foreign_action')::uuid,'accepted'); RAISE EXCEPTION 'Foreign action updated'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.decision_update_action(current_setting('test.action')::uuid,'accepted',p_owner_id=>gen_random_uuid()); RAISE EXCEPTION 'Foreign owner accepted'; EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'owner_not_in_organization' THEN RAISE; END IF; END;
 BEGIN PERFORM tj.decision_get_feed(other); RAISE EXCEPTION 'Foreign decision feed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.decision_get_prediction_dashboard(other); RAISE EXCEPTION 'Foreign prediction dashboard'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.executive_get_command_centre(other); RAISE EXCEPTION 'Foreign executive dashboard'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM tj.compute_iq_score(other); RAISE EXCEPTION 'Foreign IQ score'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.decision_predictions WHERE id=current_setting('test.prediction')::uuid AND status='measured' AND actual_value=110 AND absolute_error=10 AND percent_error=10 AND measured_at IS NOT NULL) THEN RAISE EXCEPTION 'Measurement fields not persisted'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.decision_model_performance WHERE organization_id=current_setting('test.org')::uuid AND module=current_setting('test.prediction') AND sample_count=1 AND mean_absolute_error=10 AND mean_absolute_percentage_error=10) THEN RAISE EXCEPTION 'Repeated measurement double counted'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.decision_cases WHERE id=current_setting('test.case')::uuid AND status='accepted' AND updated_by=current_setting('test.source')::uuid) THEN RAISE EXCEPTION 'Action case audit missing'; END IF;
END $$;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM tj.decision_get_feed(current_setting('test.org')::uuid); RAISE EXCEPTION 'Unmapped decision feed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['decision_get_feed(uuid,integer)','decision_get_prediction_dashboard(uuid)','executive_get_command_centre(uuid)','compute_iq_score(uuid,text,uuid,uuid)','decision_update_action(uuid,text,uuid,timestamptz,boolean,numeric,text,text)','decision_record_prediction_outcome(uuid,numeric,numeric)'] LOOP
 IF has_function_privilege('anon','tj.'||name,'EXECUTE') OR has_function_privilege('anon','tj_private.'||name,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous Command Centre privilege'; END IF;
 END LOOP;
END $$;
ROLLBACK;
