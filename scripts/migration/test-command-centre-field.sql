BEGIN; SET LOCAL statement_timeout='45s'; SET LOCAL TIME ZONE 'America/Toronto';
DO $$
DECLARE org uuid:=gen_random_uuid(); foreign_org uuid:=gen_random_uuid(); client uuid:=gen_random_uuid(); foreign_client uuid:=gen_random_uuid(); retailer uuid:=gen_random_uuid(); store uuid:=gen_random_uuid(); visit uuid:=gen_random_uuid(); old_visit uuid:=gen_random_uuid(); finding uuid:=gen_random_uuid(); action uuid:=gen_random_uuid(); native uuid; actor uuid; snap uuid; m jsonb; r jsonb;
BEGIN
 SELECT im.target_user_id,im.source_user_id INTO native,actor FROM tj.source_user_identity_map im WHERE im.activation_status='activated' AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'Native fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 INSERT INTO tj.organizations(id,name,slug) VALUES(org,'Rollback Field',org::text),(foreign_org,'Rollback Foreign Field',foreign_org::text);
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'owner','active');
 INSERT INTO tj.field_clients(id,organization_id,client_name) VALUES(client,org,'Rollback Client'),(foreign_client,foreign_org,'Foreign Client');
 INSERT INTO tj.field_retailers(id,name) VALUES(retailer,'Rollback Retailer');
 INSERT INTO tj.field_stores(id,retailer_id,store_name) VALUES(store,retailer,'Rollback Store');
 INSERT INTO tj.field_visits(id,client_id,store_id,rep_user_id,status,visit_date,updated_at) VALUES(visit,client,store,actor,'completed',current_date,now()),(old_visit,client,store,actor,'completed',current_date-30,now()-interval '30 days');
 INSERT INTO tj.field_store_scores(visit_id,client_id,store_id,overall_score,score_date,created_at) VALUES(old_visit,client,store,90,current_date-30,now()-interval '30 days'),(visit,client,store,5,current_date,now());
 INSERT INTO tj.field_findings(id,visit_id,client_id,store_id,severity,status,updated_at) VALUES(finding,visit,client,store,'critical','new',now());
 INSERT INTO tj.field_actions(id,finding_id,visit_id,client_id,store_id,title,priority,status,due_date,updated_at) VALUES(action,finding,visit,client,store,'Rollback recorded action','critical','assigned',current_date-1,now());
 -- Deliberately inconsistent foreign client links must not enter this organization's rollup.
 INSERT INTO tj.field_findings(visit_id,client_id,store_id,severity,status) VALUES(visit,foreign_client,store,'critical','new');
 m:=tj_private.command_centre_field_evidence(org);
 IF m->>'visits_total'<>'2' OR m->>'visits_this_month'<>'1' OR m->>'critical_open_findings'<>'1' OR m->>'open_actions'<>'1' OR m->>'overdue_actions'<>'1' OR (m->>'average_store_score')::numeric<>5 THEN RAISE EXCEPTION 'Scope, latest store score or scale wrong: %',m;END IF;
 IF (m->>'resolution_pct')::numeric<>0 OR jsonb_array_length(m->'priority_actions')<>1 THEN RAISE EXCEPTION 'Action evidence';END IF;
 IF (tj_private.command_centre_field_evidence(foreign_org)->>'critical_open_findings')::int<>0 THEN RAISE EXCEPTION 'Mismatched foreign finding included';END IF;
 EXECUTE 'SET LOCAL ROLE authenticated';
 snap:=public.tj_runtime_executive_refresh_command_centre(org);r:=public.tj_runtime_executive_get_command_centre(org);
 IF r#>>'{snapshot,metrics,field,visits_total}'<>'2' OR jsonb_array_length(r->'top_risks')<>1 OR r#>>'{priority_actions,0,id}'<>action::text OR r#>>'{snapshot,metrics,sources,field,latest_source_at}' IS NULL THEN RAISE EXCEPTION 'Application publication missing: %',r;END IF;
 BEGIN PERFORM public.tj_runtime_executive_get_command_centre(foreign_org);RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 EXECUTE 'RESET ROLE';
 UPDATE tj.field_actions SET status='resolved',resolved_at=now() WHERE id=action;
 UPDATE tj.field_findings SET status='resolved' WHERE id=finding;
 IF NOT EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=org AND requested_at>processed_at) THEN RAISE EXCEPTION 'Field correction did not enqueue';END IF;
 PERFORM tj_private.command_centre_rebuild(org,actor);
 EXECUTE 'SET LOCAL ROLE authenticated';r:=public.tj_runtime_executive_get_command_centre(org);EXECUTE 'RESET ROLE';
 IF jsonb_array_length(r->'top_risks')<>0 OR jsonb_array_length(r->'priority_actions')<>0 OR (r#>>'{snapshot,metrics,field,resolution_pct}')::numeric<>100 THEN RAISE EXCEPTION 'Resolved source evidence still active';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.executive_intelligence_snapshots WHERE id=snap AND metrics#>>'{field,critical_open_findings}'='1') THEN RAISE EXCEPTION 'Historical source evidence lost';END IF;
 IF EXISTS(SELECT 1 FROM tj.executive_intelligence_snapshots WHERE organization_id=org AND overall_health_score IS NOT NULL) THEN RAISE EXCEPTION 'Composite health invented';END IF;
 -- A source client transfer requests both affected organizations, without duplicate queue writes.
 UPDATE tj.field_clients SET organization_id=foreign_org WHERE id=client;
 IF NOT EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=foreign_org) OR (tj_private.command_centre_field_evidence(org)->>'visits_total')::int<>0 THEN RAISE EXCEPTION 'Client transfer scope or queue wrong';END IF;
 IF has_function_privilege('authenticated','tj_private.command_centre_field_evidence(uuid)','EXECUTE') OR has_function_privilege('anon','tj_private.command_centre_field_enqueue()','EXECUTE') THEN RAISE EXCEPTION 'Private field helper exposed';END IF;
END $$;
SELECT jsonb_build_object('passed',true,'fixtures_persisted',0,'checks',jsonb_build_array('organization and child relationship scopes','latest store score without rescaling','recorded visits and overdue actions','native executive wrappers','source dates','resolution refresh removes current alerts but retains history','client transfer queues both organizations','private helper permissions','composite health remains unknown')) verification;
ROLLBACK;
