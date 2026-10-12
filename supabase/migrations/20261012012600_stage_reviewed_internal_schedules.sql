-- Target: US Supabase. Stage reviewed internal jobs inactive until Canadian writers are paused.
DO $stage$ DECLARE v_id bigint; BEGIN
v_id:=cron.schedule('tj-iq-connector-retry-queue','*/5 * * * *','DO $j$ BEGIN IF tj.has_active_connector_connections() THEN PERFORM tj.platform_queue_due_connector_retries(50); END IF; END $j$;'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-iq-connector-alert-scan','*/5 * * * *','DO $j$ BEGIN IF tj.has_active_connector_connections() THEN PERFORM tj.platform_connector_alert_scan(); END IF; END $j$;'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-iq-connector-stale-job-recovery','*/5 * * * *','DO $j$ BEGIN IF tj.has_active_connector_connections() THEN PERFORM tj.platform_recover_stale_connector_jobs(30); END IF; END $j$;'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-phase4-evaluate-due-interventions','17 * * * *','SELECT * FROM tj.phase4_evaluate_all_due(100);'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-phase7-autonomous-orchestration','*/15 * * * *','SELECT tj.phase7_run_scheduled_cycles();'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-phase8-existing-forecast-refresh','17 5 * * *','SELECT tj.phase8_run_scheduled_forecasts();'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-move-won-to-vip-365d','0 6 * * *','WITH moved AS (UPDATE tj.crm_deals SET stage=''VIP'',stage_entered_at=now() WHERE stage=''Closed Won'' AND closed_at<now()-interval ''365 days'' AND deleted_at IS NULL AND NOT is_archived RETURNING id,organization_id,owner_user_id) INSERT INTO tj.crm_stage_history(deal_id,organization_id,from_stage,to_stage,changed_by,changed_at) SELECT id,organization_id,''Closed Won'',''VIP'',owner_user_id,now() FROM moved;'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-floor-nightly-snapshots','0 4 * * *','SELECT tj.run_floor_snapshots();'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-floor-hole-task-sync','0 5 * * *','SELECT tj.sync_floor_hole_tasks();'); PERFORM cron.alter_job(v_id,active:=false);
v_id:=cron.schedule('tj-mdf-daily-expiry-check','0 12 * * *','SET search_path=tj,extensions,pg_temp; SELECT tj.mdf_check_expiring_funds(); SELECT tj.mdf_check_expiring_contracts();'); PERFORM cron.alter_job(v_id,active:=false);
END $stage$;
