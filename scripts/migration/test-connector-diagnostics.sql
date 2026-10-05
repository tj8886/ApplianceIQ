BEGIN; SET LOCAL statement_timeout='45s';
DO $$ DECLARE u uuid;src uuid;org uuid;co uuid;c uuid;q uuid;a uuid;BEGIN
 SELECT im.target_user_id,im.source_user_id,m.organization_id INTO u,src,org FROM tj.source_user_identity_map im JOIN tj.organization_members m ON m.user_id=im.source_user_id JOIN tj.organizations o ON o.id=m.organization_id WHERE im.activation_status='activated' AND m.status='active' AND m.role IN ('owner','admin') AND o.status='active' AND o.deleted_at IS NULL LIMIT 1;
 IF u IS NULL THEN RAISE EXCEPTION 'Fixture unavailable';END IF;
 INSERT INTO tj.platform_connectors(key,name,vendor_name) VALUES('rollback-'||gen_random_uuid(),'Rollback diagnostic connector','Synthetic') RETURNING id INTO co;
 INSERT INTO tj.platform_connector_connections(organization_id,connector_id,display_name,created_by) VALUES(org,co,'Rollback diagnostic connection',src) RETURNING id INTO c;
 INSERT INTO tj.platform_connector_quarantine(connection_id,external_entity_type,external_id,stage,error_code,error_message,payload,retryable) VALUES(c,'employee','rollback','validation','synthetic','PRIVATE ERROR',jsonb_build_object('private','PRIVATE PAYLOAD'),true) RETURNING id INTO q;
 INSERT INTO tj.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details) VALUES(c,'rollback','warning','Rollback alert','PRIVATE MESSAGE','rollback-'||gen_random_uuid(),jsonb_build_object('private','PRIVATE DETAILS')) RETURNING id INTO a;
 PERFORM set_config('request.jwt.claim.sub',u::text,true);PERFORM set_config('test.source',src::text,true);PERFORM set_config('test.org',org::text,true);PERFORM set_config('test.connection',c::text,true);PERFORM set_config('test.quarantine',q::text,true);PERFORM set_config('test.alert',a::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$ DECLARE b jsonb:=jsonb_build_object('connection_id',current_setting('test.connection'));r jsonb;BEGIN
 r:=public.tj_connector_diagnostics(b);IF r::text LIKE '%PRIVATE%' THEN RAISE EXCEPTION 'Private raw payload exposed';END IF;
 r:=public.tj_connector_diagnostics(jsonb_build_object('action','org_summary','organization_id',current_setting('test.org')));IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Org summary failed';END IF;
 r:=public.tj_connector_diagnostics(jsonb_build_object('action','org_reliability','organization_id',current_setting('test.org'),'months',12));IF NOT (r->>'ok')::boolean THEN RAISE EXCEPTION 'Reliability failed';END IF;
 r:=public.tj_connector_diagnostics(b||jsonb_build_object('action','retry','quarantine_id',current_setting('test.quarantine')));IF r->>'status'<>'retrying' THEN RAISE EXCEPTION 'Retry failed';END IF;
 r:=public.tj_connector_diagnostics(b||jsonb_build_object('action','resolve','quarantine_id',current_setting('test.quarantine'),'note','Synthetic resolution'));IF r->>'status'<>'resolved' THEN RAISE EXCEPTION 'Resolution failed';END IF;
 BEGIN PERFORM public.tj_connector_diagnostics(b||jsonb_build_object('action','retry','quarantine_id',current_setting('test.quarantine')));RAISE EXCEPTION 'Resolved record retried';EXCEPTION WHEN serialization_failure THEN NULL;END;
 r:=public.tj_connector_diagnostics(b||jsonb_build_object('action','acknowledge_alert','alert_id',current_setting('test.alert')));IF r->>'status'<>'acknowledged' THEN RAISE EXCEPTION 'Acknowledgment failed';END IF;
 BEGIN PERFORM public.tj_connector_diagnostics(b||jsonb_build_object('action','acknowledge_alert','alert_id',current_setting('test.alert')));RAISE EXCEPTION 'Stale acknowledgment accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 r:=public.tj_connector_diagnostics(b||jsonb_build_object('action','reopen_alert','alert_id',current_setting('test.alert')));IF r->>'status'<>'open' THEN RAISE EXCEPTION 'Reopen failed';END IF;
 BEGIN PERFORM public.tj_connector_diagnostics(b||jsonb_build_object('action','resolve','quarantine_id',gen_random_uuid()));RAISE EXCEPTION 'Foreign quarantine accepted';EXCEPTION WHEN no_data_found THEN NULL;END;
 BEGIN PERFORM public.tj_connector_diagnostics(jsonb_build_object('action','org_summary','organization_id',gen_random_uuid()));RAISE EXCEPTION 'Foreign organization accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 BEGIN PERFORM public.tj_connector_diagnostics(b);RAISE EXCEPTION 'Unmapped actor accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
RESET ROLE;
DO $$BEGIN
 IF EXISTS(SELECT 1 FROM tj.platform_connector_retry_queue WHERE quarantine_id=current_setting('test.quarantine')::uuid) THEN RAISE EXCEPTION 'Resolved retry retained';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connector_quarantine WHERE id=current_setting('test.quarantine')::uuid AND resolution->>'user_id'=current_setting('test.source')) THEN RAISE EXCEPTION 'Resolution actor incorrect';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.platform_connector_health_snapshots WHERE connection_id=current_setting('test.connection')::uuid) THEN RAISE EXCEPTION 'Health recomputation failed';END IF;
 IF has_function_privilege('anon','public.tj_connector_diagnostics(jsonb)','EXECUTE') OR has_function_privilege('service_role','public.tj_connector_diagnostics(jsonb)','EXECUTE') THEN RAISE EXCEPTION 'Unauthenticated grants';END IF;
END $$;
UPDATE tj.organization_members SET role='manager' WHERE organization_id=current_setting('test.org')::uuid AND user_id=current_setting('test.source')::uuid;
SELECT set_config('request.jwt.claim.sub',(SELECT target_user_id::text FROM tj.source_user_identity_map WHERE source_user_id=current_setting('test.source')::uuid AND activation_status='activated' LIMIT 1),true) IS NOT NULL AS identity_set;
SET LOCAL ROLE authenticated;
DO $$BEGIN
 PERFORM public.tj_connector_diagnostics(jsonb_build_object('action','org_summary','organization_id',current_setting('test.org')));
 BEGIN PERFORM public.tj_connector_diagnostics(jsonb_build_object('action','recalculate_health','connection_id',current_setting('test.connection')));RAISE EXCEPTION 'Manager mutation accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
ROLLBACK;
