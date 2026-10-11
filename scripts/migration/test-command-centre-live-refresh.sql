-- Isolated fixtures and all changes roll back, including source hooks/queue state.
BEGIN;
SET LOCAL statement_timeout='45s';
DO $$
DECLARE org uuid:=gen_random_uuid(); sid uuid:=gen_random_uuid(); native uuid; actor uuid; prof uuid;
 visit uuid:=gen_random_uuid(); waiting uuid:=gen_random_uuid(); old_visit uuid:=gen_random_uuid(); shift uuid:=gen_random_uuid(); pos uuid:=gen_random_uuid();
 snap uuid; r jsonb; m jsonb; period text:=to_char(now() AT TIME ZONE 'America/Toronto','YYYY-MM'); first_day timestamptz:=date_trunc('month',now() AT TIME ZONE 'America/Toronto') AT TIME ZONE 'America/Toronto';
BEGIN
 SELECT im.target_user_id,im.source_user_id,p.id INTO native,actor,prof FROM tj.source_user_identity_map im JOIN tj.profiles p ON p.user_id=im.source_user_id
 WHERE im.activation_status='activated' AND NOT EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=im.source_user_id) LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'Native actor unavailable'; END IF;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 INSERT INTO tj.organizations(id,name,slug) VALUES(org,'Rollback Command Centre',org::text);
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'owner','active');
 INSERT INTO tj.org_locations(id,organization_id,name,location_type,is_active) VALUES(sid,org,'Rollback Store','store',true);
 INSERT INTO tj.iq_shift_records(id,organization_id,store_id,user_id,created_by,updated_by) VALUES(shift,org,sid,prof,actor,actor);
 INSERT INTO tj.iq_customer_waiting_queue(id,organization_id,store_id,arrival_time) VALUES(visit,org,sid,now()),(waiting,org,sid,now()),(old_visit,org,sid,first_day-interval '1 minute');
 INSERT INTO tj.iq_customer_interactions(organization_id,store_id,shift_id,salesperson_user_id,customer_waiting_id,outcome,ended_at) VALUES(org,sid,shift,prof,visit,'sale',now()),(org,sid,shift,prof,visit,'sale',now());
 INSERT INTO tj.academy_quiz_scores(user_id,vol,score,total) VALUES(actor,org::text,2,4);
 INSERT INTO tj.iq_pos_transactions(id,organization_id,store_id,pos_transaction_id,transaction_date,transaction_amount,currency_code,gross_margin_amount) VALUES(pos,org,sid,pos::text,now(),100,'CAD',20);
 snap:=tj_private.command_centre_rebuild(org,actor);
 SELECT metrics INTO m FROM tj.executive_intelligence_snapshots WHERE id=snap;
 IF m#>>'{retail_floor,walk_ins}'<>'2' OR (m#>>'{retail_floor,conversion_pct}')::numeric<>50 OR (m#>>'{retail_floor,served_score}')::numeric<>50 THEN RAISE EXCEPTION 'Month boundaries/distinct visits: %',m->'retail_floor';END IF;
 IF (m#>>'{training,average_knowledge_score}')::numeric<>50 THEN RAISE EXCEPTION 'Academy scores not received';END IF;
 IF EXISTS(SELECT 1 FROM tj.executive_intelligence_snapshots WHERE id=snap AND (overall_health_score IS NOT NULL OR health_status<>'unknown')) OR m#>>'{crm,pipeline_value_cad}' IS NOT NULL THEN RAISE EXCEPTION 'Invented health or money';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND location_id IS NULL AND period_key=period AND metric_key='revenue' AND actual_value=100) THEN RAISE EXCEPTION 'Explicit CAD revenue missing';END IF;
 UPDATE tj.metric_snapshots SET target_value=200 WHERE organization_id=org AND metric_key='revenue';
 PERFORM tj_private.command_centre_rebuild(org,actor);
 IF (SELECT count(*) FROM tj.metric_snapshots WHERE organization_id=org AND location_id IS NULL AND metric_key='revenue')<>1 OR NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND metric_key='revenue' AND target_value=200 AND variance_value=-100) THEN RAISE EXCEPTION 'Repeat refresh or target preservation';END IF;
 -- Preserve the recorded amount but hide stale CAD totals after a source currency correction.
 UPDATE tj.iq_pos_transactions SET currency_code='USD' WHERE id=pos;
 PERFORM tj_private.command_centre_rebuild(org,actor);
 IF NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND metric_key='revenue' AND metric_subtype='command_centre_withheld' AND actual_value=100 AND target_value=200) THEN RAISE EXCEPTION 'Unsupported evidence was removed or exposed';END IF;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND metric_key='revenue') THEN RAISE EXCEPTION 'Withheld evidence visible to application';END IF;
 snap:=public.tj_runtime_executive_refresh_command_centre(org);
 r:=public.tj_runtime_executive_get_command_centre(org);
 IF r#>>'{snapshot,id}'<>snap::text OR (r#>>'{snapshot,metrics,retail_floor,walk_ins}')::int<>2 THEN RAISE EXCEPTION 'Native application wrapper failed';END IF;
 EXECUTE 'RESET ROLE';
 UPDATE tj.iq_pos_transactions SET currency_code='CAD' WHERE id=pos;
 PERFORM tj_private.command_centre_rebuild(org,actor);
 IF (SELECT count(*) FROM tj.metric_snapshots WHERE organization_id=org AND location_id IS NULL AND metric_key='revenue')<>1 OR NOT EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND metric_key='revenue' AND metric_subtype='command_centre_live' AND target_value=200) THEN RAISE EXCEPTION 'Evidence restoration duplicated/lost targets';END IF;
 -- Other producers' monthly rows and their existing targets remain unchanged.
 UPDATE tj.metric_snapshots SET metric_subtype='manual_fixture',actual_value=123,target_value=456 WHERE organization_id=org AND metric_key='walk_ins';
 PERFORM tj_private.command_centre_rebuild(org,actor);
 IF EXISTS(SELECT 1 FROM tj.metric_snapshots WHERE organization_id=org AND metric_key='walk_ins' AND (actual_value<>123 OR target_value<>456)) THEN RAISE EXCEPTION 'Other producer overwritten';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=org AND requested_at>processed_at) THEN RAISE EXCEPTION 'Source update did not enqueue';END IF;
 -- Provoke one bounded worker failure with an invalid composite coverage status, then restore code in this transaction.
 UPDATE tj_private.command_centre_refresh_queue SET processed_at=clock_timestamp(),next_attempt_at=now()+interval '1 hour' WHERE organization_id<>org;
 EXECUTE format('ALTER TABLE tj.executive_intelligence_snapshots ADD CONSTRAINT rollback_worker_fault CHECK(organization_id<>%L::uuid) NOT VALID',org);
 r:=tj_private.command_centre_refresh_worker(1);
 IF r->>'failed'<>'1' OR NOT EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=org AND attempts=1 AND last_error='23514') THEN RAISE EXCEPTION 'Failed job not retained: %',r;END IF;
 ALTER TABLE tj.executive_intelligence_snapshots DROP CONSTRAINT rollback_worker_fault;
 UPDATE tj_private.command_centre_refresh_queue SET next_attempt_at=now() WHERE organization_id=org;
 r:=tj_private.command_centre_refresh_worker(1);
 IF r->>'processed'<>'1' OR EXISTS(SELECT 1 FROM tj_private.command_centre_refresh_queue WHERE organization_id=org AND (last_error IS NOT NULL OR attempts<>0 OR requested_at>processed_at)) THEN RAISE EXCEPTION 'Bounded retry incomplete: %',r;END IF;
 IF has_function_privilege('authenticated','tj_private.command_centre_refresh_worker(integer)','EXECUTE') OR has_function_privilege('anon','tj_private.command_centre_rebuild(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'Private helper callable';END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='aiq-command-centre-evidence-refresh' AND active AND schedule='*/5 * * * *') THEN RAISE EXCEPTION 'Native cron inactive';END IF;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.tj_runtime_executive_refresh_command_centre(org);RAISE EXCEPTION 'Unmapped refresh accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 EXECUTE 'RESET ROLE';
END $$;
SELECT jsonb_build_object('passed',true,'fixtures_persisted',0,'checks',jsonb_build_array('current month','distinct visits','academy score','no invented health or currency','target preservation','producer preservation','currency correction/restore','authenticated wrappers and denial','bounded failed job/retry','native cron')) verification;
ROLLBACK;
