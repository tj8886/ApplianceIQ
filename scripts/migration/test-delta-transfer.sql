BEGIN;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $$ BEGIN
  BEGIN PERFORM public.aiq_apply_delta_batch('phase7_action_audit','[]'); RAISE EXCEPTION 'missing authorization guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'service_role_required' THEN RAISE; END IF; END;
END $$;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$
DECLARE row_data jsonb; response jsonb; original_count bigint;
BEGIN
  IF has_function_privilege('anon','public.aiq_apply_delta_batch(text,jsonb)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_apply_delta_batch(text,jsonb)','EXECUTE') THEN RAISE EXCEPTION 'public_rpc_exposed'; END IF;
  BEGIN PERFORM public.aiq_apply_delta_batch('organizations','[]'); RAISE EXCEPTION 'missing table guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'table_not_allowed' THEN RAISE; END IF; END;
  SELECT to_jsonb(t) INTO row_data FROM tj.phase7_action_audit t ORDER BY id DESC LIMIT 1;
  BEGIN PERFORM public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data)); RAISE EXCEPTION 'missing window guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'outside_transfer_window' THEN RAISE; END IF; END;
  row_data:=row_data||jsonb_build_object('id',275452,'event_type','migration_rollback_fixture');
  SELECT count(*) INTO original_count FROM tj.phase7_action_audit;
  response:=public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data));
  IF response->>'inserted'<>'1' THEN RAISE EXCEPTION 'insert_missing'; END IF;
  response:=public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data));
  IF response->>'inserted'<>'0' THEN RAISE EXCEPTION 'retry_not_idempotent'; END IF;
  IF (SELECT count(*) FROM tj.phase7_action_audit)<>original_count+1 THEN RAISE EXCEPTION 'unexpected_rows'; END IF;
  BEGIN PERFORM public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data||jsonb_build_object('event_type','conflicting_fixture'))); RAISE EXCEPTION 'missing conflict guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'destination_conflict' THEN RAISE; END IF; END;
  BEGIN PERFORM public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data||jsonb_build_object('unknown_column',true))); RAISE EXCEPTION 'missing column guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'source_column_mismatch' THEN RAISE; END IF; END;
  BEGIN PERFORM public.aiq_apply_delta_batch('phase7_action_audit',jsonb_build_array(row_data,row_data)); RAISE EXCEPTION 'missing duplicate guard';
  EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'duplicate_source_key' THEN RAISE; END IF; END;
  SELECT to_jsonb(t) INTO row_data FROM tj.phase7_automation_policies t LIMIT 1;
  row_data:=row_data||jsonb_build_object('id',gen_random_uuid(),'created_at','2026-10-09T12:00:00.185084Z');
  response:=public.aiq_apply_delta_batch('phase7_automation_policies',jsonb_build_array(row_data));
  IF response->>'inserted'<>'1' THEN RAISE EXCEPTION 'policy_insert_missing'; END IF;
END $$;
ROLLBACK;
SELECT 'PASS: service-only, table/window/column/duplicate guards, insert, conflict rejection, retry, both types; fixtures rolled back' AS result;
