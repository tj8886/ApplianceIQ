BEGIN; SET LOCAL statement_timeout='30s';
DO $$DECLARE u uuid;s uuid;o uuid;c uuid;d uuid;t uuid;x uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,s,o FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations org ON org.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN('owner','admin') AND org.status='active' AND org.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);
 INSERT INTO tj.contacts(organization_id,first_name) VALUES(o,'Rollback CRM fixture') RETURNING id INTO c;
 INSERT INTO tj.crm_deals(organization_id,title,stage,contact_id,owner_user_id,purchase_date) VALUES(o,'Rollback anniversary fixture','Closed Won',c,s,(CURRENT_DATE+7-interval '1 year')::date) RETURNING id INTO d;
 INSERT INTO tj.crm_tasks(organization_id,title,assignee_user_id,due_at) VALUES(o,'Rollback overdue fixture',s,now()-interval '1 day') RETURNING id INTO t;
 INSERT INTO tj.crm_tasks(organization_id,title,assignee_user_id,due_at,deleted_at) VALUES(o,'Rollback deleted fixture',s,now()-interval '1 day',now()) RETURNING id INTO x;
 PERFORM set_config('test.native',u::text,true);PERFORM set_config('test.org',o::text,true);PERFORM set_config('test.deal',d::text,true);PERFORM set_config('test.task',t::text,true);PERFORM set_config('test.deleted',x::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 r:=public.tj_run_crm_outreach_tasks(current_setting('test.org')::uuid);IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Housekeeping failed';END IF;
 r:=public.tj_run_crm_outreach_tasks(current_setting('test.org')::uuid);IF (r->>'anniversaries_created')::int<>0 OR (r->>'overdue_notifications')::int<>0 THEN RAISE EXCEPTION 'Duplicate housekeeping';END IF;
 BEGIN PERFORM public.tj_run_crm_outreach_tasks(gen_random_uuid());RAISE EXCEPTION 'Foreign org accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_run_crm_outreach_tasks(current_setting('test.org')::uuid);RAISE EXCEPTION 'Unmapped identity accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF (SELECT count(*) FROM tj.crm_tasks WHERE deal_id=current_setting('test.deal')::uuid AND metadata ? 'anniversary_year')<>1 THEN RAISE EXCEPTION 'Anniversary task not created once';END IF;
 IF (SELECT count(*) FROM tj.crm_notifications WHERE entity_id=current_setting('test.task')::uuid)<>1 THEN RAISE EXCEPTION 'Overdue notification not created once';END IF;
 IF EXISTS(SELECT 1 FROM tj.crm_notifications WHERE entity_id=current_setting('test.deleted')::uuid) THEN RAISE EXCEPTION 'Deleted task notified';END IF;
 IF has_function_privilege('anon','public.tj_run_crm_outreach_tasks(uuid)','EXECUTE') OR has_function_privilege('service_role','public.tj_run_crm_outreach_tasks(uuid)','EXECUTE') THEN RAISE EXCEPTION 'Grant leak';END IF;
END $$;
ROLLBACK;
