BEGIN;
SELECT set_config('request.jwt.claim.role','authenticated',true);
DO $$ BEGIN
  IF has_function_privilege('anon','public.aiq_turnstile_consume_budget(text)','EXECUTE') OR has_function_privilege('authenticated','public.aiq_turnstile_consume_budget(text)','EXECUTE') THEN RAISE EXCEPTION 'client_grants_exposed'; END IF;
  BEGIN PERFORM public.aiq_turnstile_consume_budget('https://migration-rollback.example'); RAISE EXCEPTION 'missing_auth_guard'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
SELECT set_config('request.jwt.claim.role','service_role',true);
DO $$ DECLARE i integer; BEGIN
  BEGIN PERFORM public.aiq_turnstile_consume_budget('http://unapproved.example'); RAISE EXCEPTION 'invalid_origin_accepted'; EXCEPTION WHEN OTHERS THEN IF SQLERRM<>'invalid_origin' THEN RAISE; END IF; END;
  FOR i IN 1..60 LOOP IF NOT public.aiq_turnstile_consume_budget('https://migration-rollback.example') THEN RAISE EXCEPTION 'budget_exhausted_early'; END IF; END LOOP;
  IF public.aiq_turnstile_consume_budget('https://migration-rollback.example') THEN RAISE EXCEPTION 'budget_not_enforced'; END IF;
  IF NOT public.aiq_turnstile_consume_budget('https://another-rollback.example') THEN RAISE EXCEPTION 'origin_budget_not_isolated'; END IF;
  UPDATE tj_private.turnstile_rate_windows SET attempts=599 WHERE budget_key='global' AND window_start=date_trunc('minute',clock_timestamp());
  IF NOT public.aiq_turnstile_consume_budget('https://global-rollback.example') OR public.aiq_turnstile_consume_budget('https://global-rollback.example') THEN RAISE EXCEPTION 'global_budget_not_enforced'; END IF;
  INSERT INTO tj_private.turnstile_rate_windows(budget_key,window_start,attempts) VALUES('expired_fixture',clock_timestamp()-interval '10 minutes',1);
  PERFORM public.aiq_turnstile_consume_budget('https://global-rollback.example');
  IF EXISTS(SELECT 1 FROM tj_private.turnstile_rate_windows WHERE budget_key='expired_fixture') THEN RAISE EXCEPTION 'expired_counter_not_removed'; END IF;
END $$;
ROLLBACK;
SELECT 'PASS: private grants, service-only gate, bounded origin budget, isolation; fixtures rolled back' result;
