-- Public pre-login challenge service. Aggregate budgets contain no tokens, IPs or user data.
CREATE TABLE tj_private.turnstile_rate_windows(
  budget_key text NOT NULL,
  window_start timestamptz NOT NULL,
  organization_id uuid CHECK(organization_id IS NULL),
  attempts integer NOT NULL CHECK(attempts BETWEEN 1 AND 600),
  PRIMARY KEY(budget_key,window_start)
);
CREATE INDEX turnstile_rate_windows_expiry_idx ON tj_private.turnstile_rate_windows(window_start);
ALTER TABLE tj_private.turnstile_rate_windows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.turnstile_rate_windows FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.turnstile_rate_windows IS 'Private aggregate pre-login CAPTCHA budgets; organization_id is null because these are global infrastructure counters, not tenant/customer records. Short retention, no direct client/service access.';
CREATE FUNCTION tj_private.turnstile_consume_budget(p_origin text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_window timestamptz:=date_trunc('minute',clock_timestamp()); v_key text; v_limit integer; v_count integer;
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_role_required' USING ERRCODE='42501'; END IF;
  IF p_origin IS NULL OR length(p_origin)>253 OR p_origin !~ '^https://[a-zA-Z0-9.-]+(:[0-9]{1,5})?$' THEN RAISE EXCEPTION 'invalid_origin'; END IF;
  DELETE FROM tj_private.turnstile_rate_windows WHERE window_start<v_window-interval '5 minutes';
  FOR v_key,v_limit IN SELECT k,n FROM (VALUES(1,'global',600),(2,md5(p_origin),60)) limits(ord,k,n) ORDER BY ord LOOP
    INSERT INTO tj_private.turnstile_rate_windows(budget_key,window_start,attempts) VALUES(v_key,v_window,1)
    ON CONFLICT(budget_key,window_start) DO UPDATE SET attempts=tj_private.turnstile_rate_windows.attempts+1 WHERE tj_private.turnstile_rate_windows.attempts<v_limit;
    GET DIAGNOSTICS v_count=ROW_COUNT;
    IF v_count=0 THEN RETURN false; END IF;
  END LOOP;
  RETURN true;
END $$;
REVOKE ALL ON FUNCTION tj_private.turnstile_consume_budget(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.turnstile_consume_budget(text) TO service_role;
CREATE FUNCTION public.aiq_turnstile_consume_budget(p_origin text) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.turnstile_consume_budget(p_origin); $$;
REVOKE ALL ON FUNCTION public.aiq_turnstile_consume_budget(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_turnstile_consume_budget(text) TO service_role;
