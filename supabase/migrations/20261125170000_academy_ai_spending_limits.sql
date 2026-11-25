-- IQ Academy AI spending limits.
-- Every Academy AI call is reserved here before the model is called and settled
-- afterwards, so limits are enforced by the database, not by the browser.
--   * Learner monthly limits: graded role-plays and Trainer questions (per seat).
--   * Company pool: the same per-seat amounts times the company's Academy seats.
--   * Role-play limits: maximum turns and minutes per role-play.
--   * Company monthly dollar budget (set by the company admin; unset = paused).
--   * One off switch for everyone and one per company.
--   * Cost of every Academy AI call recorded by company.
-- Tables are private: RLS on, no grants to PUBLIC, anon, authenticated or
-- service_role. Access is only through the functions below.

-- Platform-wide controls (one row). organization_id is always NULL because this
-- row is the switch for everyone, not a tenant record.
CREATE TABLE tj_private.academy_ai_platform_controls(
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  organization_id uuid CHECK(organization_id IS NULL),
  ai_enabled boolean NOT NULL DEFAULT true,
  trainer_questions_per_seat integer NOT NULL DEFAULT 200 CHECK(trainer_questions_per_seat BETWEEN 0 AND 10000),
  graded_roleplays_per_seat integer NOT NULL DEFAULT 10 CHECK(graded_roleplays_per_seat BETWEEN 0 AND 1000),
  roleplay_max_turns integer NOT NULL DEFAULT 20 CHECK(roleplay_max_turns BETWEEN 1 AND 100),
  roleplay_max_minutes integer NOT NULL DEFAULT 15 CHECK(roleplay_max_minutes BETWEEN 1 AND 240),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);
INSERT INTO tj_private.academy_ai_platform_controls DEFAULT VALUES;
ALTER TABLE tj_private.academy_ai_platform_controls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.academy_ai_platform_controls FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.academy_ai_platform_controls IS 'Academy AI switch for everyone plus per-seat learner limits. Single row; organization_id is NULL because it is platform infrastructure. No direct client/service access.';

-- Per-company switch and monthly dollar budget. A missing row or NULL budget
-- pauses Academy AI for that company until its admin sets a budget.
CREATE TABLE tj_private.academy_ai_company_controls(
  organization_id uuid PRIMARY KEY REFERENCES tj.organizations(id) ON DELETE CASCADE,
  ai_enabled boolean NOT NULL DEFAULT true,
  monthly_budget_usd numeric(10,2) CHECK(monthly_budget_usd BETWEEN 0 AND 100000),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);
ALTER TABLE tj_private.academy_ai_company_controls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.academy_ai_company_controls FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.academy_ai_company_controls IS 'Academy AI per-company off switch and monthly USD budget. Read and written only through academy_ai_admin and academy_ai_reserve.';

-- One row per AI role-play. Graded role-plays count toward the monthly limit
-- when the row is created. Keys are built by the Edge functions:
-- proxy:<uuid> (ungraded Academy showroom), kpi:<uuid> (KPI role-play),
-- perf:<uuid> (Beat the Bot), h2h:<uuid> (Human to Human scoring).
CREATE TABLE tj_private.academy_ai_roleplays(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES tj.organizations(id) ON DELETE CASCADE,
  learner_id uuid NOT NULL,
  session_key text NOT NULL UNIQUE CHECK(session_key ~ '^(proxy|kpi|perf|h2h):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'),
  graded boolean NOT NULL,
  usage_month date NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  turns integer NOT NULL DEFAULT 0 CHECK(turns BETWEEN 0 AND 100),
  graded_at timestamptz
);
CREATE INDEX academy_ai_roleplays_learner_month_idx ON tj_private.academy_ai_roleplays(learner_id,usage_month) WHERE graded;
CREATE INDEX academy_ai_roleplays_org_month_idx ON tj_private.academy_ai_roleplays(organization_id,usage_month) WHERE graded;
ALTER TABLE tj_private.academy_ai_roleplays ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.academy_ai_roleplays FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.academy_ai_roleplays IS 'Academy AI role-play turn/time counters and graded role-play usage. No transcript content.';

-- Cost ledger: one row per Academy AI model call, by company. Holds no prompt
-- or answer text. Unsettled reservations count at their reserved (maximum) cost.
CREATE TABLE tj_private.academy_ai_calls(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES tj.organizations(id) ON DELETE CASCADE,
  learner_id uuid NOT NULL,
  feature text NOT NULL CHECK(feature IN ('trainer','beat_the_bot','showroom','grading','content_ideas')),
  model text NOT NULL CHECK(model IN ('claude-haiku-5-5','claude-sonnet-5-5')),
  roleplay_id uuid REFERENCES tj_private.academy_ai_roleplays(id) ON DELETE SET NULL,
  counts_as text CHECK(counts_as IN ('trainer_question')),
  new_turn boolean NOT NULL DEFAULT false,
  created_roleplay boolean NOT NULL DEFAULT false,
  usage_month date NOT NULL,
  status text NOT NULL DEFAULT 'reserved' CHECK(status IN ('reserved','settled','failed','unknown')),
  max_output_tokens integer NOT NULL CHECK(max_output_tokens BETWEEN 1 AND 2000),
  reserved_usd numeric(12,6) NOT NULL CHECK(reserved_usd>=0),
  input_tokens integer CHECK(input_tokens>=0),
  output_tokens integer CHECK(output_tokens>=0),
  cost_usd numeric(12,6) CHECK(cost_usd>=0),
  error text CHECK(length(error)<=200),
  created_at timestamptz NOT NULL DEFAULT now(),
  settled_at timestamptz
);
CREATE INDEX academy_ai_calls_org_month_idx ON tj_private.academy_ai_calls(organization_id,usage_month);
CREATE INDEX academy_ai_calls_learner_month_idx ON tj_private.academy_ai_calls(learner_id,usage_month) WHERE counts_as IS NOT NULL;
CREATE INDEX academy_ai_calls_roleplay_idx ON tj_private.academy_ai_calls(roleplay_id) WHERE roleplay_id IS NOT NULL;
ALTER TABLE tj_private.academy_ai_calls ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.academy_ai_calls FROM PUBLIC,anon,authenticated,service_role;
COMMENT ON TABLE tj_private.academy_ai_calls IS 'Academy AI cost ledger by company: model, tokens and USD cost per call. No prompt or answer text.';

-- Anthropic first-party list prices (USD per million tokens), checked 2026-11-25:
-- claude-haiku-5-5 $0.10 in / $0.50 out for prompts up to 100K tokens, $0.50 / $2.50 above;
-- claude-sonnet-5-5 $2.00 in / $10.00 out. Unknown models have no price and are refused.
CREATE FUNCTION tj_private.academy_ai_cost_usd(p_model text,p_input_tokens bigint,p_output_tokens bigint) RETURNS numeric
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT round(CASE p_model
  WHEN 'claude-haiku-5-5' THEN CASE WHEN p_input_tokens>100000 THEN p_input_tokens*0.50+p_output_tokens*2.50 ELSE p_input_tokens*0.10+p_output_tokens*0.50 END
  WHEN 'claude-sonnet-5-5' THEN p_input_tokens*2.00+p_output_tokens*10.00
 END/1000000.0,6);
$$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_cost_usd(text,bigint,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_cost_usd(text,bigint,bigint) TO service_role;

-- The model each feature must use. The Edge policy picks the same model; this
-- refuses a mismatch so the ledger cannot be charged for any other model.
CREATE FUNCTION tj_private.academy_ai_feature_model(p_feature text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN p_feature='grading' THEN 'claude-sonnet-5-5'
  WHEN p_feature IN ('trainer','beat_the_bot','showroom','content_ideas') THEN 'claude-haiku-5-5' END;
$$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_feature_model(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_feature_model(text) TO service_role;

-- Reserve one AI call. Called by Edge functions (service role) after the caller's
-- session was verified. Returns {allowed:false, reason} when a limit applies, so
-- the learner gets a plain message and no model call is made. p_input_bytes is
-- the UTF-8 size of the exact system prompt and messages; a token is never
-- smaller than one byte, so the reserved amount is an upper bound on cost.
CREATE FUNCTION tj_private.academy_ai_reserve(
  p_native_user uuid,p_organization_id uuid,p_feature text,p_model text,
  p_max_output_tokens integer,p_input_bytes integer,
  p_session_key text DEFAULT NULL,p_new_turn boolean DEFAULT false
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  v_learner uuid; v_month date:=(date_trunc('month',now() AT TIME ZONE 'UTC'))::date;
  pc tj_private.academy_ai_platform_controls%rowtype; cc tj_private.academy_ai_company_controls%rowtype;
  rp tj_private.academy_ai_roleplays%rowtype; seats integer; used integer; pool_used integer;
  v_graded boolean; new_roleplay boolean:=false; counts text; reserve_usd numeric; spent numeric; call_id uuid;
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501'; END IF;
  IF p_feature IS NULL OR tj_private.academy_ai_feature_model(p_feature) IS NULL THEN RAISE EXCEPTION 'unknown_feature' USING ERRCODE='22023'; END IF;
  IF p_model IS DISTINCT FROM tj_private.academy_ai_feature_model(p_feature) THEN RAISE EXCEPTION 'model_not_allowed_for_feature' USING ERRCODE='22023'; END IF;
  IF p_max_output_tokens IS NULL OR p_max_output_tokens NOT BETWEEN 1 AND 2000 OR p_input_bytes IS NULL OR p_input_bytes NOT BETWEEN 1 AND 400000 THEN RAISE EXCEPTION 'invalid_call_size' USING ERRCODE='22023'; END IF;
  IF p_session_key IS NOT NULL AND p_session_key !~ '^(proxy|kpi|perf|h2h):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RAISE EXCEPTION 'invalid_session_key' USING ERRCODE='22023'; END IF;
  IF p_feature IN ('showroom','beat_the_bot','grading') AND p_session_key IS NULL THEN RAISE EXCEPTION 'roleplay_session_required' USING ERRCODE='22023'; END IF;
  IF p_feature IN ('trainer','content_ideas') AND p_session_key IS NOT NULL THEN RAISE EXCEPTION 'unexpected_session' USING ERRCODE='22023'; END IF;

  v_learner:=tj_private.handoff_source_user(p_native_user);
  IF v_learner IS NULL THEN RAISE EXCEPTION 'Mapped identity required' USING ERRCODE='42501'; END IF;
  IF p_organization_id IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organizations o WHERE o.id=p_organization_id AND o.status='active' AND o.deleted_at IS NULL)
     OR NOT (EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_organization_id AND m.user_id=v_learner AND m.status='active') OR EXISTS(SELECT 1 FROM tj.platform_admins a WHERE a.user_id=v_learner)) THEN
    RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501';
  END IF;

  -- One reservation at a time per company, so pools and budgets cannot be overrun by parallel calls.
  PERFORM pg_advisory_xact_lock(hashtextextended('academy-ai:'||p_organization_id::text,0));

  SELECT * INTO pc FROM tj_private.academy_ai_platform_controls WHERE singleton;
  IF NOT FOUND OR NOT pc.ai_enabled THEN RETURN jsonb_build_object('allowed',false,'reason','ai_paused_platform'); END IF;
  SELECT * INTO cc FROM tj_private.academy_ai_company_controls WHERE organization_id=p_organization_id;
  IF FOUND AND NOT cc.ai_enabled THEN RETURN jsonb_build_object('allowed',false,'reason','ai_paused_company'); END IF;
  IF NOT FOUND OR cc.monthly_budget_usd IS NULL THEN RETURN jsonb_build_object('allowed',false,'reason','budget_not_set'); END IF;

  SELECT coalesce(sum(e.seats_included),0) INTO seats FROM tj.org_app_entitlements e
   WHERE e.organization_id=p_organization_id AND e.app_key='iq_academy'
     AND (e.status='active' OR (e.status='trial' AND (e.trial_ends_at IS NULL OR e.trial_ends_at>now())));
  IF seats<1 THEN RETURN jsonb_build_object('allowed',false,'reason','no_academy_seats'); END IF;

  -- Role-play checks (no writes until every check has passed).
  IF p_session_key IS NOT NULL THEN
    SELECT * INTO rp FROM tj_private.academy_ai_roleplays WHERE session_key=p_session_key FOR UPDATE;
    IF FOUND THEN
      IF rp.learner_id<>v_learner OR rp.organization_id<>p_organization_id THEN RAISE EXCEPTION 'Role-play access denied' USING ERRCODE='42501'; END IF;
    ELSE
      new_roleplay:=true;
      v_graded:=p_session_key !~ '^proxy:';
      IF p_feature='grading' AND NOT v_graded THEN RETURN jsonb_build_object('allowed',false,'reason','not_gradable'); END IF;
      IF v_graded THEN
        SELECT count(*) INTO used FROM tj_private.academy_ai_roleplays WHERE learner_id=v_learner AND organization_id=p_organization_id AND usage_month=v_month AND graded;
        IF used>=pc.graded_roleplays_per_seat THEN RETURN jsonb_build_object('allowed',false,'reason','graded_roleplay_limit','limit',pc.graded_roleplays_per_seat); END IF;
        SELECT count(*) INTO pool_used FROM tj_private.academy_ai_roleplays WHERE organization_id=p_organization_id AND usage_month=v_month AND graded;
        IF pool_used>=pc.graded_roleplays_per_seat*seats THEN RETURN jsonb_build_object('allowed',false,'reason','company_graded_roleplay_pool','limit',pc.graded_roleplays_per_seat*seats); END IF;
      END IF;
      rp.turns:=0; rp.started_at:=now(); rp.graded:=v_graded; rp.graded_at:=NULL;
    END IF;
    IF p_feature='grading' THEN
      IF NOT rp.graded THEN RETURN jsonb_build_object('allowed',false,'reason','not_gradable'); END IF;
      IF rp.graded_at IS NOT NULL OR (NOT new_roleplay AND EXISTS(SELECT 1 FROM tj_private.academy_ai_calls c WHERE c.roleplay_id=rp.id AND c.feature='grading' AND c.status IN ('reserved','settled','unknown'))) THEN
        RETURN jsonb_build_object('allowed',false,'reason','already_graded');
      END IF;
    ELSE
      IF rp.graded_at IS NOT NULL THEN RETURN jsonb_build_object('allowed',false,'reason','roleplay_ended'); END IF;
      IF (p_new_turn OR new_roleplay) AND now()>=rp.started_at+make_interval(mins=>pc.roleplay_max_minutes) THEN
        RETURN jsonb_build_object('allowed',false,'reason','roleplay_time_limit','limit',pc.roleplay_max_minutes);
      END IF;
      IF p_new_turn AND rp.turns>=pc.roleplay_max_turns THEN RETURN jsonb_build_object('allowed',false,'reason','roleplay_turn_limit','limit',pc.roleplay_max_turns); END IF;
    END IF;
  END IF;

  -- Trainer questions (content ideas are also one question by the asking admin).
  IF p_feature IN ('trainer','content_ideas') THEN
    counts:='trainer_question';
    SELECT count(*) INTO used FROM tj_private.academy_ai_calls WHERE learner_id=v_learner AND organization_id=p_organization_id AND usage_month=v_month AND counts_as=counts AND status<>'failed';
    IF used>=pc.trainer_questions_per_seat THEN RETURN jsonb_build_object('allowed',false,'reason','trainer_question_limit','limit',pc.trainer_questions_per_seat); END IF;
    SELECT count(*) INTO pool_used FROM tj_private.academy_ai_calls WHERE organization_id=p_organization_id AND usage_month=v_month AND counts_as=counts AND status<>'failed';
    IF pool_used>=pc.trainer_questions_per_seat*seats THEN RETURN jsonb_build_object('allowed',false,'reason','company_trainer_question_pool','limit',pc.trainer_questions_per_seat*seats); END IF;
  END IF;

  -- Monthly dollar budget, counting in-flight reservations at their maximum cost.
  reserve_usd:=tj_private.academy_ai_cost_usd(p_model,p_input_bytes,p_max_output_tokens);
  IF reserve_usd IS NULL THEN RAISE EXCEPTION 'model_not_priced' USING ERRCODE='22023'; END IF;
  SELECT coalesce(sum(coalesce(c.cost_usd,c.reserved_usd)),0) INTO spent FROM tj_private.academy_ai_calls c
   WHERE c.organization_id=p_organization_id AND c.usage_month=v_month AND c.status IN ('reserved','settled','unknown');
  IF spent+reserve_usd>cc.monthly_budget_usd THEN
    RETURN jsonb_build_object('allowed',false,'reason','company_budget_reached','budget_usd',cc.monthly_budget_usd,'spent_usd',round(spent,2));
  END IF;

  -- All checks passed: record the role-play turn and the reservation.
  IF p_session_key IS NOT NULL THEN
    IF new_roleplay THEN
      INSERT INTO tj_private.academy_ai_roleplays(organization_id,learner_id,session_key,graded,usage_month,turns)
      VALUES(p_organization_id,v_learner,p_session_key,rp.graded,v_month,CASE WHEN p_new_turn AND p_feature<>'grading' THEN 1 ELSE 0 END) RETURNING * INTO rp;
    ELSIF p_new_turn AND p_feature<>'grading' THEN
      UPDATE tj_private.academy_ai_roleplays SET turns=turns+1 WHERE id=rp.id RETURNING * INTO rp;
    END IF;
  END IF;
  INSERT INTO tj_private.academy_ai_calls(organization_id,learner_id,feature,model,roleplay_id,counts_as,new_turn,created_roleplay,usage_month,max_output_tokens,reserved_usd)
  VALUES(p_organization_id,v_learner,p_feature,p_model,rp.id,counts,p_new_turn AND p_feature<>'grading',new_roleplay,v_month,p_max_output_tokens,reserve_usd)
  RETURNING id INTO call_id;
  RETURN jsonb_build_object('allowed',true,'call_id',call_id,'roleplay_id',rp.id,'turns',rp.turns,'reserved_usd',reserve_usd,
    'turns_limit',pc.roleplay_max_turns,'minutes_limit',pc.roleplay_max_minutes);
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean) TO service_role;

-- Settle a reservation with what the provider reported.
--   ok      : cost from reported tokens.
--   failed  : the provider rejected the request (not billed); cost 0, and a
--             turn or new graded role-play taken by this call is given back.
--   unknown : timeout or lost response (may have been billed); cost stays at
--             the reserved maximum.
CREATE FUNCTION tj_private.academy_ai_settle(p_call_id uuid,p_outcome text,p_input_tokens integer DEFAULT 0,p_output_tokens integer DEFAULT 0,p_error text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE c tj_private.academy_ai_calls%rowtype; cost numeric;
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501'; END IF;
  IF p_outcome IS NULL OR p_outcome NOT IN ('ok','failed','unknown') OR length(p_error)>200 THEN RAISE EXCEPTION 'invalid_settlement' USING ERRCODE='22023'; END IF;
  IF p_outcome='ok' AND (p_input_tokens IS NULL OR p_output_tokens IS NULL OR p_input_tokens NOT BETWEEN 0 AND 2000000 OR p_output_tokens NOT BETWEEN 0 AND 200000) THEN RAISE EXCEPTION 'invalid_usage' USING ERRCODE='22023'; END IF;
  SELECT * INTO c FROM tj_private.academy_ai_calls WHERE id=p_call_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'call_not_found' USING ERRCODE='42501'; END IF;
  IF c.status<>'reserved' THEN RAISE EXCEPTION 'call_already_settled' USING ERRCODE='40001'; END IF;
  IF p_outcome='ok' THEN
    cost:=tj_private.academy_ai_cost_usd(c.model,p_input_tokens,p_output_tokens);
    UPDATE tj_private.academy_ai_calls SET status='settled',input_tokens=p_input_tokens,output_tokens=p_output_tokens,cost_usd=cost,settled_at=now() WHERE id=c.id;
    IF c.feature='grading' AND c.roleplay_id IS NOT NULL THEN UPDATE tj_private.academy_ai_roleplays SET graded_at=now() WHERE id=c.roleplay_id; END IF;
  ELSIF p_outcome='failed' THEN
    cost:=0;
    UPDATE tj_private.academy_ai_calls SET status='failed',cost_usd=0,error=p_error,settled_at=now() WHERE id=c.id;
    IF c.roleplay_id IS NOT NULL THEN
      IF c.created_roleplay AND NOT EXISTS(SELECT 1 FROM tj_private.academy_ai_calls o WHERE o.roleplay_id=c.roleplay_id AND o.id<>c.id) THEN
        DELETE FROM tj_private.academy_ai_roleplays WHERE id=c.roleplay_id;
      ELSIF c.new_turn THEN
        UPDATE tj_private.academy_ai_roleplays SET turns=greatest(turns-1,0) WHERE id=c.roleplay_id;
      END IF;
    END IF;
  ELSE
    cost:=c.reserved_usd;
    UPDATE tj_private.academy_ai_calls SET status='unknown',cost_usd=c.reserved_usd,error=p_error,settled_at=now() WHERE id=c.id;
  END IF;
  RETURN jsonb_build_object('call_id',c.id,'status',CASE p_outcome WHEN 'ok' THEN 'settled' ELSE p_outcome END,'cost_usd',cost);
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_settle(uuid,text,integer,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_settle(uuid,text,integer,integer,text) TO service_role;

-- ai-roleplay generates the opening line before its session row exists, so the
-- role-play is reserved under a temporary kpi: key and renamed to the session id
-- here. Only the learner who owns it can rename it, and only to an unused key.
CREATE FUNCTION tj_private.academy_ai_link_roleplay(p_native_user uuid,p_from_key text,p_to_key text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_learner uuid; n integer;
BEGIN
  IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'Service role required' USING ERRCODE='42501'; END IF;
  IF p_from_key !~ '^kpi:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' OR p_to_key !~ '^kpi:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RAISE EXCEPTION 'invalid_session_key' USING ERRCODE='22023'; END IF;
  v_learner:=tj_private.handoff_source_user(p_native_user);
  IF v_learner IS NULL THEN RAISE EXCEPTION 'Mapped identity required' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM tj_private.academy_ai_roleplays WHERE session_key=p_to_key) THEN RAISE EXCEPTION 'session_key_in_use' USING ERRCODE='23505'; END IF;
  UPDATE tj_private.academy_ai_roleplays SET session_key=p_to_key WHERE session_key=p_from_key AND learner_id=v_learner AND graded_at IS NULL;
  GET DIAGNOSTICS n=ROW_COUNT;
  RETURN n=1;
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_link_roleplay(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_link_roleplay(uuid,text,text) TO service_role;

-- Company admin controls and usage. Actions:
--   my_usage             any active member: own remaining questions/role-plays and pause state
--   status               company admin: budget, spend, pools and cost by feature this month
--   set_budget           company admin: {"monthly_budget_usd": 0..100000 or null}
--   set_enabled          company admin: {"enabled": true|false}
--   set_platform_enabled platform admin only: {"enabled": true|false} (switch for everyone)
CREATE FUNCTION tj_private.academy_ai_admin(p_organization_id uuid,p_action text,p_payload jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
  actor uuid:=tj_private.current_source_user_id(); v_month date:=(date_trunc('month',now() AT TIME ZONE 'UTC'))::date;
  pc tj_private.academy_ai_platform_controls%rowtype; cc tj_private.academy_ai_company_controls%rowtype;
  before_row jsonb; after_row jsonb; seats integer; budget numeric; enabled boolean;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE='42501'; END IF;
  IF p_organization_id IS NULL OR p_action IS NULL OR jsonb_typeof(coalesce(p_payload,'{}')) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  SELECT * INTO pc FROM tj_private.academy_ai_platform_controls WHERE singleton;
  SELECT * INTO cc FROM tj_private.academy_ai_company_controls WHERE organization_id=p_organization_id;
  SELECT coalesce(sum(e.seats_included),0) INTO seats FROM tj.org_app_entitlements e
   WHERE e.organization_id=p_organization_id AND e.app_key='iq_academy'
     AND (e.status='active' OR (e.status='trial' AND (e.trial_ends_at IS NULL OR e.trial_ends_at>now())));

  IF p_action='my_usage' THEN
    IF NOT tj_private.is_org_member(p_organization_id) THEN RAISE EXCEPTION 'member_required' USING ERRCODE='42501'; END IF;
    RETURN jsonb_build_object(
      'ai_available',pc.ai_enabled AND coalesce(cc.ai_enabled,true) AND cc.monthly_budget_usd IS NOT NULL AND seats>0,
      'trainer_questions_used',(SELECT count(*) FROM tj_private.academy_ai_calls WHERE learner_id=actor AND organization_id=p_organization_id AND usage_month=v_month AND counts_as='trainer_question' AND status<>'failed'),
      'trainer_questions_limit',pc.trainer_questions_per_seat,
      'graded_roleplays_used',(SELECT count(*) FROM tj_private.academy_ai_roleplays WHERE learner_id=actor AND organization_id=p_organization_id AND usage_month=v_month AND graded),
      'graded_roleplays_limit',pc.graded_roleplays_per_seat,
      'roleplay_max_turns',pc.roleplay_max_turns,'roleplay_max_minutes',pc.roleplay_max_minutes);
  END IF;

  IF p_action='set_platform_enabled' THEN
    IF NOT tj_private.is_platform_admin() THEN RAISE EXCEPTION 'platform_admin_required' USING ERRCODE='42501'; END IF;
    IF jsonb_typeof(p_payload->'enabled') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid_enabled' USING ERRCODE='22023'; END IF;
    before_row:=jsonb_build_object('ai_enabled',pc.ai_enabled);
    UPDATE tj_private.academy_ai_platform_controls SET ai_enabled=(p_payload->>'enabled')::boolean,updated_at=now(),updated_by=actor WHERE singleton RETURNING * INTO pc;
    after_row:=jsonb_build_object('ai_enabled',pc.ai_enabled);
    INSERT INTO tj_private.company_admin_audit(organization_id,actor_source_user_id,action,before_data,after_data) VALUES(p_organization_id,actor,'academy_ai_set_platform_enabled',before_row,after_row);
    RETURN jsonb_build_object('ok',true,'platform_ai_enabled',pc.ai_enabled);
  END IF;

  IF NOT tj_private.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'company_admin_required' USING ERRCODE='42501'; END IF;

  IF p_action='status' THEN
    RETURN jsonb_build_object(
      'month',v_month,'platform_ai_enabled',pc.ai_enabled,'company_ai_enabled',coalesce(cc.ai_enabled,true),
      'monthly_budget_usd',cc.monthly_budget_usd,'seats',seats,
      'spent_usd',(SELECT round(coalesce(sum(coalesce(cost_usd,reserved_usd)),0),4) FROM tj_private.academy_ai_calls WHERE organization_id=p_organization_id AND usage_month=v_month AND status IN ('reserved','settled','unknown')),
      'calls',(SELECT count(*) FROM tj_private.academy_ai_calls WHERE organization_id=p_organization_id AND usage_month=v_month AND status<>'failed'),
      'cost_by_feature',(SELECT coalesce(jsonb_object_agg(feature,usd),'{}') FROM (SELECT feature,round(sum(coalesce(cost_usd,reserved_usd)),4) usd FROM tj_private.academy_ai_calls WHERE organization_id=p_organization_id AND usage_month=v_month AND status IN ('reserved','settled','unknown') GROUP BY feature) f),
      'trainer_questions_used',(SELECT count(*) FROM tj_private.academy_ai_calls WHERE organization_id=p_organization_id AND usage_month=v_month AND counts_as='trainer_question' AND status<>'failed'),
      'trainer_questions_pool',pc.trainer_questions_per_seat*seats,
      'graded_roleplays_used',(SELECT count(*) FROM tj_private.academy_ai_roleplays WHERE organization_id=p_organization_id AND usage_month=v_month AND graded),
      'graded_roleplays_pool',pc.graded_roleplays_per_seat*seats,
      'per_learner',jsonb_build_object('trainer_questions',pc.trainer_questions_per_seat,'graded_roleplays',pc.graded_roleplays_per_seat,'roleplay_max_turns',pc.roleplay_max_turns,'roleplay_max_minutes',pc.roleplay_max_minutes));
  END IF;

  IF p_action NOT IN ('set_budget','set_enabled') THEN RAISE EXCEPTION 'unknown_action' USING ERRCODE='22023'; END IF;
  before_row:=CASE WHEN cc.organization_id IS NULL THEN NULL ELSE jsonb_build_object('ai_enabled',cc.ai_enabled,'monthly_budget_usd',cc.monthly_budget_usd) END;
  IF p_action='set_budget' THEN
    IF NOT p_payload ? 'monthly_budget_usd' OR jsonb_typeof(p_payload->'monthly_budget_usd') NOT IN ('number','null') THEN RAISE EXCEPTION 'invalid_budget' USING ERRCODE='22023'; END IF;
    budget:=(p_payload->>'monthly_budget_usd')::numeric;
    IF budget IS NOT NULL AND (budget<0 OR budget>100000 OR budget<>round(budget,2)) THEN RAISE EXCEPTION 'invalid_budget' USING ERRCODE='22023'; END IF;
    INSERT INTO tj_private.academy_ai_company_controls(organization_id,monthly_budget_usd,updated_by) VALUES(p_organization_id,budget,actor)
    ON CONFLICT(organization_id) DO UPDATE SET monthly_budget_usd=excluded.monthly_budget_usd,updated_at=now(),updated_by=actor RETURNING * INTO cc;
  ELSE
    IF jsonb_typeof(p_payload->'enabled') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid_enabled' USING ERRCODE='22023'; END IF;
    enabled:=(p_payload->>'enabled')::boolean;
    INSERT INTO tj_private.academy_ai_company_controls(organization_id,ai_enabled,updated_by) VALUES(p_organization_id,enabled,actor)
    ON CONFLICT(organization_id) DO UPDATE SET ai_enabled=excluded.ai_enabled,updated_at=now(),updated_by=actor RETURNING * INTO cc;
  END IF;
  after_row:=jsonb_build_object('ai_enabled',cc.ai_enabled,'monthly_budget_usd',cc.monthly_budget_usd);
  INSERT INTO tj_private.company_admin_audit(organization_id,actor_source_user_id,action,before_data,after_data) VALUES(p_organization_id,actor,'academy_ai_'||p_action,before_row,after_row);
  RETURN jsonb_build_object('ok',true,'company_ai_enabled',cc.ai_enabled,'monthly_budget_usd',cc.monthly_budget_usd);
END $$;
REVOKE ALL ON FUNCTION tj_private.academy_ai_admin(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.academy_ai_admin(uuid,text,jsonb) TO authenticated;

-- Public adapters, matching the existing aiq_* (service) and tj_runtime_* (browser) conventions.
CREATE FUNCTION public.aiq_academy_ai_reserve(p_native_user uuid,p_organization_id uuid,p_feature text,p_model text,p_max_output_tokens integer,p_input_bytes integer,p_session_key text DEFAULT NULL,p_new_turn boolean DEFAULT false) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.academy_ai_reserve(p_native_user,p_organization_id,p_feature,p_model,p_max_output_tokens,p_input_bytes,p_session_key,p_new_turn); $$;
REVOKE ALL ON FUNCTION public.aiq_academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_academy_ai_reserve(uuid,uuid,text,text,integer,integer,text,boolean) TO service_role;

CREATE FUNCTION public.aiq_academy_ai_settle(p_call_id uuid,p_outcome text,p_input_tokens integer DEFAULT 0,p_output_tokens integer DEFAULT 0,p_error text DEFAULT NULL) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.academy_ai_settle(p_call_id,p_outcome,p_input_tokens,p_output_tokens,p_error); $$;
REVOKE ALL ON FUNCTION public.aiq_academy_ai_settle(uuid,text,integer,integer,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_academy_ai_settle(uuid,text,integer,integer,text) TO service_role;

CREATE FUNCTION public.aiq_academy_ai_link_roleplay(p_native_user uuid,p_from_key text,p_to_key text) RETURNS boolean
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.academy_ai_link_roleplay(p_native_user,p_from_key,p_to_key); $$;
REVOKE ALL ON FUNCTION public.aiq_academy_ai_link_roleplay(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.aiq_academy_ai_link_roleplay(uuid,text,text) TO service_role;

CREATE FUNCTION public.tj_runtime_academy_ai_admin(p_organization_id uuid,p_action text,p_payload jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.academy_ai_admin(p_organization_id,p_action,p_payload); $$;
REVOKE ALL ON FUNCTION public.tj_runtime_academy_ai_admin(uuid,text,jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_academy_ai_admin(uuid,text,jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
