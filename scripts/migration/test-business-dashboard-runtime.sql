-- Positive/negative live database checks. All synthetic rows are rolled back.
BEGIN;
SET LOCAL statement_timeout='25s';
DO $$ DECLARE target_u uuid; source_u uuid; org uuid; foreign_org uuid;
 task uuid:=gen_random_uuid(); foreign_task uuid:=gen_random_uuid(); brief uuid:=gen_random_uuid(); event uuid:=gen_random_uuid(); case_id uuid:=gen_random_uuid(); BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO target_u,source_u,org
 FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id
 JOIN tj.organizations o ON o.id=m.organization_id AND o.deleted_at IS NULL
 WHERE im.activation_status='activated' AND m.status='active' AND m.visibility_scope='all'
 AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id)
 ORDER BY im.source_user_id LIMIT 1;
 SELECT o.id INTO foreign_org FROM tj.organizations o WHERE o.deleted_at IS NULL AND o.id<>org
 AND NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=source_u AND m.organization_id=o.id AND m.status='active') LIMIT 1;
 IF target_u IS NULL OR foreign_org IS NULL THEN RAISE EXCEPTION 'Positive/negative member fixtures unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',target_u::text,true);
 PERFORM set_config('test.org',org::text,true);
 PERFORM set_config('test.foreign_org',foreign_org::text,true);
 PERFORM set_config('test.task',task::text,true);
 PERFORM set_config('test.foreign_task',foreign_task::text,true);
 PERFORM set_config('test.brief',brief::text,true);
 PERFORM set_config('test.event',event::text,true);
 PERFORM set_config('test.case',case_id::text,true);
 PERFORM set_config('test.source_user',source_u::text,true);
 PERFORM set_config('test.invalid_assignee',(SELECT s.id::text FROM tj.source_auth_users s
 WHERE NOT EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.user_id=s.id AND m.organization_id=org AND m.status='active') LIMIT 1),true);
 INSERT INTO tj.ai_manager_assignments(id,organization_id,title,assigned_to)
 VALUES(task,org,'Migration rollback fixture',source_u),(foreign_task,foreign_org,'Hidden rollback fixture',NULL);
 INSERT INTO tj.decision_cases(id,organization_id,module,title,summary,recommendation)
 VALUES(case_id,org,'command_center','Migration rollback fixture','Synthetic test','Synthetic test');
 IF (SELECT priority_score FROM tj.decision_cases WHERE id=case_id)<>15
 THEN RAISE EXCEPTION 'Insert priority trigger failed'; END IF;
 UPDATE tj.ai_manager_assignments SET decision_case_id=case_id WHERE id=task;
 INSERT INTO tj.ai_manager_briefs(id,organization_id,headline,executive_summary)
 VALUES(brief,org,'Migration rollback fixture','Synthetic test; no delivery');
 INSERT INTO tj.intelligence_events(id,organization_id,event_type,source_system)
 VALUES(event,org,'test.migration','migration-rollback-test');
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE org uuid:=current_setting('test.org')::uuid; forbidden uuid:=current_setting('test.foreign_org')::uuid;
 result jsonb; r record; BEGIN
 IF tj.get_my_org_role(org) IS NULL OR tj.get_my_org_role(forbidden) IS NOT NULL
 THEN RAISE EXCEPTION 'Role lookup authorization failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.get_org_member_profiles(org)) OR EXISTS(SELECT 1 FROM tj.get_org_member_profiles(forbidden))
 THEN RAISE EXCEPTION 'Member roster authorization failed'; END IF;
 IF jsonb_typeof(tj.ai_manager_get_members(org))<>'array' THEN RAISE EXCEPTION 'Manager member response failed'; END IF;
 result:=tj.ai_manager_get_dashboard(org);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'assignments') a WHERE a->>'id'=current_setting('test.task'))
 THEN RAISE EXCEPTION 'Dashboard assignment missing'; END IF;
 result:=tj.ai_manager_get_my_work(org);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'assignments') a WHERE a->>'id'=current_setting('test.task'))
 THEN RAISE EXCEPTION 'Personal work assignment missing'; END IF;
 result:=tj.ai_manager_get_task_detail(current_setting('test.task')::uuid);
 IF result->'assignment'->>'id' IS DISTINCT FROM current_setting('test.task') THEN RAISE EXCEPTION 'Task detail missing'; END IF;
 IF tj.ai_manager_register_attachment(current_setting('test.task')::uuid,'foreign/path/file.pdf','file.pdf','application/pdf',10)->>'error'<>'invalid_storage_path'
 THEN RAISE EXCEPTION 'Foreign attachment path accepted'; END IF;
 IF tj.ai_manager_register_attachment(current_setting('test.task')::uuid,
 current_setting('test.org')||'/'||current_setting('test.task')||'/missing.pdf','missing.pdf','application/pdf',10)->>'error'<>'stored_object_missing_or_metadata_mismatch'
 THEN RAISE EXCEPTION 'Missing attachment accepted'; END IF;
 IF tj.ai_manager_get_task_detail(current_setting('test.foreign_task')::uuid)->>'error'<>'access_denied'
 THEN RAISE EXCEPTION 'Foreign task detail exposed'; END IF;
 result:=tj.ai_manager_get_executive_briefs(org,p_focus_id=>current_setting('test.brief')::uuid);
 IF jsonb_array_length(result->'briefs')<>1 THEN RAISE EXCEPTION 'Executive brief missing'; END IF;
 result:=tj.ai_manager_assign_task(current_setting('test.task')::uuid,current_setting('test.source_user')::uuid);
 IF result->>'ok'<>'true' OR NOT EXISTS(SELECT 1 FROM tj.ai_manager_task_history h
 WHERE h.assignment_id=current_setting('test.task')::uuid AND h.actor_id=current_setting('test.source_user')::uuid)
 THEN RAISE EXCEPTION 'Assignment/audit write failed'; END IF;
 IF tj.ai_manager_assign_task(current_setting('test.foreign_task')::uuid)->>'error'<>'access_denied'
 THEN RAISE EXCEPTION 'Foreign assignment updated'; END IF;
 IF tj.ai_manager_assign_task(current_setting('test.task')::uuid,current_setting('test.invalid_assignee')::uuid)->>'error'<>'assignee_not_in_organization'
 THEN RAISE EXCEPTION 'Foreign assignee accepted'; END IF;
 BEGIN PERFORM tj.ai_manager_update_assignment(current_setting('test.task')::uuid,'open',p_assigned_to=>current_setting('test.invalid_assignee')::uuid);
 RAISE EXCEPTION 'Foreign update assignee accepted'; EXCEPTION WHEN raise_exception THEN
 IF SQLERRM<>'assignee_not_in_organization' THEN RAISE; END IF; END;
 result:=tj.ai_manager_update_assignment(current_setting('test.task')::uuid,'blocked','Migration rollback test');
 IF result->>'status'<>'blocked' OR result->>'blocked_reason'<>'Migration rollback test'
 THEN RAISE EXCEPTION 'Blocked status update failed'; END IF;
 result:=tj.ai_manager_update_assignment(current_setting('test.task')::uuid,'completed');
 IF result->>'status'<>'completed' OR result->>'completed_at' IS NULL OR result->>'blocked_reason' IS NOT NULL
 THEN RAISE EXCEPTION 'Completion status update failed'; END IF;
 BEGIN PERFORM tj.ai_manager_update_assignment(current_setting('test.foreign_task')::uuid,'completed');
 RAISE EXCEPTION 'Foreign completion accepted'; EXCEPTION WHEN raise_exception THEN
 IF SQLERRM<>'not_authorized' THEN RAISE; END IF; END;
 BEGIN PERFORM tj.ai_manager_update_assignment(current_setting('test.task')::uuid,NULL);
 RAISE EXCEPTION 'Null status accepted'; EXCEPTION WHEN raise_exception THEN
 IF SQLERRM<>'invalid_status' THEN RAISE; END IF; END;
 result:=tj.ai_manager_mark_brief_delivered(current_setting('test.brief')::uuid);
 IF result->>'delivery_status'<>'delivered' OR result->>'delivered_at' IS NULL
 THEN RAISE EXCEPTION 'Brief delivery tracking failed'; END IF;
 IF tj.decision_calculate_priority(NULL,NULL,NULL,NULL,NULL,NULL)<>15
 OR tj.decision_calculate_priority(250000,100,100,1,1,0)<>100
 THEN RAISE EXCEPTION 'Priority formula regression'; END IF;
 IF tj.ai_manager_get_executive_briefs(forbidden)->>'error'<>'organization_access_denied'
 THEN RAISE EXCEPTION 'Foreign executive brief exposed'; END IF;
 IF tj.ai_manager_get_my_work(forbidden)->>'error'<>'access_denied'
 THEN RAISE EXCEPTION 'Foreign personal work exposed'; END IF;
 BEGIN PERFORM tj.ai_manager_get_dashboard(forbidden); RAISE EXCEPTION 'Foreign dashboard accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'not_authorized' THEN RAISE; END IF; END;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_intelligence_feed(org,p_event_types=>ARRAY['test.migration']) f WHERE f.id=current_setting('test.event')::uuid)
 THEN RAISE EXCEPTION 'Own intelligence feed missing'; END IF;
 result:=tj.platform_intelligence_summary(org);
 IF (result->>'events')::bigint<1 THEN RAISE EXCEPTION 'Own intelligence summary missing'; END IF;
 PERFORM * FROM tj.platform_intelligence_employee_rollup(org);
 PERFORM * FROM tj.platform_intelligence_store_rollup(org);
 IF tj.platform_intelligence_summary(forbidden)<>'{}'::jsonb
 OR EXISTS(SELECT 1 FROM tj.platform_intelligence_feed(forbidden))
 OR EXISTS(SELECT 1 FROM tj.platform_intelligence_employee_rollup(forbidden))
 OR EXISTS(SELECT 1 FROM tj.platform_intelligence_store_rollup(forbidden))
 THEN RAISE EXCEPTION 'Foreign intelligence data exposed'; END IF;
 FOR r IN SELECT n.nspname,p.oid,p.prosecdef,p.proconfig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname IN ('tj','tj_private') AND p.proname IN ('source_identity_for_session','get_org_member_profiles',
 'get_my_org_role','intelligence_employee_names','ai_manager_get_dashboard','ai_manager_get_members',
 'ai_manager_get_my_work','ai_manager_get_task_detail','ai_manager_get_executive_briefs',
 'platform_intelligence_feed','platform_intelligence_summary','platform_intelligence_store_rollup',
 'platform_intelligence_employee_rollup','ai_manager_assign_task','ai_manager_update_assignment',
 'ai_manager_mark_brief_delivered','allowed_store_pairs','unrestricted_store_organizations') LOOP
 IF has_function_privilege('anon',r.oid,'EXECUTE') THEN RAISE EXCEPTION 'Anonymous execute privilege'; END IF;
 IF r.nspname='tj' AND r.prosecdef THEN RAISE EXCEPTION 'Privileged public adapter'; END IF;
 IF NOT coalesce(r.proconfig @> ARRAY['search_path=""'],false) THEN RAISE EXCEPTION 'Unfixed search path'; END IF;
 END LOOP;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM tj.decision_cases WHERE id=current_setting('test.case')::uuid
 AND status='completed' AND resolved_at IS NOT NULL AND priority_score=15)
 THEN RAISE EXCEPTION 'Completion case/priority trigger failed'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000000',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE t text; found_rows boolean; BEGIN
 FOREACH t IN ARRAY ARRAY['ai_manager_briefs','ai_manager_assignments','ai_manager_escalations',
 'ai_manager_task_comments','ai_manager_task_attachments','ai_manager_task_history','intelligence_events'] LOOP
 EXECUTE format('SELECT EXISTS(SELECT 1 FROM tj.%I)',t) INTO found_rows;
 IF found_rows THEN RAISE EXCEPTION 'Unmapped business read exposed data'; END IF;
 IF has_table_privilege(current_user,'tj.'||t,'INSERT') OR has_table_privilege(current_user,'tj.'||t,'UPDATE')
 THEN RAISE EXCEPTION 'Unreviewed business write privileges'; END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM tj.get_org_member_profiles(current_setting('test.org')::uuid))
 THEN RAISE EXCEPTION 'Unmapped roster exposed data'; END IF;
END $$;
RESET ROLE;
ROLLBACK;
SELECT 'Business dashboard checks passed; all test writes rolled back' AS result;
