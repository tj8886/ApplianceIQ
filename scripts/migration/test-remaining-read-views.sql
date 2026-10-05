BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid; src uuid; org uuid; product uuid:=gen_random_uuid(); version uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.version',version::text,true);
 INSERT INTO tj.aiq_products(id,organization_id,manufacturer_name,brand_name,model,status) VALUES(product,org,'Rollback fixture','Rollback fixture',product::text,'draft');
 INSERT INTO tj.aiq_product_versions(id,organization_id,product_id,version_number,snapshot) VALUES(version,org,product,1,'{"model":"Rollback fixture","dealer_cost":123}'::jsonb);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE t text; visible boolean; snap jsonb; BEGIN
 SELECT snapshot INTO snap FROM tj.aiq_product_versions_app WHERE id=current_setting('test.version')::uuid;
 IF snap IS NULL OR snap?'dealer_cost' OR snap->>'model'<>'Rollback fixture' THEN RAISE EXCEPTION 'Version projection failed'; END IF;
 BEGIN PERFORM snapshot FROM tj.aiq_product_versions LIMIT 1; RAISE EXCEPTION 'Raw snapshot readable'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 IF EXISTS(SELECT 1 FROM tj.iq_staffing_predictions WHERE NOT(id=ANY((SELECT tj_private.approved_staffing_ids())::uuid[]))) THEN RAISE EXCEPTION 'US-only staffing visible'; END IF;
 FOREACH t IN ARRAY ARRAY['academy_content_suggestions','aiq_product_versions_app','crm_postmortems','iq_staffing_predictions','crm_conversation_records','performance_metric_diagnostics','v_commercial_project_timelines','v_crm_accountability','v_floor_analytics'] LOOP EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO visible; END LOOP;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 FOREACH t IN ARRAY ARRAY['academy_content_suggestions','aiq_product_versions_app','crm_postmortems','iq_staffing_predictions','crm_conversation_records','performance_metric_diagnostics','v_commercial_project_timelines','v_crm_accountability','v_floor_analytics'] LOOP EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO visible; IF visible THEN RAISE EXCEPTION 'Unmapped read: %',t; END IF; END LOOP;
END $$;
RESET ROLE;
DO $$ DECLARE t text; BEGIN
 IF (SELECT count(*) FROM tj_private.approved_staffing_prediction_ids)<>1028 OR (SELECT count(*) FROM tj.iq_staffing_predictions p WHERE NOT EXISTS(SELECT 1 FROM tj_private.approved_staffing_prediction_ids a WHERE a.prediction_id=p.id))<>74 THEN RAISE EXCEPTION 'Staffing provenance counts changed'; END IF;
 FOREACH t IN ARRAY ARRAY['academy_content_suggestions','aiq_product_versions_app','crm_postmortems','iq_staffing_predictions','crm_conversation_records','performance_metric_diagnostics','v_commercial_project_timelines','v_crm_accountability','v_floor_analytics'] LOOP IF has_table_privilege('anon',format('tj.%I',t),'SELECT') OR has_table_privilege('authenticated',format('tj.%I',t),'INSERT,UPDATE,DELETE') THEN RAISE EXCEPTION 'Unexpected grants: %',t; END IF; END LOOP;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='tj' AND c.relname IN('crm_conversation_records','performance_metric_diagnostics','v_commercial_project_timelines','v_crm_accountability','v_floor_analytics','aiq_product_versions_app') AND NOT coalesce(c.reloptions @> ARRAY['security_invoker=true'],false)) THEN RAISE EXCEPTION 'Definer view activated'; END IF;
 IF has_table_privilege('authenticated','tj.ai_response_cache','SELECT') OR has_table_privilege('authenticated','tj.mfr_invites','SELECT') THEN RAISE EXCEPTION 'Private cache/invite access exposed'; END IF;
END $$;
ROLLBACK;
