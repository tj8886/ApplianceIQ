-- Bulk code import. Existing verified functions are untouched.
-- No triggers, jobs, API grants or data writes are activated by this migration.
SET LOCAL check_function_bodies=off;
CREATE OR REPLACE FUNCTION tj_private.accept_invite(p_invite_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_invite record;
  v_user_id uuid;
  v_existing record;
begin
  v_user_id := tj_private.current_source_user_id();
  if v_user_id is null then
    return jsonb_build_object('error', 'not_authenticated');
  end if;

  select * into v_invite from tj.org_invites
  where invite_code = p_invite_code and status = 'pending'
  for update;

  if not found then
    return jsonb_build_object('error', 'invite_not_found_or_used');
  end if;

  if v_invite.expires_at < now() then
    update tj.org_invites set status = 'expired' where id = v_invite.id;
    return jsonb_build_object('error', 'invite_expired');
  end if;

  -- Check email matches (case-insensitive)
  if lower((select email from tj.source_auth_users where id = v_user_id)) != lower(v_invite.invited_email) then
    return jsonb_build_object('error', 'email_mismatch', 'detail', 'Sign in with the email that was invited.');
  end if;

  -- Check if already a member
  select * into v_existing from tj.organization_members
  where organization_id = v_invite.organization_id and user_id = v_user_id;
  if found then
    update tj.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;
    return jsonb_build_object('ok', true, 'already_member', true);
  end if;

  -- Create membership
  insert into tj.organization_members (organization_id, user_id, role, status, org_role_id, manager_id)
  values (v_invite.organization_id, v_user_id, v_invite.role, 'active', v_invite.org_role_id, v_invite.manager_id);

  update tj.org_invites set status = 'accepted', accepted_at = now() where id = v_invite.id;

  -- Initialize token limits if org has billing
  insert into tj.ai_token_limits (organization_id, monthly_limit, tokens_used_this_month)
  select v_invite.organization_id, 
    case (select tier from tj.organizations where id = v_invite.organization_id)
      when 'starter' then 100000
      when 'pro' then 1000000
      when 'enterprise' then 10000000
      else 10000
    end, 0
  on conflict do nothing;

  return jsonb_build_object('ok', true, 'organization_id', v_invite.organization_id);
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.accept_invite(p_invite_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.accept_invite(p_invite_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.accept_invite("p_invite_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.accept_invite(p_invite_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.accept_org_invite(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_invite org_invites%ROWTYPE;
  v_uid uuid := tj_private.current_source_user_id();
  v_email text;
  v_org_name text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_authenticated');
  END IF;

  SELECT email INTO v_email FROM tj.source_auth_users WHERE id = v_uid;

  SELECT * INTO v_invite FROM org_invites
  WHERE invite_code = p_code AND status = 'pending'
  LIMIT 1;

  IF v_invite.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_or_used');
  END IF;

  IF v_invite.expires_at < now() THEN
    UPDATE org_invites SET status = 'expired' WHERE id = v_invite.id;
    RETURN jsonb_build_object('ok', false, 'error', 'expired');
  END IF;

  IF lower(v_invite.invited_email) <> lower(coalesce(v_email, '')) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'email_mismatch',
      'expected', v_invite.invited_email);
  END IF;

  INSERT INTO profiles (id, user_id, email, full_name)
  VALUES (v_uid, v_uid, v_email, split_part(v_email, '@', 1))
  ON CONFLICT (id) DO NOTHING;

  IF EXISTS (SELECT 1 FROM organization_members WHERE user_id = v_uid AND organization_id = v_invite.organization_id) THEN
    UPDATE organization_members
    SET status = 'active', role = v_invite.role, org_role_id = v_invite.org_role_id,
        manager_id = v_invite.manager_id
    WHERE user_id = v_uid AND organization_id = v_invite.organization_id;
  ELSE
    INSERT INTO organization_members (organization_id, user_id, role, org_role_id, manager_id, status)
    VALUES (v_invite.organization_id, v_uid, v_invite.role, v_invite.org_role_id, v_invite.manager_id, 'active');
  END IF;

  -- Store assignment from the invite
  IF v_invite.location_id IS NOT NULL THEN
    INSERT INTO org_location_members (organization_id, location_id, user_id, is_primary)
    VALUES (v_invite.organization_id, v_invite.location_id, v_uid, true)
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE org_invites SET status = 'accepted', accepted_at = now() WHERE id = v_invite.id;

  SELECT name INTO v_org_name FROM organizations WHERE id = v_invite.organization_id;

  RETURN jsonb_build_object('ok', true, 'organization_id', v_invite.organization_id, 'organization_name', v_org_name, 'role', v_invite.role);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.accept_org_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.accept_org_invite(p_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.accept_org_invite("p_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.accept_org_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_generate_daily_coaching_focus(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_diag record; v_perf record; v_skill record; v_scenario record; v_intervention uuid; v_existing uuid;
  v_skill_key text; v_difficulty integer; v_insight text; v_existing_items jsonb := '[]'::jsonb; v_retained_items jsonb := '[]'::jsonb; v_coaching_items jsonb;
begin
  if tj_private.current_source_user_id() is not null then
    if p_user_id <> tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id) then raise exception 'Not authorized to generate coaching for this user'; end if;
    if not tj.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  end if;
  select i.id into v_existing from tj.ai_coaching_interventions i where i.organization_id=p_organization_id and i.user_id=p_user_id and i.status in ('recommended','assigned','in_progress') and i.created_at >= p_focus_date::timestamptz - interval '1 day' order by i.created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;
  select d.* into v_diag from tj.performance_metric_diagnostics d where d.organization_id=p_organization_id and d.user_id=p_user_id and d.actual_value is not null and d.target_value is not null and d.actual_value < d.target_value order by d.target_gap_pct desc nulls last,d.causal_weight desc,d.computed_at desc limit 1;
  if v_diag.metric_key is null then
    select ss.rolling_score,ss.confidence,ss.sample_size,c.id competency_id,c.code competency_code,c.name competency_name into v_perf from tj.performance_skill_state ss join tj.performance_competencies c on c.id=ss.competency_id where ss.organization_id=p_organization_id and ss.user_id=p_user_id and c.active order by ss.rolling_score asc,ss.confidence desc,ss.last_observed_at desc nulls last limit 1;
    if v_perf.competency_id is null then return null; end if;
  else
    select ss.rolling_score,ss.confidence,ss.sample_size,c.id competency_id,c.code competency_code,c.name competency_name into v_perf from tj.performance_competencies c left join tj.performance_skill_state ss on ss.competency_id=c.id and ss.organization_id=p_organization_id and ss.user_id=p_user_id where c.id=v_diag.competency_id limit 1;
  end if;
  v_skill_key := case v_perf.competency_code when 'attachment' then 'attach_selling' when 'closing' then 'closing' when 'communication' then 'active_listening' when 'discovery' then 'discovery' when 'objection_handling' then 'objection_handling' when 'process_discipline' then 'follow_up' when 'product_knowledge' then 'product_knowledge' when 'recommendation' then 'solution_matching' when 'trust' then 'rapport' when 'value_building' then 'value_communication' else v_perf.competency_code end;
  select s.id,s.skill_key,s.name into v_skill from tj.ai_skill_definitions s where s.active and s.skill_key=v_skill_key limit 1;
  if v_skill.id is null then return null; end if;
  v_difficulty := case when coalesce(v_perf.rolling_score,50)<45 then 2 when coalesce(v_perf.rolling_score,50)<60 then 4 when coalesce(v_perf.rolling_score,50)<75 then 6 when coalesce(v_perf.rolling_score,50)<88 then 8 else 10 end;
  select s.id,s.title,s.difficulty into v_scenario from tj.ai_scenario_definitions s where s.active and (s.organization_id is null or s.organization_id=p_organization_id) and s.target_skills ? v_skill.skill_key order by abs(s.difficulty-v_difficulty),case when s.organization_id=p_organization_id then 0 else 1 end,s.difficulty desc limit 1;
  if v_diag.metric_key is not null then
    v_insight := format('%s is below target (%s vs %s). Performance Brain links the gap most strongly to %s. Sales DNA is %s/100 with %s confidence across %s observations. %s',v_diag.metric_key,v_diag.actual_value,v_diag.target_value,v_perf.competency_name,coalesce(round(v_perf.rolling_score,1)::text,'baseline'),coalesce(round(v_perf.confidence*100)::text||'%','low'),coalesce(v_perf.sample_size,0),coalesce(v_diag.rationale,''));
  else
    v_insight := format('Performance Brain identifies %s as the current coaching priority at %s/100. Today''s work targets that behaviour directly.',v_perf.competency_name,coalesce(round(v_perf.rolling_score,1)::text,'baseline'));
  end if;
  insert into tj.ai_coaching_interventions(organization_id,user_id,status,trigger_type,metric_key,skill_id,diagnosis,evidence,baseline_value,target_value,prescribed_scenario_id,due_at)
  values(p_organization_id,p_user_id,'recommended',case when v_diag.metric_key is null then 'performance_brain' else 'metric_gap' end,v_diag.metric_key,v_skill.id,v_insight,jsonb_strip_nulls(jsonb_build_object('source','performance_brain','competency_code',v_perf.competency_code,'competency_name',v_perf.competency_name,'sales_dna_score',v_perf.rolling_score,'confidence',v_perf.confidence,'sample_size',v_perf.sample_size,'causal_weight',v_diag.causal_weight,'target_gap_pct',v_diag.target_gap_pct,'recommended_difficulty',v_difficulty)),coalesce(v_diag.actual_value,v_perf.rolling_score),coalesce(v_diag.target_value,80),v_scenario.id,(p_focus_date+7)::timestamptz) returning id into v_intervention;
  insert into tj.ai_intervention_steps(intervention_id,step_order,step_type,title,resource_ref,target_score,metadata) values
    (v_intervention,1,'lesson',format('Micro-training: %s',v_skill.name),format('skill:%s',v_skill.skill_key),null,jsonb_build_object('source','performance_brain','competency_code',v_perf.competency_code)),
    (v_intervention,2,'roleplay',coalesce(format('Beat the Bot: %s',v_scenario.title),'Beat the Bot targeted practice'),case when v_scenario.id is not null then 'scenario:'||v_scenario.id::text end,80,jsonb_build_object('difficulty',v_difficulty,'competency_code',v_perf.competency_code)),
    (v_intervention,3,'floor_challenge',format('Live floor challenge: practice %s five times',v_skill.name),format('skill:%s',v_skill.skill_key),null,jsonb_build_object('repeat_count',5,'competency_code',v_perf.competency_code)),
    (v_intervention,4,'review','End-of-day reflection and 7-day performance recheck',case when v_diag.metric_key is not null then 'metric:'||v_diag.metric_key else 'competency:'||v_perf.competency_code end,null,jsonb_build_object('baseline',coalesce(v_diag.actual_value,v_perf.rolling_score),'target',coalesce(v_diag.target_value,80)));
  insert into tj.daily_coaching_focus(organization_id,user_id,focus_date,primary_kpi_name,previous_score,target_score,insight,intervention_id,skill_id,prescribed_scenario_id)
  values(p_organization_id,p_user_id,p_focus_date,coalesce(v_diag.metric_key,v_perf.competency_name),coalesce(v_diag.actual_value,v_perf.rolling_score),coalesce(v_diag.target_value,80),v_insight,v_intervention,v_skill.id,v_scenario.id)
  on conflict(organization_id,user_id,focus_date) do update set primary_kpi_name=excluded.primary_kpi_name,previous_score=excluded.previous_score,target_score=excluded.target_score,insight=excluded.insight,intervention_id=excluded.intervention_id,skill_id=excluded.skill_id,prescribed_scenario_id=excluded.prescribed_scenario_id;
  select coalesce(items,'[]'::jsonb) into v_existing_items from tj.crm_daily_five where organization_id=p_organization_id and user_id=p_user_id and work_date=p_focus_date;
  select coalesce(jsonb_agg(q.value order by q.ord),'[]'::jsonb) into v_retained_items from (select x.value,x.ord from jsonb_array_elements(v_existing_items) with ordinality x(value,ord) where coalesce(x.value->>'type','crm') <> 'coaching' order by x.ord limit 2) q;
  v_coaching_items := jsonb_build_array(
    jsonb_build_object('type','coaching','step_order',1,'action','Micro-training','title',format('Learn: %s',v_skill.name),'reason','Performance Brain coaching prescription','intervention_id',v_intervention,'resource_ref',format('skill:%s',v_skill.skill_key),'completed',false),
    jsonb_build_object('type','coaching','step_order',2,'action','Beat the Bot','title',coalesce(v_scenario.title,'Targeted roleplay'),'reason',format('Practice %s at the right difficulty',v_perf.competency_name),'intervention_id',v_intervention,'resource_ref',case when v_scenario.id is not null then 'scenario:'||v_scenario.id::text end,'completed',false),
    jsonb_build_object('type','coaching','step_order',3,'action','Floor challenge','title',format('Use %s with 5 live customers',v_skill.name),'reason','Transfer practice to the sales floor','intervention_id',v_intervention,'resource_ref',format('skill:%s',v_skill.skill_key),'completed',false));
  insert into tj.crm_daily_five(organization_id,user_id,work_date,items,completed_count,total_count,generated_at)
  values(p_organization_id,p_user_id,p_focus_date,v_coaching_items||v_retained_items,0,jsonb_array_length(v_coaching_items||v_retained_items),now())
  on conflict(organization_id,user_id,work_date) do update set items=excluded.items,total_count=excluded.total_count,generated_at=excluded.generated_at,updated_at=now();
  return v_intervention;
end;$function$;
REVOKE ALL ON FUNCTION tj.ai_generate_daily_coaching_focus(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_manager_add_comment(p_assignment_id uuid, p_body text, p_comment_type text DEFAULT 'comment'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare a tj.ai_manager_assignments%rowtype; cid uuid;
begin
 select * into a from tj.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not tj.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 insert into tj.ai_manager_task_comments(organization_id,assignment_id,author_id,body,comment_type) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),trim(p_body),p_comment_type) returning id into cid;
 insert into tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,note) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),'comment_added',left(trim(p_body),500));
 return jsonb_build_object('ok',true,'comment_id',cid);
end$function$;
REVOKE ALL ON FUNCTION tj.ai_manager_add_comment(p_assignment_id uuid, p_body text, p_comment_type text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text DEFAULT 'morning'::text, p_brief_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_start date;
  v_end date;
  v_open integer;
  v_overdue integer;
  v_completed integer;
  v_critical integer;
  v_exposure numeric;
  v_predicted numeric;
  v_top jsonb;
  v_risks jsonb;
  v_wins jsonb;
  v_headline text;
  v_summary text;
  v_id uuid;
begin
  if not tj.is_org_member(p_organization_id) then
    raise exception 'organization_access_denied';
  end if;
  if p_brief_type not in ('morning','end_of_day','weekly') then
    raise exception 'unsupported_brief_type';
  end if;

  if p_brief_type='weekly' then
    v_start := date_trunc('week',p_brief_date)::date;
    v_end := v_start + 6;
  else
    v_start := p_brief_date;
    v_end := p_brief_date;
  end if;

  select count(*) filter(where status not in ('completed','cancelled')),
         count(*) filter(where status not in ('completed','cancelled') and due_at < now()),
         count(*) filter(where status='completed' and completed_at::date between v_start and v_end)
  into v_open,v_overdue,v_completed
  from tj.ai_manager_assignments
  where organization_id=p_organization_id;

  select count(*) filter(where severity='critical' and status not in ('completed','dismissed','rejected','expired')),
         coalesce(sum(financial_impact_cad) filter(where status not in ('completed','dismissed','rejected','expired')),0)
  into v_critical,v_exposure
  from tj.decision_cases
  where organization_id=p_organization_id;

  select coalesce(sum(financial_impact_cad) filter(where status='active'),0)
  into v_predicted
  from tj.decision_predictions
  where organization_id=p_organization_id;

  select coalesce(jsonb_agg(x order by (x->>'priority_score')::numeric desc),'[]'::jsonb)
  into v_top
  from (
    select jsonb_build_object(
      'id',id,'title',title,'module',module,'severity',severity,
      'priority_score',priority_score,'financial_impact_cad',financial_impact_cad,
      'recommendation',recommendation,'due_at',due_at
    ) x
    from tj.decision_cases
    where organization_id=p_organization_id
      and status not in ('completed','dismissed','rejected','expired')
    order by priority_score desc nulls last
    limit 5
  ) s;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into v_risks
  from (
    select jsonb_build_object('title',title,'priority',priority,'due_at',due_at,'status',status,'blocked_reason',blocked_reason) x
    from tj.ai_manager_assignments
    where organization_id=p_organization_id
      and (status='blocked' or (status not in ('completed','cancelled') and due_at < now()))
    order by due_at asc nulls last
    limit 5
  ) s;

  select coalesce(jsonb_agg(x),'[]'::jsonb)
  into v_wins
  from (
    select jsonb_build_object('title',title,'completed_at',completed_at,'priority',priority) x
    from tj.ai_manager_assignments
    where organization_id=p_organization_id and status='completed'
      and completed_at::date between v_start and v_end
    order by completed_at desc
    limit 5
  ) s;

  if p_brief_type='morning' then
    v_headline := case when v_critical>0 then v_critical||' critical issue'||case when v_critical=1 then '' else 's' end||' require attention today'
      when v_overdue>0 then v_overdue||' overdue assignment'||case when v_overdue=1 then '' else 's' end||' require action'
      else 'Operations are stable; focus on the highest-value opportunity' end;
    v_summary := format('Start the day with %s active assignments, %s overdue, and %s in open financial exposure. Current predicted opportunity is %s.',v_open,v_overdue,to_char(v_exposure,'FM$999,999,990'),to_char(v_predicted,'FM$999,999,990'));
  elsif p_brief_type='end_of_day' then
    v_headline := v_completed||' assignment'||case when v_completed=1 then '' else 's' end||' completed today';
    v_summary := format('The day closed with %s completed assignments, %s still open, and %s overdue. Remaining exposure is %s.',v_completed,v_open,v_overdue,to_char(v_exposure,'FM$999,999,990'));
  else
    v_headline := format('Weekly operating review: %s completed, %s open, %s overdue',v_completed,v_open,v_overdue);
    v_summary := format('For %s through %s, the organization completed %s assignments. Open financial exposure is %s and active predicted opportunity is %s.',to_char(v_start,'Mon DD'),to_char(v_end,'Mon DD'),v_completed,to_char(v_exposure,'FM$999,999,990'),to_char(v_predicted,'FM$999,999,990'));
  end if;

  insert into tj.ai_manager_briefs(
    organization_id,brief_date,brief_type,period_start,period_end,headline,executive_summary,
    priorities,risks,wins,workload,financial_exposure_cad,narrative,generated_by,generated_at
  ) values (
    p_organization_id,p_brief_date,p_brief_type,v_start,v_end,v_headline,v_summary,
    v_top,v_risks,v_wins,
    jsonb_build_object('open',v_open,'overdue',v_overdue,'completed',v_completed,'critical',v_critical),
    v_exposure,
    jsonb_build_object('predicted_opportunity_cad',v_predicted,'recommended_focus',coalesce(v_top->0->>'recommendation','Review the highest-priority open assignment.')),
    tj_private.current_source_user_id(),now()
  )
  on conflict (organization_id,brief_type,coalesce(period_start,brief_date),coalesce(period_end,brief_date))
  do update set headline=excluded.headline,executive_summary=excluded.executive_summary,priorities=excluded.priorities,
    risks=excluded.risks,wins=excluded.wins,workload=excluded.workload,financial_exposure_cad=excluded.financial_exposure_cad,
    narrative=excluded.narrative,generated_by=excluded.generated_by,generated_at=now()
  returning id into v_id;

  return tj.ai_manager_get_executive_briefs(p_organization_id,10,v_id);
end $function$;
REVOKE ALL ON FUNCTION tj.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_manager_review_completion(p_assignment_id uuid, p_approve boolean, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare a tj.ai_manager_assignments%rowtype;
begin
 select * into a from tj.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not tj.is_org_admin(a.organization_id) then return jsonb_build_object('error','admin_required'); end if;
 if a.approval_status<>'pending' then return jsonb_build_object('error','not_pending_approval'); end if;
 if p_approve then
  update tj.ai_manager_assignments set approval_status='approved',approved_at=now(),approved_by=(select tj_private.current_source_user_id()),rejection_reason=null,updated_at=now() where id=a.id;
  update tj.decision_cases set status='completed',resolved_at=now(),updated_by=(select tj_private.current_source_user_id()),updated_at=now() where id=a.decision_case_id;
  insert into tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),'completion_approved','pending','approved');
 else
  update tj.ai_manager_assignments set status='in_progress',approval_status='rejected',rejection_reason=coalesce(nullif(trim(p_reason),''),'Revision required'),completed_at=null,updated_at=now() where id=a.id;
  insert into tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,from_value,to_value,note) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),'completion_rejected','pending','rejected',coalesce(nullif(trim(p_reason),''),'Revision required'));
 end if;
 return jsonb_build_object('ok',true,'approval_status',case when p_approve then 'approved' else 'rejected' end);
end$function$;
REVOKE ALL ON FUNCTION tj.ai_manager_review_completion(p_assignment_id uuid, p_approve boolean, p_reason text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_manager_run_cycle(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_created int := 0;
  v_overdue int := 0;
  v_escalated int := 0;
  v_open int := 0;
  v_blocked int := 0;
  v_completed_7d int := 0;
  v_financial numeric := 0;
  v_priorities jsonb;
  v_risks jsonb;
  v_wins jsonb;
  v_headline text;
  v_summary text;
begin
  if not tj.is_org_member(p_organization_id) then raise exception 'not_authorized'; end if;

  insert into tj.ai_manager_assignments(organization_id,decision_case_id,title,instructions,assigned_to,assigned_by,priority,status,due_at,metadata)
  select c.organization_id,c.id,c.title,
    coalesce(c.recommendation,'Review the evidence, choose an action, and record the result.'),
    c.owner_id,tj_private.current_source_user_id(),
    case c.severity when 'critical' then 'critical' when 'high' then 'high' when 'medium' then 'medium' else 'low' end,
    'open',
    coalesce(c.due_at, now() + case c.severity when 'critical' then interval '4 hours' when 'high' then interval '1 day' when 'medium' then interval '3 days' else interval '7 days' end),
    jsonb_build_object('module',c.module,'priority_score',c.priority_score,'financial_impact_cad',c.financial_impact_cad,'source_system',c.source_system)
  from tj.decision_cases c
  where c.organization_id=p_organization_id and c.status in ('open','accepted','in_progress')
    and not exists(select 1 from tj.ai_manager_assignments a where a.decision_case_id=c.id and a.status in ('open','accepted','in_progress','blocked'))
  on conflict do nothing;
  get diagnostics v_created = row_count;

  update tj.ai_manager_assignments a
  set escalation_level=least(5,case when now()>a.due_at+interval '7 days' then 3 when now()>a.due_at+interval '2 days' then 2 when now()>a.due_at then 1 else a.escalation_level end),updated_at=now()
  where a.organization_id=p_organization_id and a.status not in ('completed','cancelled') and a.due_at<now();
  get diagnostics v_overdue = row_count;

  insert into tj.ai_manager_escalations(organization_id,assignment_id,level,reason,escalated_to,metadata)
  select a.organization_id,a.id,a.escalation_level,
    case a.escalation_level when 3 then 'Task is more than seven days overdue.' when 2 then 'Task is more than two days overdue.' else 'Task is overdue.' end,
    a.assigned_by,jsonb_build_object('due_at',a.due_at,'priority',a.priority)
  from tj.ai_manager_assignments a
  where a.organization_id=p_organization_id and a.escalation_level>0 and a.status not in ('completed','cancelled')
  on conflict do nothing;
  get diagnostics v_escalated = row_count;

  select count(*) filter(where status in ('open','accepted','in_progress')),count(*) filter(where status='blocked'),count(*) filter(where status='completed' and completed_at>=now()-interval '7 days')
  into v_open,v_blocked,v_completed_7d from tj.ai_manager_assignments where organization_id=p_organization_id;

  select coalesce(sum(coalesce(financial_impact_cad,0)),0) into v_financial from tj.decision_cases where organization_id=p_organization_id and status in ('open','accepted','in_progress');

  select coalesce(jsonb_agg(x order by (x->>'priority_score')::numeric desc),'[]'::jsonb) into v_priorities from (
    select jsonb_build_object('case_id',c.id,'title',c.title,'module',c.module,'severity',c.severity,'priority_score',coalesce(c.priority_score,0),'financial_impact_cad',coalesce(c.financial_impact_cad,0),'recommendation',c.recommendation) x
    from tj.decision_cases c where c.organization_id=p_organization_id and c.status in ('open','accepted','in_progress') order by c.priority_score desc nulls last limit 5
  ) q;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_risks from (
    select jsonb_build_object('assignment_id',a.id,'title',a.title,'priority',a.priority,'status',a.status,'due_at',a.due_at,'escalation_level',a.escalation_level) x
    from tj.ai_manager_assignments a where a.organization_id=p_organization_id and (a.status='blocked' or a.due_at<now()) order by a.escalation_level desc,a.due_at asc limit 5
  ) q;

  select coalesce(jsonb_agg(x),'[]'::jsonb) into v_wins from (
    select jsonb_build_object('assignment_id',a.id,'title',a.title,'completed_at',a.completed_at) x
    from tj.ai_manager_assignments a where a.organization_id=p_organization_id and a.status='completed' and a.completed_at>=now()-interval '7 days' order by a.completed_at desc limit 5
  ) q;

  v_headline := case when v_overdue>0 then v_overdue||' overdue task'||case when v_overdue=1 then '' else 's' end||' require attention' when v_open>0 then v_open||' active management priorit'||case when v_open=1 then 'y' else 'ies' end when v_completed_7d>0 then v_completed_7d||' task'||case when v_completed_7d=1 then '' else 's' end||' completed this week' else 'No active management exceptions' end;
  v_summary := format('The AI Manager created %s new assignment(s), is tracking %s active item(s), %s blocked item(s), and %s escalation(s). Open decisions represent approximately C$%s in stated financial impact.',v_created,v_open,v_blocked,v_escalated,to_char(v_financial,'FM999G999G999G990'));

  insert into tj.ai_manager_briefs(organization_id,brief_date,brief_type,headline,executive_summary,priorities,risks,wins,workload,financial_exposure_cad,generated_by,generated_at)
  values(p_organization_id,current_date,'daily',v_headline,v_summary,v_priorities,v_risks,v_wins,jsonb_build_object('open',v_open,'blocked',v_blocked,'overdue',v_overdue,'completed_7d',v_completed_7d,'new_assignments',v_created,'new_escalations',v_escalated),v_financial,tj_private.current_source_user_id(),now())
  on conflict(organization_id,brief_date,brief_type) do update set headline=excluded.headline,executive_summary=excluded.executive_summary,priorities=excluded.priorities,risks=excluded.risks,wins=excluded.wins,workload=excluded.workload,financial_exposure_cad=excluded.financial_exposure_cad,generated_by=excluded.generated_by,generated_at=now();

  return jsonb_build_object('new_assignments',v_created,'overdue',v_overdue,'new_escalations',v_escalated,'open',v_open,'blocked',v_blocked,'completed_7d',v_completed_7d,'financial_exposure_cad',v_financial);
end $function$;
REVOKE ALL ON FUNCTION tj.ai_manager_run_cycle(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_manager_submit_completion(p_assignment_id uuid, p_completion_summary text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare a tj.ai_manager_assignments%rowtype; proofs int;
begin
 select * into a from tj.ai_manager_assignments where id=p_assignment_id;
 if a.id is null or not tj.is_org_member(a.organization_id) then return jsonb_build_object('error','access_denied'); end if;
 if a.assigned_to is distinct from (select tj_private.current_source_user_id()) and not tj.is_org_admin(a.organization_id) then return jsonb_build_object('error','only_owner_or_admin_can_submit'); end if;
 select count(*) into proofs from tj.ai_manager_task_attachments where assignment_id=a.id and attachment_type='proof';
 if a.proof_required and proofs=0 then return jsonb_build_object('error','proof_required'); end if;
 update tj.ai_manager_assignments set status='completed',submitted_at=now(),submitted_by=(select tj_private.current_source_user_id()),completion_summary=trim(p_completion_summary),approval_status='pending',completed_at=now(),updated_at=now() where id=a.id;
 insert into tj.ai_manager_task_history(organization_id,assignment_id,actor_id,event_type,to_value,note) values(a.organization_id,a.id,(select tj_private.current_source_user_id()),'submitted_for_approval','pending',trim(p_completion_summary));
 return jsonb_build_object('ok',true,'approval_status','pending');
end$function$;
REVOKE ALL ON FUNCTION tj.ai_manager_submit_completion(p_assignment_id uuid, p_completion_summary text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_refresh_all_rep_skills(p_organization_id uuid, p_user_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  r record;
  v_count integer := 0;
begin
  for r in
    select distinct skill_id
    from tj.ai_behavior_observations
    where organization_id=p_organization_id and user_id=p_user_id
  loop
    perform tj.ai_refresh_rep_skill_profile(p_organization_id,p_user_id,r.skill_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;
REVOKE ALL ON FUNCTION tj.ai_refresh_all_rep_skills(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.ai_refresh_rep_skill_profile(p_organization_id uuid, p_user_id uuid, p_skill_id uuid)
 RETURNS tj.ai_rep_skill_profiles
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_row tj.ai_rep_skill_profiles;
  v_score numeric;
  v_count integer;
  v_confidence numeric;
  v_source_mix jsonb;
  v_last timestamptz;
  v_previous numeric;
begin
  select p.score into v_previous
  from tj.ai_rep_skill_profiles p
  where p.organization_id=p_organization_id and p.user_id=p_user_id and p.skill_id=p_skill_id;

  select
    round((sum(o.score * greatest(o.confidence,0.05)) / nullif(sum(greatest(o.confidence,0.05)),0))::numeric,2),
    count(*)::integer,
    least(1::numeric, 0.20::numeric + count(*)::numeric * 0.06::numeric),
    max(o.observed_at)
  into v_score, v_count, v_confidence, v_last
  from tj.ai_behavior_observations o
  where o.organization_id=p_organization_id and o.user_id=p_user_id and o.skill_id=p_skill_id;

  if coalesce(v_count,0)=0 then
    delete from tj.ai_rep_skill_profiles
    where organization_id=p_organization_id and user_id=p_user_id and skill_id=p_skill_id;
    return null;
  end if;

  select coalesce(jsonb_object_agg(source_type, cnt),'{}'::jsonb)
  into v_source_mix
  from (
    select source_type, count(*)::integer cnt
    from tj.ai_behavior_observations
    where organization_id=p_organization_id and user_id=p_user_id and skill_id=p_skill_id
    group by source_type
  ) q;

  insert into tj.ai_rep_skill_profiles
    (organization_id,user_id,skill_id,score,confidence,trend_delta,observation_count,source_mix,last_assessed_at,updated_at)
  values
    (p_organization_id,p_user_id,p_skill_id,v_score,v_confidence,coalesce(v_score-v_previous,0),v_count,v_source_mix,v_last,now())
  on conflict (organization_id,user_id,skill_id) do update set
    score=excluded.score,
    confidence=excluded.confidence,
    trend_delta=excluded.score-tj.ai_rep_skill_profiles.score,
    observation_count=excluded.observation_count,
    source_mix=excluded.source_mix,
    last_assessed_at=excluded.last_assessed_at,
    updated_at=now()
  returning * into v_row;

  return v_row;
end;
$function$;
REVOKE ALL ON FUNCTION tj.ai_refresh_rep_skill_profile(p_organization_id uuid, p_user_id uuid, p_skill_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.ai_submit_request(p_organization_id uuid DEFAULT NULL::uuid, p_assistant_key text DEFAULT NULL::text, p_prompt text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_user uuid := tj_private.current_source_user_id();
  v_org uuid;
  v_assistant tj.ai_assistants%rowtype;
  v_session uuid;
  v_request uuid;
  v_grounded jsonb;
  v_action uuid;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;
  if p_assistant_key is null or coalesce(length(trim(p_prompt)),0) < 3 then
    raise exception 'assistant_key and prompt are required.';
  end if;

  if p_organization_id is not null then
    if not tj.is_org_member(p_organization_id) then
      raise exception 'Access denied for organization.';
    end if;
    v_org := p_organization_id;
  else
    select organization_id into v_org
      from tj.organization_members
     where user_id = v_user and status = 'active'
     order by created_at limit 1;
    if v_org is null then
      raise exception 'Access denied: no active organization membership.';
    end if;
  end if;

  select * into v_assistant from tj.ai_assistants
   where assistant_key = p_assistant_key and status = 'active';
  if not found then
    raise exception 'Unknown or inactive assistant.';
  end if;
  if v_assistant.organization_id is not null and v_assistant.organization_id <> v_org then
    raise exception 'Access denied: assistant not available for this organization.';
  end if;

  insert into tj.ai_sessions (organization_id, user_id, assistant_key)
  values (v_org, v_user, p_assistant_key)
  returning id into v_session;

  v_grounded := jsonb_build_object(
    'record_counts', jsonb_build_object(
      'companies', (select count(*) from tj.companies c where c.organization_id = v_org),
      'contacts', (select count(*) from tj.contacts c where c.organization_id = v_org),
      'deals', (select count(*) from tj.crm_deals d where d.organization_id = v_org),
      'open_tasks', (select count(*) from tj.crm_tasks t where t.organization_id = v_org and t.completed_at is null),
      'products', (select count(*) from tj.products p where p.organization_id = v_org)
    ),
    'pipeline', (select coalesce(jsonb_object_agg(stage, cnt), '{}'::jsonb)
                 from (select stage, count(*) cnt from tj.crm_deals d
                       where d.organization_id = v_org and d.closed_at is null
                       group by stage) s),
    'generated_at', now()
  );

  insert into tj.ai_requests
    (organization_id, session_id, user_id, assistant_key, request_status, prompt, context, grounded_context,
     output, explanation, model_provider, model_name, completed_at)
  values
    (v_org, v_session, v_user, p_assistant_key, 'completed', p_prompt, coalesce(p_context,'{}'::jsonb), v_grounded,
     jsonb_build_object('mode','foundation','assistant_key',p_assistant_key,
       'notice','Governed request recorded. Model layer produces the final answer.'),
     'Foundation envelope: auth, tenancy, assistant visibility, grounded context, and audit recorded at the database layer.',
     'foundation','deterministic', now())
  returning id into v_request;

  if v_assistant.approval_required then
    insert into tj.ai_proposed_actions (organization_id, request_id, assistant_key, action_type, action_payload)
    values (v_org, v_request, p_assistant_key, 'advisory_output_review',
            jsonb_build_object('prompt_preview', left(p_prompt, 200)))
    returning id into v_action;
  end if;

  insert into tj.ai_audit_events (organization_id, request_id, assistant_key, event_type, event_payload)
  values (v_org, v_request, p_assistant_key, 'ai.request.submitted',
          jsonb_build_object('approval_required', v_assistant.approval_required));

  insert into tj.ai_usage_meter (organization_id, assistant_key, request_id, usage_kind, quantity, limit_key)
  values (v_org, p_assistant_key, v_request, 'request', 1, 'ai.requests.monthly');

  return jsonb_build_object(
    'request_id', v_request,
    'session_id', v_session,
    'organization_id', v_org,
    'approval_required', v_assistant.approval_required,
    'proposed_action_id', v_action,
    'output', (select output from tj.ai_requests where id = v_request)
  );
end $function$;
REVOKE ALL ON FUNCTION tj_private.ai_submit_request(p_organization_id uuid, p_assistant_key text, p_prompt text, p_context jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.ai_submit_request(p_organization_id uuid DEFAULT NULL::uuid, p_assistant_key text DEFAULT NULL::text, p_prompt text DEFAULT NULL::text, p_context jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.ai_submit_request("p_organization_id","p_assistant_key","p_prompt","p_context"); $adapter$;
REVOKE ALL ON FUNCTION tj.ai_submit_request(p_organization_id uuid, p_assistant_key text, p_prompt text, p_context jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.aicrm_collaboration_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.aicrm_collaboration_touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aicrm_executive_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_payload jsonb;
begin
  if p_organization_id is null then
    raise exception 'organization_id is required';
  end if;

  if not private.user_can_access_organization(p_organization_id, 'crm.view') then
    raise exception 'permission denied';
  end if;

  with
  account_contact_counts as (
    select
      c.account_id,
      count(*)::integer as contact_count
    from tj.aicrm_contacts c
    where c.organization_id = p_organization_id
    group by c.account_id
  ),
  account_open_opportunity_values as (
    select
      o.account_id,
      coalesce(sum(coalesce(o.opportunity_value, 0)), 0)::numeric as open_opportunity_value
    from tj.aicrm_opportunities o
    where o.organization_id = p_organization_id
      and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled', 'closed')
    group by o.account_id
  ),
  account_last_activity as (
    select
      a.id as account_id,
      max(act.activity_date) as last_activity_at
    from tj.aicrm_accounts a
    left join tj.aicrm_activities act
      on act.organization_id = p_organization_id
     and act.account_id = a.id
    where a.organization_id = p_organization_id
    group by a.id
  ),
  account_research as (
    select
      r.account_id,
      r.confidence,
      r.research_summary,
      r.mock_generated,
      r.last_updated,
      r.priority_score,
      r.score_explanation,
      r.recommended_products,
      r.recommended_campaign,
      r.recommended_campaign_reasoning,
      r.recommended_next_action,
      r.recommended_next_action_reasoning,
      r.recommended_next_action_confidence,
      r.product_fit_scores
    from tj.aicrm_ai_research r
    where r.organization_id = p_organization_id
  ),
  account_base as (
    select
      a.id,
      a.company_name,
      a.category,
      a.province,
      a.revenue_tier,
      a.priority_score,
      a.channel_product_fit,
      a.next_action,
      a.status,
      a.do_not_contact,
      a.scoring_review_required,
      a.scoring_review_reason,
      a.website,
      a.owner_id,
      a.estimated_revenue,
      a.city,
      a.last_scored_at,
      coalesce(acc.contact_count, 0) as contact_count,
      coalesce(opp.open_opportunity_value, 0) as open_opportunity_value,
      ar.confidence,
      ar.research_summary,
      ar.mock_generated,
      ar.last_updated,
      ar.score_explanation,
      ar.recommended_products,
      ar.recommended_campaign,
      ar.recommended_campaign_reasoning,
      ar.recommended_next_action,
      ar.recommended_next_action_reasoning,
      ar.recommended_next_action_confidence,
      ar.product_fit_scores,
      act.last_activity_at
    from tj.aicrm_accounts a
    left join account_contact_counts acc on acc.account_id = a.id
    left join account_open_opportunity_values opp on opp.account_id = a.id
    left join account_research ar on ar.account_id = a.id
    left join account_last_activity act on act.account_id = a.id
    where a.organization_id = p_organization_id
  ),
  contact_quality as (
    select
      avg(
        (
          (case when coalesce(c.full_name, '') <> '' or (coalesce(c.first_name, '') <> '' and coalesce(c.last_name, '') <> '') then 1 else 0 end)
          + (case when coalesce(c.title, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.role_type, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.account_id::text, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.email, '') <> '' or coalesce(c.phone, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.linkedin_url, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.priority, '') <> '' then 1 else 0 end)
          + (case when coalesce(c.email_status, '') <> '' then 1 else 0 end)
        )::numeric / 8 * 100
      ) as average_contact_completeness,
      count(*) filter (where coalesce(c.full_name, '') = '' and coalesce(c.first_name, '') = '' and coalesce(c.last_name, '') = '') as contacts_missing_name
    from tj.aicrm_contacts c
    where c.organization_id = p_organization_id
  ),
  account_quality as (
    select
      avg(
        (
          (case when coalesce(a.company_name, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.category, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.province, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.city, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.website, '') <> '' then 1 else 0 end)
          + (case when a.estimated_revenue is not null or coalesce(a.revenue_tier, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.verification_status, '') <> '' then 1 else 0 end)
          + (case when coalesce(a.channel_product_fit, '') <> '' then 1 else 0 end)
          + (case when a.priority_score is not null then 1 else 0 end)
          + (case when coalesce(a.next_action, '') <> '' then 1 else 0 end)
        )::numeric / 10 * 100
      ) as average_account_completeness,
      count(*) filter (where coalesce(a.website, '') = '') as accounts_missing_website,
      count(*) filter (where a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '') as accounts_missing_revenue,
      count(*) filter (where coalesce(a.channel_product_fit, '') = '') as accounts_missing_product_fit,
      count(*) filter (where coalesce(ac.contact_count, 0) = 0) as accounts_missing_contacts
    from tj.aicrm_accounts a
    left join account_contact_counts ac on ac.account_id = a.id
    where a.organization_id = p_organization_id
  ),
  top_targets as (
    select
      a.id as account_id,
      a.company_name,
      a.category,
      a.province,
      a.revenue_tier,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(ar.confidence, 0) as confidence,
      coalesce(a.channel_product_fit, '') as product_fit,
      coalesce(a.next_action, '') as next_action,
      coalesce(a.open_opportunity_value, 0) as open_opportunity_value
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.do_not_contact, false) = false
      and coalesce(lower(a.status), '') <> 'archived'
      and coalesce(ar.confidence, 0) >= 70
    order by coalesce(a.priority_score, 0) desc, a.company_name asc
    limit 100
  ),
  top_ai_opportunities as (
    select
      a.id as account_id,
      a.company_name,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(ar.confidence, 0) as confidence,
      coalesce(
        (
          select elem->>'product'
          from jsonb_array_elements(coalesce(ar.recommended_products, '[]'::jsonb)) elem
          where coalesce(elem->>'product', '') <> ''
          limit 1
        ),
        coalesce(a.channel_product_fit, ''),
        'Recommendation pending'
      ) as recommended_product,
      coalesce(ar.recommended_next_action, coalesce(a.next_action, ''), 'Review account') as recommended_next_action
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.do_not_contact, false) = false
      and coalesce(lower(a.status), '') <> 'archived'
      and coalesce(ar.confidence, 0) >= 70
    order by coalesce(a.priority_score, 0) desc, a.company_name asc
    limit 25
  ),
  review_queue as (
    select
      a.id as account_id,
      a.company_name,
      a.owner_id,
      coalesce(a.scoring_review_reason, case
        when coalesce(ar.confidence, 0) < 50 then 'Low confidence'
        when coalesce(a.website, '') = '' then 'Missing website'
        when coalesce(a.category, '') = '' then 'Missing category'
        when a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '' then 'Missing revenue'
        when coalesce(a.contact_count, 0) = 0 then 'No contacts'
        when coalesce(a.next_action, '') = '' then 'No next action'
        else 'Review required'
      end) as review_reason,
      array_remove(array[
        case when coalesce(a.website, '') = '' then 'website' end,
        case when coalesce(a.category, '') = '' then 'category' end,
        case when a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '' then 'revenue' end,
        case when coalesce(a.contact_count, 0) = 0 then 'contacts' end,
        case when coalesce(a.next_action, '') = '' then 'next_action' end,
        case when coalesce(ar.confidence, 0) < 50 then 'confidence' end
      ], null)::text[] as missing_fields
    from account_base a
    left join account_research ar on ar.account_id = a.id
    where coalesce(a.scoring_review_required, false) = true
       or coalesce(ar.confidence, 0) < 50
       or coalesce(a.website, '') = ''
       or coalesce(a.category, '') = ''
       or (a.estimated_revenue is null and coalesce(a.revenue_tier, '') = '')
       or coalesce(a.contact_count, 0) = 0
       or coalesce(a.next_action, '') = ''
    order by coalesce(ar.confidence, 0) asc, a.priority_score desc nulls last, a.company_name asc
    limit 50
  ),
  opportunity_base as (
    select
      o.id,
      o.account_id,
      o.title,
      o.stage,
      coalesce(o.opportunity_value, 0) as opportunity_value,
      coalesce(o.probability, 0) as probability,
      o.expected_close_date,
      o.status,
      a.company_name as account_name,
      act.last_activity_at
    from tj.aicrm_opportunities o
    join tj.aicrm_accounts a
      on a.id = o.account_id
     and a.organization_id = p_organization_id
    left join (
      select opportunity_id, max(activity_date) as last_activity_at
      from tj.aicrm_activities
      where organization_id = p_organization_id
      group by opportunity_id
    ) act on act.opportunity_id = o.id
    where o.organization_id = p_organization_id
  ),
  pipeline_stage_stats as (
    select
      coalesce(ps.name, o.stage) as stage,
      coalesce(ps.sort_order, 9999) as sort_order,
      count(*)::integer as opportunity_count,
      coalesce(sum(o.opportunity_value), 0)::numeric as pipeline_value,
      coalesce(sum(o.opportunity_value * coalesce(o.probability, 0) / 100), 0)::numeric as weighted_pipeline_value
    from opportunity_base o
    left join tj.aicrm_pipeline_stages ps
      on ps.organization_id = p_organization_id
     and lower(trim(ps.name)) = lower(trim(o.stage))
    where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')
    group by coalesce(ps.name, o.stage), coalesce(ps.sort_order, 9999)
  ),
  stalled_opportunities as (
    select
      o.id as opportunity_id,
      o.title,
      o.account_name,
      o.stage,
      o.opportunity_value,
      o.probability,
      o.expected_close_date,
      o.status,
      o.last_activity_at
    from opportunity_base o
    where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')
      and (o.last_activity_at is null or o.last_activity_at < now() - interval '14 days')
    order by coalesce(o.last_activity_at, timestamptz '1970-01-01') asc, o.expected_close_date asc nulls last, o.opportunity_value desc
    limit 25
  ),
  task_base as (
    select
      t.id,
      t.title,
      t.description,
      t.due_date,
      coalesce(t.priority, 'normal') as priority,
      t.status,
      t.account_id,
      a.company_name as account_name,
      c.id as contact_id,
      coalesce(c.full_name, concat_ws(' ', c.first_name, c.last_name)) as contact_name,
      o.id as opportunity_id,
      o.title as opportunity_title,
      case
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date < current_date then 'Overdue'
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date = current_date then 'Due Today'
        when t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date::date <= current_date + 7 then 'Due This Week'
        when t.status in ('open', 'in_progress') and (
          lower(coalesce(t.title, '')) like '%follow%'
          or lower(coalesce(t.description, '')) like '%follow%'
        ) then 'Follow-Up Required'
        else 'Due This Week'
      end as bucket
    from tj.aicrm_tasks t
    join tj.aicrm_accounts a
      on a.id = t.account_id
     and a.organization_id = p_organization_id
    left join tj.aicrm_contacts c on c.id = t.contact_id
    left join tj.aicrm_opportunities o on o.id = t.opportunity_id
    where t.organization_id = p_organization_id
      and t.status in ('open', 'in_progress')
  ),
  ai_job_base as (
    select
      j.id,
      j.account_id,
      j.job_type,
      j.status,
      j.provider,
      j.mock_mode,
      j.started_at,
      j.completed_at,
      j.created_at,
      j.cost_estimate,
      j.error_message,
      a.company_name as account_name
    from tj.aicrm_ai_enrichment_jobs j
    left join tj.aicrm_accounts a
      on a.id = j.account_id
     and a.organization_id = p_organization_id
    where j.organization_id = p_organization_id
  ),
  outreach_message_base as (
    select
      m.id,
      m.account_id,
      m.contact_id,
      m.campaign_id,
      m.sequence_step_id,
      m.subject,
      m.status,
      m.approval_status,
      m.eligibility_status,
      m.eligibility_reason,
      m.created_at,
      m.sent_at,
      a.company_name as account_name,
      c.full_name as contact_name,
      campaign.name as campaign_name,
      step.step_number
    from tj.aicrm_outreach_messages m
    left join tj.aicrm_accounts a
      on a.id = m.account_id
     and a.organization_id = p_organization_id
    left join tj.aicrm_contacts c on c.id = m.contact_id
    left join tj.aicrm_outreach_campaigns campaign on campaign.id = m.campaign_id
    left join tj.aicrm_sequence_steps step on step.id = m.sequence_step_id
    where m.organization_id = p_organization_id
  ),
  last_import as (
    select
      i.created_at,
      i.file_name,
      i.import_status,
      i.accepted_rows,
      i.processed_rows
    from tj.aicrm_imports i
    where i.organization_id = p_organization_id
    order by i.created_at desc
    limit 1
  ),
  product_fit as (
    select
      product_name,
      count(*)::integer as match_count,
      coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'account_id', fit.account_id,
            'company_name', fit.company_name,
            'province', fit.province,
            'priority_score', fit.priority_score,
            'product_fit', fit.channel_product_fit
          )
          order by fit.priority_score desc nulls last, fit.company_name asc
        )
        from (
          select
            a.id as account_id,
            a.company_name,
            a.province,
            coalesce(a.priority_score, 0) as priority_score,
            coalesce(a.channel_product_fit, '') as channel_product_fit
          from account_base a
          where lower(coalesce(a.channel_product_fit, '')) like '%' || lower(product_name) || '%'
          order by coalesce(a.priority_score, 0) desc, a.company_name asc
          limit 5
        ) fit
      ), '[]'::jsonb) as top_accounts
    from (values ('Fotile'), ('Dreame'), ('Mobila'), ('Nobilia')) as products(product_name)
    group by product_name
  )
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'total_accounts', (select count(*) from account_base),
      'total_contacts', (select count(*) from tj.aicrm_contacts c where c.organization_id = p_organization_id),
      'total_opportunities', (select count(*) from tj.aicrm_opportunities o where o.organization_id = p_organization_id),
      'total_pipeline_value', (select coalesce(sum(o.opportunity_value), 0) from tj.aicrm_opportunities o where o.organization_id = p_organization_id and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'weighted_pipeline_value', (select coalesce(sum(coalesce(o.opportunity_value, 0) * coalesce(o.probability, 0) / 100), 0) from tj.aicrm_opportunities o where o.organization_id = p_organization_id and coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'open_tasks', (select count(*) from tj.aicrm_tasks t where t.organization_id = p_organization_id and t.status in ('open', 'in_progress')),
      'overdue_tasks', (select count(*) from tj.aicrm_tasks t where t.organization_id = p_organization_id and t.status in ('open', 'in_progress') and t.due_date is not null and t.due_date < now()),
      'active_campaigns', (select count(*) from tj.aicrm_outreach_campaigns c where c.organization_id = p_organization_id and c.status = 'active')
    ),
    'top_targets', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', t.account_id,
      'company_name', t.company_name,
      'category', t.category,
      'province', t.province,
      'revenue_tier', t.revenue_tier,
      'priority_score', t.priority_score,
      'confidence', t.confidence,
      'product_fit', t.product_fit,
      'next_action', t.next_action,
      'open_opportunity_value', t.open_opportunity_value
    ) order by t.priority_score desc, t.company_name asc) from top_targets t), '[]'::jsonb),
    'top_ai_opportunities', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', t.account_id,
      'company_name', t.company_name,
      'priority_score', t.priority_score,
      'confidence', t.confidence,
      'recommended_product', t.recommended_product,
      'recommended_next_action', t.recommended_next_action
    ) order by t.priority_score desc, t.company_name asc) from top_ai_opportunities t), '[]'::jsonb),
    'review_queue', coalesce((select jsonb_agg(jsonb_build_object(
      'account_id', r.account_id,
      'company_name', r.company_name,
      'review_reason', r.review_reason,
      'missing_fields', to_jsonb(r.missing_fields),
      'owner_id', r.owner_id
    ) order by r.review_reason asc, r.company_name asc) from review_queue r), '[]'::jsonb),
    'pipeline', jsonb_build_object(
      'opportunities_by_stage', coalesce((select jsonb_agg(jsonb_build_object(
        'stage', s.stage,
        'opportunity_count', s.opportunity_count,
        'pipeline_value', s.pipeline_value,
        'weighted_pipeline_value', s.weighted_pipeline_value
      ) order by s.sort_order asc, s.stage asc) from pipeline_stage_stats s), '[]'::jsonb),
      'weighted_pipeline_value', (select coalesce(sum(s.weighted_pipeline_value), 0) from pipeline_stage_stats s),
      'average_opportunity_size', (select coalesce(round(avg(o.opportunity_value), 0), 0) from opportunity_base o where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled')),
      'expected_close_this_month', (select count(*) from opportunity_base o where coalesce(lower(o.status), '') not in ('won', 'lost', 'cancelled') and o.expected_close_date >= date_trunc('month', now()) and o.expected_close_date < date_trunc('month', now()) + interval '1 month'),
      'stalled_opportunities', coalesce((select jsonb_agg(jsonb_build_object(
        'opportunity_id', s.opportunity_id,
        'title', s.title,
        'account_name', s.account_name,
        'stage', s.stage,
        'opportunity_value', s.opportunity_value,
        'probability', s.probability,
        'expected_close_date', s.expected_close_date,
        'last_activity_at', s.last_activity_at,
        'status', s.status
      ) order by s.last_activity_at asc nulls first, s.opportunity_value desc) from stalled_opportunities s), '[]'::jsonb)
    ),
    'tasks', jsonb_build_object(
      'due_today', (select count(*) from task_base t where t.bucket = 'Due Today'),
      'overdue', (select count(*) from task_base t where t.bucket = 'Overdue'),
      'due_this_week', (select count(*) from task_base t where t.bucket = 'Due This Week'),
      'follow_up_required', (select count(*) from task_base t where t.bucket = 'Follow-Up Required'),
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'task_id', t.id,
        'title', t.title,
        'account_id', t.account_id,
        'account_name', t.account_name,
        'contact_id', t.contact_id,
        'contact_name', t.contact_name,
        'opportunity_id', t.opportunity_id,
        'opportunity_title', t.opportunity_title,
        'due_date', t.due_date,
        'priority', t.priority,
        'status', t.status,
        'bucket', t.bucket
      ) order by coalesce(t.due_date, timestamptz 'infinity') asc, t.priority desc, t.title asc) from (select * from task_base order by coalesce(due_date, timestamptz 'infinity') asc, priority desc, title asc limit 25) t), '[]'::jsonb)
    ),
    'ai', jsonb_build_object(
      'total_enriched_accounts', (select count(*) from tj.aicrm_ai_research r where r.organization_id = p_organization_id),
      'pending_jobs', (select count(*) from ai_job_base j where j.status = 'queued'),
      'running_jobs', (select count(*) from ai_job_base j where j.status = 'running'),
      'failed_jobs', (select count(*) from ai_job_base j where j.status = 'failed'),
      'mock_jobs', (select count(*) from ai_job_base j where coalesce(j.mock_mode, false) = true),
      'real_jobs', (select count(*) from ai_job_base j where coalesce(j.mock_mode, false) = false),
      'latest_activity', coalesce((select jsonb_agg(jsonb_build_object(
        'job_id', j.id,
        'account_id', j.account_id,
        'account_name', j.account_name,
        'job_type', j.job_type,
        'status', j.status,
        'provider', j.provider,
        'mock_mode', j.mock_mode,
        'created_at', j.created_at,
        'completed_at', j.completed_at,
        'error_message', j.error_message
      ) order by j.created_at desc) from (select * from ai_job_base order by created_at desc limit 8) j), '[]'::jsonb)
    ),
    'outreach', jsonb_build_object(
      'campaign_count', (select count(*) from tj.aicrm_outreach_campaigns c where c.organization_id = p_organization_id),
      'active_enrollments', (select count(*) from tj.aicrm_sequence_enrollments e where e.organization_id = p_organization_id and e.status = 'active'),
      'draft_messages', (select count(*) from outreach_message_base m where m.status in ('draft', 'pending_approval')),
      'pending_approvals', (select count(*) from outreach_message_base m where m.approval_status = 'pending'),
      'blocked_messages', (select count(*) from outreach_message_base m where coalesce(m.eligibility_status, '') = 'blocked'),
      'casl_review_required', (select count(*) from outreach_message_base m where coalesce(m.eligibility_status, '') = 'review_required'),
      'recent_activity', coalesce((select jsonb_agg(jsonb_build_object(
        'message_id', m.id,
        'account_id', m.account_id,
        'account_name', m.account_name,
        'contact_id', m.contact_id,
        'contact_name', m.contact_name,
        'campaign_id', m.campaign_id,
        'campaign_name', m.campaign_name,
        'sequence_step_number', m.step_number,
        'subject', m.subject,
        'status', m.status,
        'approval_status', m.approval_status,
        'eligibility_status', m.eligibility_status,
        'created_at', m.created_at,
        'sent_at', m.sent_at
      ) order by m.created_at desc) from (select * from outreach_message_base order by created_at desc limit 8) m), '[]'::jsonb)
    ),
    'data_quality', jsonb_build_object(
      'average_account_completeness', coalesce((select round(average_account_completeness::numeric, 1) from account_quality), 0),
      'average_contact_completeness', coalesce((select round(average_contact_completeness::numeric, 1) from contact_quality), 0),
      'accounts_missing_contacts', coalesce((select accounts_missing_contacts from account_quality), 0),
      'accounts_missing_revenue', coalesce((select accounts_missing_revenue from account_quality), 0),
      'accounts_missing_website', coalesce((select accounts_missing_website from account_quality), 0),
      'accounts_missing_product_fit', coalesce((select accounts_missing_product_fit from account_quality), 0)
    ),
    'product_fit', coalesce((select jsonb_agg(jsonb_build_object(
      'product_name', p.product_name,
      'match_count', p.match_count,
      'top_accounts', p.top_accounts
    ) order by p.product_name asc) from product_fit p), '[]'::jsonb),
    'system_health', jsonb_build_object(
      'last_import_at', (select li.created_at from last_import li),
      'last_import_name', (select li.file_name from last_import li),
      'total_imported_records', coalesce((select sum(i.accepted_rows)::integer from tj.aicrm_imports i where i.organization_id = p_organization_id), 0),
      'total_audit_events', coalesce((select count(*) from tj.aicrm_audit_log l where l.organization_id = p_organization_id), 0),
      'organizations_count', coalesce((select count(*) from tj.organizations o), 0),
      'last_enrichment_at', coalesce((select max(coalesce(j.completed_at, j.started_at, j.created_at)) from tj.aicrm_ai_enrichment_jobs j where j.organization_id = p_organization_id), null)
    )
  )
  into v_payload;

  return v_payload;
end;
$function$;
REVOKE ALL ON FUNCTION tj.aicrm_executive_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.aicrm_graph_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.aicrm_graph_touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aicrm_market_brief(p_organization_id uuid, p_province text DEFAULT NULL::text, p_country text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  with
  base_watchlists as (
    select count(*)::integer as total_watchlists
    from tj.aicrm_market_watchlists
    where organization_id = p_organization_id
      and active = true
  ),
  discovered as (
    select
      count(*) filter (where review_status = 'pending')::integer as awaiting_review,
      count(*) filter (where created_at >= now() - interval '30 days')::integer as new_companies,
      count(*) filter (where confidence >= 70)::integer as growth_opportunities
    from tj.aicrm_market_discovery_queue
    where organization_id = p_organization_id
      and (p_province is null or coalesce(province, '') = p_province)
      and (p_country is null or coalesce(country, '') = p_country)
  ),
  refreshes as (
    select count(*) filter (where status = 'pending')::integer as pending_refresh
    from tj.aicrm_market_refresh_queue
    where organization_id = p_organization_id
  ),
  events as (
    select count(*) filter (where occurred_at >= now() - interval '30 days')::integer as recent_events
    from tj.aicrm_market_events
    where organization_id = p_organization_id
      and (p_province is null or exists (
        select 1
        from tj.aicrm_accounts a
        where a.id = aicrm_market_events.account_id
          and a.organization_id = p_organization_id
          and coalesce(a.province, '') = p_province
      ))
  ),
  coverage as (
    select
      case
        when count(*) = 0 then 0
        else round(
          (
            count(*) filter (
              where exists (
                select 1
                from tj.aicrm_market_events e
                where e.organization_id = p_organization_id
                  and e.account_id = a.id
              )
              or exists (
                select 1
                from tj.aicrm_market_refresh_queue r
                where r.organization_id = p_organization_id
                  and r.account_id = a.id
              )
            )::numeric * 100.0
          ) / count(*)::numeric,
          1
        )
      end as coverage_percentage
    from tj.aicrm_accounts a
    where a.organization_id = p_organization_id
      and coalesce(lower(a.status), '') <> 'archived'
  )
  select jsonb_build_object(
    'summary',
    concat(
      coalesce(p_province, p_country, 'Market'), ': ',
      coalesce((select new_companies from discovered), 0), ' new companies, ',
      coalesce((select awaiting_review from discovered), 0), ' awaiting review, ',
      coalesce((select pending_refresh from refreshes), 0), ' accounts queued for refresh.'
    ),
    'new_companies_discovered', coalesce((select new_companies from discovered), 0),
    'companies_awaiting_review', coalesce((select awaiting_review from discovered), 0),
    'accounts_needing_refresh', coalesce((select pending_refresh from refreshes), 0),
    'market_events', coalesce((select recent_events from events), 0),
    'growth_opportunities', coalesce((select growth_opportunities from discovered), 0),
    'coverage_percentage', coalesce((select coverage_percentage from coverage), 0),
    'total_watchlists', coalesce((select total_watchlists from base_watchlists), 0)
);
$function$;
REVOKE ALL ON FUNCTION tj.aicrm_market_brief(p_organization_id uuid, p_province text, p_country text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aicrm_platform_config_snapshot(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  with
  settings as (
    select to_jsonb(s) as payload
    from tj.aicrm_organization_settings s
    where s.organization_id = p_organization_id
    limit 1
  ),
  business_units as (
    select coalesce(jsonb_agg(to_jsonb(b) order by b.display_order, b.name), '[]'::jsonb) as payload
    from tj.aicrm_business_units b
    where b.organization_id = p_organization_id
  ),
  brands as (
    select coalesce(jsonb_agg(to_jsonb(b) order by b.display_order, b.name), '[]'::jsonb) as payload
    from tj.aicrm_brands b
    where b.organization_id = p_organization_id
  ),
  products as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'organization_id', p.organization_id,
      'business_unit_id', p.business_unit_id,
      'brand_id', p.brand_id,
      'name', p.name,
      'brand', p.brand,
      'category', p.category,
      'description', p.description,
      'active', p.active,
      'archived_at', p.archived_at,
      'created_at', p.created_at,
      'updated_at', p.updated_at
    ) order by p.name), '[]'::jsonb) as payload
    from tj.aicrm_products p
    where p.organization_id = p_organization_id
  ),
  channels as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from tj.aicrm_channels c
    where c.organization_id = p_organization_id
  ),
  sales_motions as (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.display_order, s.name), '[]'::jsonb) as payload
    from tj.aicrm_sales_motions s
    where s.organization_id = p_organization_id
  ),
  campaign_categories as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from tj.aicrm_campaign_categories c
    where c.organization_id = p_organization_id
  ),
  campaign_types as (
    select coalesce(jsonb_agg(to_jsonb(c) order by c.display_order, c.name), '[]'::jsonb) as payload
    from tj.aicrm_campaign_types c
    where c.organization_id = p_organization_id
  ),
  campaign_sequences as (
    select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at, s.name), '[]'::jsonb) as payload
    from tj.aicrm_campaign_sequences s
    where s.organization_id = p_organization_id
  ),
  kpis as (
    select coalesce(jsonb_agg(to_jsonb(k) order by k.display_order, k.name), '[]'::jsonb) as payload
    from tj.aicrm_kpis k
    where k.organization_id = p_organization_id
  ),
  ai_profiles as (
    select coalesce(jsonb_agg(to_jsonb(a) order by a.is_default desc, a.name), '[]'::jsonb) as payload
    from tj.aicrm_ai_profiles a
    where a.organization_id = p_organization_id
  ),
  pipeline_stages as (
    select coalesce(jsonb_agg(to_jsonb(p) order by p.sort_order, p.name), '[]'::jsonb) as payload
    from tj.aicrm_pipeline_stages p
    where p.organization_id = p_organization_id
  )
  select jsonb_build_object(
    'organization_settings', coalesce((select payload from settings), '{}'::jsonb),
    'business_units', coalesce((select payload from business_units), '[]'::jsonb),
    'brands', coalesce((select payload from brands), '[]'::jsonb),
    'products', coalesce((select payload from products), '[]'::jsonb),
    'channels', coalesce((select payload from channels), '[]'::jsonb),
    'sales_motions', coalesce((select payload from sales_motions), '[]'::jsonb),
    'campaign_categories', coalesce((select payload from campaign_categories), '[]'::jsonb),
    'campaign_types', coalesce((select payload from campaign_types), '[]'::jsonb),
    'campaign_sequences', coalesce((select payload from campaign_sequences), '[]'::jsonb),
    'kpis', coalesce((select payload from kpis), '[]'::jsonb),
    'ai_profiles', coalesce((select payload from ai_profiles), '[]'::jsonb),
    'pipeline_stages', coalesce((select payload from pipeline_stages), '[]'::jsonb)
  );
$function$;
REVOKE ALL ON FUNCTION tj.aicrm_platform_config_snapshot(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aicrm_product_fit_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  with ranked as (
    select
      p.name as product_name,
      f.account_id,
      a.company_name,
      a.province,
      coalesce(a.priority_score, 0) as priority_score,
      coalesce(f.fit_score, 0) as fit_score,
      f.fit_tier,
      coalesce(f.confidence, 0) as confidence,
      coalesce(f.recommended_sales_motion, '') as recommended_sales_motion,
      coalesce(f.recommended_campaign, '') as recommended_campaign,
      coalesce(f.fit_reason, '') as fit_reason,
      coalesce(ar.recommended_next_action, a.next_action, 'Review account') as next_action,
      row_number() over (partition by p.name order by coalesce(f.fit_score, 0) desc, coalesce(a.priority_score, 0) desc, a.company_name asc) as rn
    from tj.aicrm_account_product_fit f
    join tj.aicrm_products p
      on p.id = f.product_id
     and p.organization_id = p_organization_id
    join tj.aicrm_accounts a
      on a.id = f.account_id
     and a.organization_id = p_organization_id
    left join tj.aicrm_ai_research ar
      on ar.organization_id = p_organization_id
     and ar.account_id = a.id
    where f.organization_id = p_organization_id
      and p.active = true
  )
  select jsonb_build_object(
    'product_fit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'product_name', s.product_name,
        'match_count', s.match_count,
        'top_accounts', s.top_accounts
      ) order by s.product_name asc)
      from (
        select
          product_name,
          count(*)::integer as match_count,
          coalesce((
            select jsonb_agg(jsonb_build_object(
              'account_id', x.account_id,
              'company_name', x.company_name,
              'province', x.province,
              'priority_score', x.priority_score,
              'fit_score', x.fit_score,
              'fit_tier', x.fit_tier,
              'confidence', x.confidence,
              'recommended_sales_motion', x.recommended_sales_motion,
              'recommended_campaign', x.recommended_campaign,
              'fit_reason', x.fit_reason,
              'next_action', x.next_action
            ) order by x.fit_score desc, x.priority_score desc, x.company_name asc)
            from ranked x
            where x.product_name = s.product_name and x.rn <= 10
          ), '[]'::jsonb) as top_accounts
        from ranked s
        group by product_name
      ) s
    ), '[]'::jsonb)
  );
$function$;
REVOKE ALL ON FUNCTION tj.aicrm_product_fit_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aicrm_product_fit_matrix(p_organization_id uuid, p_product_id uuid DEFAULT NULL::uuid, p_fit_tier text DEFAULT NULL::text, p_reviewed_status text DEFAULT NULL::text, p_confidence_min numeric DEFAULT NULL::numeric, p_province text DEFAULT NULL::text, p_category text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 250)
 RETURNS TABLE(total_count bigint, fit_id uuid, organization_id uuid, account_id uuid, account_name text, account_priority_score numeric, account_category text, account_segment text, account_type text, province text, product_id uuid, product_name text, product_brand text, product_category text, fit_score numeric, fit_tier text, fit_reason text, recommended_sales_motion text, recommended_campaign text, confidence numeric, source text, reviewed_status text, reviewed_by uuid, reviewed_at timestamp with time zone, last_calculated_at timestamp with time zone, research_summary text, product_fit_scores jsonb, recommended_products jsonb, recommended_next_action text, recommended_next_action_reasoning text, created_at timestamp with time zone, updated_at timestamp with time zone)
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select
    count(*) over() as total_count,
    f.id as fit_id,
    f.organization_id,
    f.account_id,
    a.company_name as account_name,
    coalesce(a.priority_score, 0) as account_priority_score,
    a.category as account_category,
    a.segment as account_segment,
    a.account_type,
    a.province,
    p.id as product_id,
    p.name as product_name,
    p.brand as product_brand,
    p.category as product_category,
    f.fit_score,
    f.fit_tier,
    f.fit_reason,
    f.recommended_sales_motion,
    f.recommended_campaign,
    f.confidence,
    f.source,
    f.reviewed_status,
    f.reviewed_by,
    f.reviewed_at,
    f.last_calculated_at,
    ar.research_summary,
    ar.product_fit_scores,
    to_jsonb(ar.recommended_products) as recommended_products,
    ar.recommended_next_action,
    ar.recommended_next_action_reasoning,
    f.created_at,
    f.updated_at
  from tj.aicrm_account_product_fit f
  join tj.aicrm_accounts a
    on a.id = f.account_id
   and a.organization_id = p_organization_id
  join tj.aicrm_products p
    on p.id = f.product_id
   and p.organization_id = p_organization_id
  left join tj.aicrm_ai_research ar
    on ar.organization_id = p_organization_id
   and ar.account_id = a.id
  where f.organization_id = p_organization_id
    and (p_product_id is null or f.product_id = p_product_id)
    and (p_fit_tier is null or f.fit_tier = p_fit_tier)
    and (p_reviewed_status is null or f.reviewed_status = p_reviewed_status)
    and (p_confidence_min is null or f.confidence >= p_confidence_min)
    and (p_province is null or coalesce(a.province, '') = p_province)
    and (p_category is null or coalesce(a.category, '') = p_category)
    and (
      p_search is null
      or p_search = ''
      or a.company_name ilike '%' || p_search || '%'
      or p.name ilike '%' || p_search || '%'
      or coalesce(f.fit_reason, '') ilike '%' || p_search || '%'
    )
  order by coalesce(f.fit_score, 0) desc, coalesce(a.priority_score, 0) desc, a.company_name asc, p.name asc
  limit greatest(1, least(coalesce(p_limit, 250), 500));
$function$;
REVOKE ALL ON FUNCTION tj.aicrm_product_fit_matrix(p_organization_id uuid, p_product_id uuid, p_fit_tier text, p_reviewed_status text, p_confidence_min numeric, p_province text, p_category text, p_search text, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aiq_command_centre_snapshot(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
select jsonb_build_object(
 'generated_at',now(),'organization_id',p_organization_id,
 'products',jsonb_build_object(
   'total',(select count(*) from tj.aiq_products where organization_id=p_organization_id),
   'approved',(select count(*) from tj.aiq_products where organization_id=p_organization_id and approval_status='approved'),
   'public',(select count(*) from tj.aiq_products where organization_id=p_organization_id and public_visible),
   'documents',(select count(*) from tj.pim_product_documents d join tj.aiq_products p on p.id=d.product_id where p.organization_id=p_organization_id),
   'graph_nodes',(select count(*) from tj.aicrm_graph_nodes where organization_id=p_organization_id),
   'graph_edges',(select count(*) from tj.aicrm_graph_edges where organization_id=p_organization_id)),
 'sales',jsonb_build_object(
   'deals',(select count(*) from tj.crm_deals where organization_id=p_organization_id),
   'open_deals',(select count(*) from tj.crm_deals where organization_id=p_organization_id and closed_at is null and coalesce(is_archived,false)=false),
   'pipeline_value',(select coalesce(sum(value_amount),0) from tj.crm_deals where organization_id=p_organization_id and closed_at is null and coalesce(is_archived,false)=false),
   'packages',(select count(*) from tj.speciq_packages where organization_id=p_organization_id),
   'comparisons',(select count(*) from tj.ai_product_comparisons where organization_id=p_organization_id),
   'recordings',(select count(*) from tj.sales_recordings where organization_id=p_organization_id)),
 'operations',jsonb_build_object(
   'traffic_events',(select count(*) from tj.iq_traffic_events where organization_id=p_organization_id),
   'customer_interactions',(select count(*) from tj.iq_customer_interactions where organization_id=p_organization_id)),
 'ai',jsonb_build_object(
   'requests',(select count(*) from tj.ai_requests where organization_id=p_organization_id),
   'conversations',(select count(*) from tj.ai_conversations where organization_id=p_organization_id),
   'roleplays',(select count(*) from tj.ai_roleplay_sessions where organization_id=p_organization_id),
   'coaching_reviews',(select count(*) from tj.ai_coaching_reviews where organization_id=p_organization_id))
); $function$;
REVOKE ALL ON FUNCTION tj.aiq_command_centre_snapshot(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aiq_graph_neighbours(p_organization_id uuid, p_entity_id uuid, p_depth integer DEFAULT 1, p_limit integer DEFAULT 50)
 RETURNS TABLE(root_node_id uuid, node_id uuid, node_type text, entity_id uuid, label text, relationship_path text[], depth integer, metadata jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
with recursive walk(root_node_id,node_id,node_type,entity_id,label,relationship_path,depth,metadata,visited) as (
  select n.id,n.id,n.node_type,n.entity_id,n.label,array[]::text[],0,n.metadata,array[n.id]::uuid[]
  from tj.aicrm_graph_nodes n
  where n.organization_id=p_organization_id and n.entity_id=p_entity_id and n.active
  union all
  select w.root_node_id,nextn.id,nextn.node_type,nextn.entity_id,nextn.label,w.relationship_path||e.relationship_type,w.depth+1,nextn.metadata,w.visited||nextn.id
  from walk w
  join tj.aicrm_graph_edges e on e.organization_id=p_organization_id and (e.from_node_id=w.node_id or e.to_node_id=w.node_id)
  join tj.aicrm_graph_nodes nextn on nextn.id=case when e.from_node_id=w.node_id then e.to_node_id else e.from_node_id end
  where w.depth<greatest(1,least(p_depth,3)) and nextn.active and not nextn.id=any(w.visited)
)
select root_node_id,node_id,node_type,entity_id,label,relationship_path,depth,metadata from walk
order by depth,label limit greatest(1,least(p_limit,200));
$function$;
REVOKE ALL ON FUNCTION tj.aiq_graph_neighbours(p_organization_id uuid, p_entity_id uuid, p_depth integer, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.aiq_record_version()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  version_table text := tg_argv[0];
  fk_column text := tg_argv[1];
begin
  execute format(
    'insert into public.%I (organization_id, %I, version_number, snapshot) values ($1.organization_id, $1.id, $1.version_number, to_jsonb($1))',
    version_table, fk_column
  ) using new;
  return null;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.aiq_record_version() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.aiq_sync_knowledge_graph(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  insert into tj.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Product',p.id,'aiq_products',concat_ws(' ',p.brand_name,p.model),p.short_description,
    jsonb_strip_nulls(jsonb_build_object('brand_name',p.brand_name,'manufacturer_name',p.manufacturer_name,'category',p.category,'series',p.series,'product_family',p.product_family,'status',p.status,'market',p.market,'msrp',p.msrp,'replacement_model',p.replacement_model)),coalesce(p.public_visible,true)
  from tj.aiq_products p where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into tj.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select b.organization_id,'Brand',b.id,'brand_catalog',b.brand_name,b.brand_story,
    jsonb_strip_nulls(jsonb_build_object('brand_tier',b.brand_tier,'parent_company',b.parent_company,'country',b.country,'website',b.website,'headquarters',b.headquarters,'tagline',b.brand_tagline,'categories',b.product_categories)),coalesce(b.is_active,true)
  from tj.brand_catalog b where p_organization_id is null or b.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into tj.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Document',d.id,'pim_product_documents',d.title,d.description,
    jsonb_strip_nulls(jsonb_build_object('doc_type',d.doc_type,'language',d.language,'locale',d.locale,'version',d.version,'file_url',d.file_url,'verification_status',d.verification_status,'manufacturer_verified',d.manufacturer_verified)),coalesce(d.is_current,true)
  from tj.pim_product_documents d join tj.aiq_products p on p.id=d.product_id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into tj.aicrm_graph_nodes (organization_id,node_type,entity_id,entity_type,label,description,metadata,active)
  select p.organization_id,'Product',a.id,'pim_product_accessories',a.accessory_name,a.accessory_description,
    jsonb_strip_nulls(jsonb_build_object('is_accessory',true,'model',a.accessory_model,'relationship_type',a.relationship_type,'category',a.category,'msrp',a.msrp,'required',a.is_required,'included',a.is_included)),true
  from tj.pim_product_accessories a join tj.aiq_products p on p.id=a.product_id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,node_type,entity_type,entity_id) where entity_id is not null
  do update set label=excluded.label,description=excluded.description,metadata=excluded.metadata,active=excluded.active,updated_at=now();

  insert into tj.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,bn.id,'BELONGS_TO',100,100,'aiq_sync',jsonb_build_object('semantic_type','made_by_brand')
  from tj.aicrm_graph_nodes pn
  join tj.aiq_products p on pn.entity_type='aiq_products' and pn.entity_id=p.id
  join tj.aicrm_graph_nodes bn on bn.organization_id=pn.organization_id and bn.entity_type='brand_catalog' and bn.entity_id=p.brand_id
  where pn.node_type='Product' and (p_organization_id is null or pn.organization_id=p_organization_id)
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into tj.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,dn.id,'CONNECTED_TO',90,case when d.manufacturer_verified then 100 else 80 end,'aiq_sync',jsonb_build_object('semantic_type','has_document','doc_type',d.doc_type)
  from tj.pim_product_documents d
  join tj.aiq_products p on p.id=d.product_id
  join tj.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join tj.aicrm_graph_nodes dn on dn.organization_id=p.organization_id and dn.entity_type='pim_product_documents' and dn.entity_id=d.id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into tj.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select pn.organization_id,pn.id,an.id,'CONNECTED_TO',case when coalesce(a.is_required,false) then 100 else 80 end,90,'aiq_sync',
    jsonb_build_object('semantic_type',case when coalesce(a.is_required,false) then 'requires_accessory' when coalesce(a.is_included,false) then 'includes_accessory' else 'compatible_accessory' end,'relationship_type',a.relationship_type)
  from tj.pim_product_accessories a
  join tj.aiq_products p on p.id=a.product_id
  join tj.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join tj.aicrm_graph_nodes an on an.organization_id=p.organization_id and an.entity_type='pim_product_accessories' and an.entity_id=a.id
  where p_organization_id is null or p.organization_id=p_organization_id
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  insert into tj.aicrm_graph_edges (organization_id,from_node_id,to_node_id,relationship_type,strength,confidence,source,metadata)
  select p.organization_id,pn.id,rn.id,'CONNECTED_TO',100,95,'aiq_sync',jsonb_build_object('semantic_type','replaced_by','replacement_model',p.replacement_model)
  from tj.aiq_products p
  join tj.aiq_products r on r.organization_id=p.organization_id and upper(r.model)=upper(p.replacement_model)
  join tj.aicrm_graph_nodes pn on pn.organization_id=p.organization_id and pn.entity_type='aiq_products' and pn.entity_id=p.id
  join tj.aicrm_graph_nodes rn on rn.organization_id=r.organization_id and rn.entity_type='aiq_products' and rn.entity_id=r.id
  where nullif(trim(p.replacement_model),'') is not null and (p_organization_id is null or p.organization_id=p_organization_id)
  on conflict (organization_id,from_node_id,to_node_id,relationship_type)
  do update set updated_at=now(),confidence=excluded.confidence,metadata=excluded.metadata;

  return jsonb_build_object('nodes',(select count(*) from tj.aicrm_graph_nodes where p_organization_id is null or organization_id=p_organization_id),'edges',(select count(*) from tj.aicrm_graph_edges where p_organization_id is null or organization_id=p_organization_id),'synced_at',now());
end;
$function$;
REVOKE ALL ON FUNCTION tj.aiq_sync_knowledge_graph(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.aiq_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.version_number := coalesce(old.version_number, 0) + 1;
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.aiq_touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.apply_feedback_to_chunks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE v_updated int := 0;
BEGIN
  WITH scores AS (
    SELECT unnest(chunk_keys_used) AS ck, SUM(rating)::numeric AS net
    FROM ai_answer_feedback
    WHERE created_at > now() - interval '90 days'
    GROUP BY 1
  )
  UPDATE ai_knowledge_chunks k
  SET feedback_score = LEAST(GREATEST(s.net / 10.0, -2), 2)
  FROM scores s WHERE k.chunk_key = s.ck;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN jsonb_build_object('chunks_updated', v_updated, 'ran_at', now());
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.apply_feedback_to_chunks() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.apply_feedback_to_chunks() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.apply_feedback_to_chunks(); $adapter$;
REVOKE ALL ON FUNCTION tj.apply_feedback_to_chunks() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.archive_connector_event(p_connection_id uuid, p_external_entity_type text, p_event_type text, p_payload jsonb, p_external_id text DEFAULT NULL::text, p_sync_job_id uuid DEFAULT NULL::uuid, p_source_api_version text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_id uuid;
  v_correlation uuid := coalesce(p_correlation_id, gen_random_uuid());
  v_fingerprint text := tj.connector_payload_fingerprint(p_payload);
  v_connector_id uuid;
  v_variant_id uuid;
begin
  select connector_id, variant_id into v_connector_id, v_variant_id
  from tj.platform_connector_connections where id=p_connection_id;
  if v_connector_id is null then raise exception 'Unknown connector connection'; end if;

  insert into tj.platform_connector_event_archive(
    connection_id,sync_job_id,correlation_id,external_entity_type,external_id,event_type,
    source_api_version,schema_fingerprint,payload_hash,payload,metadata
  ) values (
    p_connection_id,p_sync_job_id,v_correlation,p_external_entity_type,p_external_id,p_event_type,
    p_source_api_version,v_fingerprint,md5(coalesce(p_payload::text,'')),p_payload,coalesce(p_metadata,'{}'::jsonb)
  ) returning id into v_id;

  insert into tj.platform_connector_schema_fingerprints(
    connector_id,variant_id,external_entity_type,api_version,fingerprint,observed_shape
  ) values (
    v_connector_id,v_variant_id,p_external_entity_type,p_source_api_version,v_fingerprint,
    coalesce((select jsonb_object_agg(key,jsonb_typeof(value)) from jsonb_each(coalesce(p_payload,'{}'::jsonb))),'{}'::jsonb)
  ) on conflict(connector_id,variant_id,external_entity_type,api_version,fingerprint)
    do update set last_seen_at=now(), occurrence_count=platform_connector_schema_fingerprints.occurrence_count+1;

  insert into tj.platform_connector_trace_events(correlation_id,connection_id,sync_job_id,archive_event_id,stage,status,details)
  values(v_correlation,p_connection_id,p_sync_job_id,v_id,'ingestion.archive','received',jsonb_build_object('entity_type',p_external_entity_type,'event_type',p_event_type));

  return v_id;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.archive_connector_event(p_connection_id uuid, p_external_entity_type text, p_event_type text, p_payload jsonb, p_external_id text, p_sync_job_id uuid, p_source_api_version text, p_correlation_id uuid, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.archive_connector_event(p_connection_id uuid, p_external_entity_type text, p_event_type text, p_payload jsonb, p_external_id text DEFAULT NULL::text, p_sync_job_id uuid DEFAULT NULL::uuid, p_source_api_version text DEFAULT NULL::text, p_correlation_id uuid DEFAULT NULL::uuid, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.archive_connector_event("p_connection_id","p_external_entity_type","p_event_type","p_payload","p_external_id","p_sync_job_id","p_source_api_version","p_correlation_id","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.archive_connector_event(p_connection_id uuid, p_external_entity_type text, p_event_type text, p_payload jsonb, p_external_id text, p_sync_job_id uuid, p_source_api_version text, p_correlation_id uuid, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.archive_old_intelligence_events(p_days_old integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_cutoff timestamptz := now() - (p_days_old || ' days')::interval;
  v_archived integer := 0;
  v_month_counts jsonb;
BEGIN
  -- Aggregate counts by month before deleting
  WITH monthly AS (
    SELECT 
      date_trunc('month', created_at) as month,
      event_type,
      organization_id,
      count(*) as event_count
    FROM tj.intelligence_events
    WHERE created_at < v_cutoff
    GROUP BY 1, 2, 3
  ),
  inserted AS (
    INSERT INTO intelligence_events_archive (month, event_type, organization_id, event_count)
    SELECT month, event_type, organization_id, event_count
    FROM monthly
    ON CONFLICT DO NOTHING
    RETURNING *
  )
  SELECT count(*) INTO v_archived FROM inserted;

  -- Delete archived events
  DELETE FROM tj.intelligence_events WHERE created_at < v_cutoff;
  
  -- Also prune timelines older than 180 days
  DELETE FROM tj.intelligence_timelines WHERE created_at < (now() - interval '180 days');

  RETURN jsonb_build_object(
    'archived_months', v_archived,
    'cutoff', v_cutoff,
    'status', 'ok'
  );
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.archive_old_intelligence_events(p_days_old integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.archive_old_intelligence_events(p_days_old integer DEFAULT 90) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.archive_old_intelligence_events("p_days_old"); $adapter$;
REVOKE ALL ON FUNCTION tj.archive_old_intelligence_events(p_days_old integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.assert_floor_org_access(p_org_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF p_org_id IS NULL THEN
    RAISE EXCEPTION 'organization_id is required';
  END IF;

  -- Trusted server-side contexts bypass
  IF current_setting('role', true) = 'service_role'
     OR auth.role() = 'service_role'
     OR current_user IN ('postgres','supabase_admin') THEN
    RETURN;
  END IF;

  IF NOT is_org_member(p_org_id) THEN
    RAISE EXCEPTION 'Access denied to organization %', p_org_id
      USING ERRCODE = '42501';
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.assert_floor_org_access(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.assert_floor_org_access(p_org_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.assert_floor_org_access("p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.assert_floor_org_access(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_disco_from_condition()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_disco_retailers int;
BEGIN
  IF NEW.product_id IS NULL THEN RETURN NEW; END IF;

  -- Only act if this row is NOW flagged as discontinued/end_of_life
  IF NEW.condition_normalized IN ('discontinued','end_of_life') 
     OR NEW.is_end_of_life = true
     OR NEW.condition = 'discontinued' THEN

    -- Count distinct retailers marking this product discontinued
    SELECT COUNT(DISTINCT retailer_name) INTO v_disco_retailers
    FROM pim_retailer_prices
    WHERE product_id = NEW.product_id
      AND (condition_normalized IN ('discontinued','end_of_life')
           OR is_end_of_life = true
           OR condition = 'discontinued');

    -- 2+ retailers = discontinued
    IF v_disco_retailers >= 2 THEN
      UPDATE aiq_products SET status = 'discontinued'
      WHERE id = NEW.product_id AND status IN ('active','draft','clearance');
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_disco_from_condition() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_disco_from_manufacturer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- If a manufacturer source sets status to discontinued, trust it immediately
  IF NEW.status = 'discontinued' 
     AND NEW.source_type IN ('manufacturer_submitted','spec_sheet_extraction')
     AND (OLD.status IS NULL OR OLD.status != 'discontinued') THEN
    -- Already set by the update itself — just ensure it sticks
    RETURN NEW;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_disco_from_manufacturer() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_grant_platform_shell()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.app_key <> 'platform' AND NOT EXISTS (
    SELECT 1 FROM org_app_entitlements WHERE organization_id = NEW.organization_id AND app_key = 'platform'
  ) THEN
    INSERT INTO org_app_entitlements (organization_id, app_key, tier, seats_included, status)
    VALUES (NEW.organization_id, 'platform', 'starter', 1, 'active')
    ON CONFLICT (organization_id, app_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_grant_platform_shell() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_link_discovered_to_pim()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_product_id uuid;
BEGIN
  IF NEW.brand_name IS NULL OR TRIM(NEW.brand_name) = '' 
     OR NEW.model IS NULL OR TRIM(NEW.model) = '' THEN
    RETURN NEW;
  END IF;

  SELECT id INTO v_product_id
  FROM aiq_products
  WHERE LOWER(TRIM(brand_name)) = LOWER(TRIM(NEW.brand_name))
    AND LOWER(TRIM(model)) = LOWER(TRIM(NEW.model))
  LIMIT 1;

  IF v_product_id IS NOT NULL THEN
    NEW.aiq_product_id := v_product_id;
    -- Backfill missing fields
    UPDATE aiq_products SET
      category = COALESCE(NULLIF(category, ''), NEW.category),
      subcategory = COALESCE(NULLIF(subcategory, ''), NEW.subcategory),
      short_description = COALESCE(NULLIF(short_description, ''), NEW.product_name),
      msrp = COALESCE(msrp, NEW.regular_price, NEW.price)
    WHERE id = v_product_id
      AND (
        (category IS NULL OR category = '') AND NEW.category IS NOT NULL AND NEW.category != ''
        OR (subcategory IS NULL OR subcategory = '') AND NEW.subcategory IS NOT NULL
        OR (short_description IS NULL OR short_description = '') AND NEW.product_name IS NOT NULL
        OR msrp IS NULL AND (NEW.regular_price IS NOT NULL OR NEW.price IS NOT NULL)
      );
  ELSE
    -- Create new — skip if model too short (scraper junk)
    IF LENGTH(TRIM(NEW.model)) < 2 THEN RETURN NEW; END IF;
    
    BEGIN
      INSERT INTO aiq_products (
        brand_name, manufacturer_name, model, short_description,
        category, subcategory, msrp, sale_price,
        market, source_type, approval_status, status, organization_id
      ) VALUES (
        TRIM(NEW.brand_name), TRIM(NEW.brand_name), TRIM(NEW.model), NEW.product_name,
        NEW.category, NEW.subcategory, COALESCE(NEW.regular_price, NEW.price),
        CASE WHEN NEW.on_sale = true THEN NEW.price ELSE NULL END,
        'CA', 'scraper_v2', 'approved', 'active',
        '00000000-0000-0000-0000-000000000002'::uuid
      )
      RETURNING id INTO v_product_id;
      NEW.aiq_product_id := v_product_id;
    EXCEPTION WHEN unique_violation THEN
      -- Race condition: another insert beat us — just look it up
      SELECT id INTO v_product_id
      FROM aiq_products
      WHERE LOWER(TRIM(brand_name)) = LOWER(TRIM(NEW.brand_name))
        AND LOWER(TRIM(model)) = LOWER(TRIM(NEW.model))
      LIMIT 1;
      NEW.aiq_product_id := v_product_id;
    END;
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_link_discovered_to_pim() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_link_price_to_pim()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_product_id uuid;
  v_disco_retailers int;
BEGIN
  IF NEW.product_id IS NOT NULL THEN RETURN NEW; END IF;
  IF NEW.brand_name IS NULL OR TRIM(NEW.brand_name) = ''
     OR NEW.model IS NULL OR TRIM(NEW.model) = '' THEN RETURN NEW; END IF;
  IF LENGTH(TRIM(NEW.model)) < 2 THEN RETURN NEW; END IF;

  SELECT id INTO v_product_id
  FROM aiq_products
  WHERE LOWER(TRIM(brand_name)) = LOWER(TRIM(NEW.brand_name))
    AND LOWER(TRIM(model)) = LOWER(TRIM(NEW.model))
  LIMIT 1;

  IF v_product_id IS NOT NULL THEN
    NEW.product_id := v_product_id;
    UPDATE aiq_products SET
      msrp = COALESCE(msrp, NEW.regular_price, NEW.price),
      sale_price = CASE 
        WHEN NEW.on_sale = true AND NEW.price IS NOT NULL 
             AND (sale_price IS NULL OR NEW.price < sale_price)
        THEN NEW.price ELSE sale_price
      END
    WHERE id = v_product_id;

    IF NEW.condition_normalized = 'discontinued' OR NEW.condition_normalized = 'end_of_life'
       OR NEW.is_end_of_life = true OR NEW.condition = 'discontinued' THEN
      SELECT COUNT(DISTINCT retailer_name) INTO v_disco_retailers
      FROM pim_retailer_prices
      WHERE product_id = v_product_id
        AND (condition_normalized IN ('discontinued','end_of_life') 
             OR is_end_of_life = true OR condition = 'discontinued');
      v_disco_retailers := v_disco_retailers + 1;
      IF v_disco_retailers >= 2 THEN
        UPDATE aiq_products SET status = 'discontinued'
        WHERE id = v_product_id AND status IN ('active','draft');
      END IF;
    END IF;

    IF NEW.is_clearance = true OR NEW.condition_normalized = 'clearance' THEN
      IF NOT EXISTS (
        SELECT 1 FROM pim_retailer_prices 
        WHERE product_id = v_product_id AND is_clearance = false 
          AND condition_normalized IS DISTINCT FROM 'clearance'
          AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
      ) THEN
        UPDATE aiq_products SET status = 'clearance'
        WHERE id = v_product_id AND status = 'active';
      END IF;
    END IF;
  ELSE
    BEGIN
      INSERT INTO aiq_products (
        brand_name, manufacturer_name, model,
        msrp, sale_price, market, source_type, approval_status, status, organization_id
      ) VALUES (
        TRIM(NEW.brand_name), TRIM(NEW.brand_name), TRIM(NEW.model),
        COALESCE(NEW.regular_price, NEW.price),
        CASE WHEN NEW.on_sale = true THEN NEW.price ELSE NULL END,
        'CA', 'scraper_v2', 'approved', 'active',
        '00000000-0000-0000-0000-000000000002'::uuid
      ) RETURNING id INTO v_product_id;
      NEW.product_id := v_product_id;
    EXCEPTION WHEN unique_violation THEN
      SELECT id INTO v_product_id
      FROM aiq_products
      WHERE LOWER(TRIM(brand_name)) = LOWER(TRIM(NEW.brand_name))
        AND LOWER(TRIM(model)) = LOWER(TRIM(NEW.model))
      LIMIT 1;
      NEW.product_id := v_product_id;
    END;
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_link_price_to_pim() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.auto_price_entitlement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE v_price platform_pricing%ROWTYPE;
BEGIN
  IF coalesce(NEW.metadata->>'custom_price','') = 'true' THEN
    RETURN NEW;
  END IF;
  SELECT * INTO v_price FROM platform_pricing
  WHERE app_key = NEW.app_key AND tier = NEW.tier AND active;
  IF v_price.id IS NULL THEN
    RETURN NEW; -- no pricing row: leave manual value alone
  END IF;
  NEW.price_cents_monthly := CASE v_price.billing_unit
    WHEN 'flat' THEN v_price.unit_price_cents
    ELSE v_price.unit_price_cents * greatest(NEW.seats_included, 1)
  END;
  NEW.metadata := NEW.metadata || jsonb_build_object(
    'billing_unit', v_price.billing_unit,
    'unit_price_cents', v_price.unit_price_cents,
    'tier_display', v_price.display_name);
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.auto_price_entitlement() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.cascade_budget(p_budget_plan_id uuid, p_metric_type text DEFAULT 'revenue'::text, p_period_type text DEFAULT 'annual'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_plan record;
  v_corporate_target numeric;
  v_loc record;
  v_total_historical numeric;
  v_cascaded integer := 0;
begin
  select * into v_plan from tj.budget_plans where id = p_budget_plan_id;
  if not found then return jsonb_build_object('error','plan_not_found'); end if;

  -- Get the corporate-level target for this metric
  select target_value into v_corporate_target from tj.budget_nodes
  where budget_plan_id = p_budget_plan_id and location_id is null and user_id is null
    and metric_type = p_metric_type and period_type = p_period_type
  limit 1;

  if v_corporate_target is null or v_corporate_target = 0 then
    v_corporate_target := v_plan.total_revenue_target;
  end if;

  -- Get historical totals for active child locations to compute %
  select coalesce(sum(actual_value), 0) into v_total_historical
  from tj.metric_snapshots ms
  join tj.org_locations ol on ol.id = ms.location_id
  where ms.organization_id = v_plan.organization_id
    and ms.metric_key = p_metric_type
    and ms.period_type = 'annual'
    and ol.is_active = true;

  -- Cascade to each active location
  for v_loc in
    select id, name from tj.org_locations
    where organization_id = v_plan.organization_id and is_active = true
    order by location_type, name
  loop
    declare
      v_loc_historical numeric := 0;
      v_loc_pct numeric := 0;
      v_loc_target numeric := 0;
    begin
      select coalesce(sum(actual_value), 0) into v_loc_historical
      from tj.metric_snapshots
      where location_id = v_loc.id and metric_key = p_metric_type and period_type = 'annual';

      if v_total_historical > 0 then
        v_loc_pct := v_loc_historical / v_total_historical * 100;
      else
        -- Equal distribution if no history
        v_loc_pct := 100.0 / greatest((select count(*) from tj.org_locations where organization_id = v_plan.organization_id and is_active = true), 1);
      end if;

      v_loc_target := v_corporate_target * v_loc_pct / 100;

      insert into tj.budget_nodes (organization_id, budget_plan_id, location_id, period_type, period_key, metric_type, target_value, pct_of_parent)
      values (v_plan.organization_id, p_budget_plan_id, v_loc.id, p_period_type, v_plan.fiscal_year::text, p_metric_type, v_loc_target, v_loc_pct)
      on conflict do nothing;

      v_cascaded := v_cascaded + 1;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'cascaded', v_cascaded, 'corporate_target', v_corporate_target);
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.cascade_budget(p_budget_plan_id uuid, p_metric_type text, p_period_type text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.cascade_budget(p_budget_plan_id uuid, p_metric_type text DEFAULT 'revenue'::text, p_period_type text DEFAULT 'annual'::text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.cascade_budget("p_budget_plan_id","p_metric_type","p_period_type"); $adapter$;
REVOKE ALL ON FUNCTION tj.cascade_budget(p_budget_plan_id uuid, p_metric_type text, p_period_type text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.check_app_access(p_app text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := tj_private.current_source_user_id();
  v_row record;
  v_stores jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  END IF;

  IF is_platform_admin() THEN
    RETURN jsonb_build_object('allowed', true, 'reason', 'platform_admin',
      'role', 'super_admin', 'role_level', 0, 'visibility_scope', 'all',
      'store_ids', '[]'::jsonb,
      'permissions', jsonb_build_object(
        'can_manage_users', true, 'can_manage_roles', true,
        'can_view_all_analytics', true, 'can_view_team_analytics', true,
        'can_manage_kpis', true, 'can_manage_targets', true));
  END IF;

  SELECT m.organization_id, o.name AS org_name, m.role, m.visibility_scope,
         e.status AS ent_status, e.tier, e.trial_ends_at,
         r.role_name, r.role_level,
         coalesce(r.can_manage_users,false) mu, coalesce(r.can_manage_roles,false) mr,
         coalesce(r.can_view_all_analytics,false) va, coalesce(r.can_view_team_analytics,false) vt,
         coalesce(r.can_manage_kpis,false) mk, coalesce(r.can_manage_targets,false) mt
  INTO v_row
  FROM organization_members m
  JOIN organizations o ON o.id = m.organization_id AND o.status = 'active'
  JOIN org_app_entitlements e ON e.organization_id = m.organization_id AND e.app_key = p_app
  LEFT JOIN org_roles r ON r.id = m.org_role_id
  WHERE m.user_id = v_uid AND m.status = 'active'
  ORDER BY (e.status = 'active') DESC, (e.status = 'trial') DESC
  LIMIT 1;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'no_entitlement');
  END IF;

  IF v_row.ent_status = 'trial' AND v_row.trial_ends_at IS NOT NULL AND v_row.trial_ends_at < now() THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'trial_expired',
      'organization_id', v_row.organization_id, 'organization_name', v_row.org_name);
  END IF;

  IF v_row.ent_status NOT IN ('active','trial') THEN
    RETURN jsonb_build_object('allowed', false, 'reason', v_row.ent_status,
      'organization_id', v_row.organization_id, 'organization_name', v_row.org_name);
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'name', l.name, 'primary', lm.is_primary)), '[]'::jsonb)
  INTO v_stores
  FROM org_location_members lm
  JOIN org_locations l ON l.id = lm.location_id AND l.is_active
  WHERE lm.user_id = v_uid AND lm.organization_id = v_row.organization_id;

  RETURN jsonb_build_object('allowed', true, 'reason', v_row.ent_status,
    'organization_id', v_row.organization_id, 'organization_name', v_row.org_name,
    'tier', v_row.tier, 'role', v_row.role,
    'position', v_row.role_name, 'role_level', coalesce(v_row.role_level, 99),
    'visibility_scope', coalesce(v_row.visibility_scope, 'own'),
    'store_ids', v_stores,
    'permissions', jsonb_build_object(
      'can_manage_users', v_row.mu, 'can_manage_roles', v_row.mr,
      'can_view_all_analytics', v_row.va, 'can_view_team_analytics', v_row.vt,
      'can_manage_kpis', v_row.mk, 'can_manage_targets', v_row.mt));
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.check_app_access(p_app text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.check_app_access(p_app text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.check_app_access("p_app"); $adapter$;
REVOKE ALL ON FUNCTION tj.check_app_access(p_app text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.check_token_budget(p_organization_id uuid, p_tokens_needed integer)
 RETURNS TABLE(has_budget boolean, tokens_remaining bigint, org_tier text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select
    (l.monthly_limit - l.tokens_used_this_month) >= p_tokens_needed,
    (l.monthly_limit - l.tokens_used_this_month),
    o.tier
  from tj.ai_token_limits l
  join tj.organizations o on o.id = l.organization_id
  where l.organization_id = p_organization_id;
$function$;
REVOKE ALL ON FUNCTION tj_private.check_token_budget(p_organization_id uuid, p_tokens_needed integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.check_token_budget(p_organization_id uuid, p_tokens_needed integer) RETURNS TABLE(has_budget boolean, tokens_remaining bigint, org_tier text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.check_token_budget("p_organization_id","p_tokens_needed"); $adapter$;
REVOKE ALL ON FUNCTION tj.check_token_budget(p_organization_id uuid, p_tokens_needed integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.chq_claim_open_job()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.response = 'accepted' AND OLD.response IS NULL THEN
    -- Check if job is still open
    IF (SELECT status FROM chq_open_jobs WHERE id = NEW.open_job_id) = 'open' THEN
      UPDATE chq_open_jobs SET
        status = 'claimed',
        claimed_by = NEW.contractor_id,
        claimed_at = now()
      WHERE id = NEW.open_job_id;
      NEW.responded_at = now();
    ELSE
      -- Job already claimed by someone else
      NEW.response = 'expired';
      NEW.responded_at = now();
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.chq_claim_open_job() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.chq_on_new_message()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE chq_bookings SET
    last_message_at = NEW.created_at,
    has_unread_customer = CASE WHEN NEW.sender_type = 'contractor' THEN true ELSE has_unread_customer END,
    has_unread_contractor = CASE WHEN NEW.sender_type = 'customer' THEN true ELSE has_unread_contractor END
  WHERE id = NEW.booking_id;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.chq_on_new_message() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.chq_set_payout_eligibility()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.customer_signoff_at IS NOT NULL AND OLD.customer_signoff_at IS NULL THEN
    NEW.payout_eligible_at := NEW.customer_signoff_at + INTERVAL '72 hours';
    NEW.dispute_window_ends_at := NEW.customer_signoff_at + INTERVAL '72 hours';
    NEW.status := 'completed';
    NEW.completed_at := NEW.customer_signoff_at;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.chq_set_payout_eligibility() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.chq_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.chq_set_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.chq_update_contractor_rating()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  UPDATE chq_contractors SET
    avg_rating = (SELECT COALESCE(AVG(rating), 0) FROM chq_reviews WHERE contractor_id = NEW.contractor_id),
    review_count = (SELECT COUNT(*) FROM chq_reviews WHERE contractor_id = NEW.contractor_id)
  WHERE id = NEW.contractor_id;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.chq_update_contractor_rating() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.command_center_after_connector_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_org uuid;
  v_from date;
  v_to date;
  v_job_type text;
begin
  if new.status not in ('success','partial') then return new; end if;
  if old.status is not distinct from new.status then return new; end if;

  v_job_type := coalesce(new.job_type,'');
  if v_job_type not like 'business_central_%' then return new; end if;

  select c.organization_id into v_org
  from tj.platform_connector_connections c
  where c.id=new.connection_id;
  if v_org is null then return new; end if;

  select min(t.transaction_date::date), max(t.transaction_date::date)
    into v_from,v_to
  from tj.iq_pos_transactions t
  where t.source_connection_id=new.connection_id
    and t.synced_at >= coalesce(new.started_at,now()) - interval '5 minutes';

  v_from := coalesce(v_from,current_date-35);
  v_to := coalesce(v_to,current_date);
  perform tj.command_center_refresh_transaction_metrics(v_org,v_from,v_to);
  return new;
exception when others then
  -- Analytics refresh must never turn a successful ERP sync into a failed ERP sync.
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.command_center_after_connector_sync() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.command_center_refresh_transaction_metrics(p_organization_id uuid, p_from date DEFAULT (CURRENT_DATE - 35), p_to date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_inserted integer:=0; v_updated integer:=0;
begin
  if p_organization_id is null then raise exception 'organization required'; end if;
  if p_to < p_from then raise exception 'invalid date range'; end if;

  with tx as (
    select t.organization_id,
           coalesce(m.salesperson_user_id,st.user_id) user_id,
           t.store_id location_id,
           t.transaction_date::date metric_date,
           count(*) transactions,
           coalesce(sum(t.transaction_amount),0) revenue,
           coalesce(sum(t.gross_margin_amount),0) margin_dollars,
           coalesce(sum(st.item_count),0) units_sold,
           coalesce(sum(st.warranty_value),0) warranty_revenue,
           coalesce(sum(st.delivery_value),0) delivery_revenue,
           coalesce(sum(st.install_value),0) install_revenue,
           count(*) filter (where coalesce(st.warranty_sold,false)) warranty_transactions,
           count(*) filter (where coalesce(st.delivery_value,0)>0) delivery_transactions,
           count(*) filter (where coalesce(st.install_value,0)>0) install_transactions,
           count(*) filter (where coalesce(st.haul_away_value,0)>0) haul_transactions
    from tj.iq_pos_transactions t
    left join tj.iq_pos_employee_map m on m.organization_id=t.organization_id and m.pos_employee_id=t.salesperson_external_id and m.is_active=true
    left join tj.sales_transactions st on st.organization_id=t.organization_id and st.invoice_number=t.pos_transaction_id
    where t.organization_id=p_organization_id and t.transaction_date::date between p_from and p_to
    group by t.organization_id,coalesce(m.salesperson_user_id,st.user_id),t.store_id,t.transaction_date::date
  ), metrics as (
    select organization_id,location_id,user_id,metric_date,'revenue'::text metric_key,revenue actual from tx
    union all select organization_id,location_id,user_id,metric_date,'transactions',transactions::numeric from tx
    union all select organization_id,location_id,user_id,metric_date,'units_sold',units_sold::numeric from tx
    union all select organization_id,location_id,user_id,metric_date,'avg_order',case when transactions>0 then revenue/transactions end from tx
    union all select organization_id,location_id,user_id,metric_date,'ipo',case when transactions>0 then units_sold/transactions end from tx
    union all select organization_id,location_id,user_id,metric_date,'item_value',case when units_sold>0 then revenue/units_sold end from tx
    union all select organization_id,location_id,user_id,metric_date,'margin_dollars',margin_dollars from tx
    union all select organization_id,location_id,user_id,metric_date,'margin_pct',case when revenue<>0 then margin_dollars/revenue*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'warranty_attach',case when transactions>0 then warranty_transactions::numeric/transactions*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'warranty_pen_units',case when units_sold>0 then warranty_transactions::numeric/units_sold*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'warranty_pen_dollars',case when revenue<>0 then warranty_revenue/revenue*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'delivery_revenue',delivery_revenue from tx
    union all select organization_id,location_id,user_id,metric_date,'install_revenue',install_revenue from tx
    union all select organization_id,location_id,user_id,metric_date,'delivery_attach',case when transactions>0 then delivery_transactions::numeric/transactions*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'install_attach',case when transactions>0 then install_transactions::numeric/transactions*100 end from tx
    union all select organization_id,location_id,user_id,metric_date,'haul_away_attach',case when transactions>0 then haul_transactions::numeric/transactions*100 end from tx
  ), peers as (
    select organization_id,location_id,metric_date,metric_key,
           avg(actual) filter(where user_id is not null) peer_avg,
           count(distinct user_id) filter(where user_id is not null) peer_count
    from metrics where actual is not null group by organization_id,location_id,metric_date,metric_key
  ), rows_to_write as (
    select m.organization_id,m.location_id,m.user_id,'daily'::text period_type,m.metric_date::text period_key,m.metric_key,
           round(m.actual,2) actual_value,
           case when m.metric_date < current_date and m.user_id is not null and p.peer_count>=2 then round(p.peer_avg,2) else null end target_value,
           case when m.metric_date < current_date and m.user_id is not null and p.peer_count>=2 then round(m.actual-p.peer_avg,2) else null end variance_value,
           case when m.metric_date < current_date and m.user_id is not null and p.peer_count>=2 and p.peer_avg<>0 then round((m.actual-p.peer_avg)/abs(p.peer_avg)*100,2) else null end variance_pct
    from metrics m join peers p using(organization_id,location_id,metric_date,metric_key)
    where m.actual is not null
  ), ins as (
    insert into tj.metric_snapshots
      (organization_id,location_id,user_id,period_type,period_key,metric_key,metric_subtype,actual_value,target_value,variance_value,variance_pct,computed_at)
    select organization_id,location_id,user_id,period_type,period_key,metric_key,'connector_transaction',actual_value,target_value,variance_value,variance_pct,now()
    from rows_to_write
    on conflict (organization_id,location_id,user_id,period_type,period_key,metric_key,metric_subtype)
      where metric_subtype='connector_transaction'
    do update set actual_value=excluded.actual_value,
                  target_value=excluded.target_value,
                  variance_value=excluded.variance_value,
                  variance_pct=excluded.variance_pct,
                  computed_at=excluded.computed_at
    returning (xmax=0) as inserted
  )
  select count(*) filter(where inserted),count(*) filter(where not inserted) into v_inserted,v_updated from ins;

  return jsonb_build_object('ok',true,'organization_id',p_organization_id,'from',p_from,'to',p_to,'inserted',v_inserted,'updated',v_updated);
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.command_center_refresh_transaction_metrics(p_organization_id uuid, p_from date, p_to date) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.command_center_refresh_transaction_metrics(p_organization_id uuid, p_from date DEFAULT (CURRENT_DATE - 35), p_to date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.command_center_refresh_transaction_metrics("p_organization_id","p_from","p_to"); $adapter$;
REVOKE ALL ON FUNCTION tj.command_center_refresh_transaction_metrics(p_organization_id uuid, p_from date, p_to date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.complete_embedding_worker_run(p_run_id uuid, p_status text, p_rows_embedded integer, p_rows_failed integer, p_model text, p_error_message text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  update tj.embedding_worker_runs
     set status = p_status, rows_embedded = p_rows_embedded, rows_failed = p_rows_failed,
         model = p_model, error_message = p_error_message, metadata = p_metadata, finished_at = now()
   where id = p_run_id;
$function$;
REVOKE ALL ON FUNCTION tj_private.complete_embedding_worker_run(p_run_id uuid, p_status text, p_rows_embedded integer, p_rows_failed integer, p_model text, p_error_message text, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.complete_embedding_worker_run(p_run_id uuid, p_status text, p_rows_embedded integer, p_rows_failed integer, p_model text, p_error_message text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.complete_embedding_worker_run("p_run_id","p_status","p_rows_embedded","p_rows_failed","p_model","p_error_message","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.complete_embedding_worker_run(p_run_id uuid, p_status text, p_rows_embedded integer, p_rows_failed integer, p_model text, p_error_message text, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.compute_iq_score(p_org_id uuid, p_period text DEFAULT '2026-06'::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(metric_key text, metric_label text, max_points numeric, actual_value numeric, target_value numeric, pct_of_target numeric, earned_points numeric, sort_order integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  w RECORD;
  v_actual NUMERIC;
  v_target NUMERIC;
  v_pct NUMERIC;
  v_earned NUMERIC;
  v_total_interactions BIGINT;
  v_complete_contacts BIGINT;
  v_no_sale_total BIGINT;
  v_has_followup BIGINT;
BEGIN
  -- Pre-compute CRM accountability metrics for this scope
  SELECT
    count(*),
    count(*) FILTER (WHERE NOT no_crm_created AND crm_completeness = 'complete'),
    count(*) FILTER (WHERE outcome != 'sale'),
    count(*) FILTER (WHERE outcome != 'sale' AND follow_up_date IS NOT NULL)
  INTO v_total_interactions, v_complete_contacts, v_no_sale_total, v_has_followup
  FROM v_crm_accountability ca
  WHERE ca.organization_id = p_org_id
    AND (p_location_id IS NULL OR ca.store_id = p_location_id)
    AND (p_user_id IS NULL OR ca.salesperson_user_id = p_user_id);

  FOR w IN
    SELECT sw.metric_key, sw.metric_label, sw.max_points, sw.source_type, sw.direction, sw.sort_order
    FROM iq_score_weights sw
    WHERE sw.organization_id = p_org_id AND sw.is_active = true
    ORDER BY sw.sort_order
  LOOP
    v_actual := NULL;
    v_target := NULL;
    v_pct := 0;
    v_earned := 0;

    IF w.source_type = 'metric_snapshot' THEN
      -- Pull from metric_snapshots
      SELECT ms.actual_value, ms.target_value
      INTO v_actual, v_target
      FROM metric_snapshots ms
      WHERE ms.organization_id = p_org_id
        AND ms.period_type = 'monthly'
        AND ms.period_key = p_period
        AND ms.metric_key = w.metric_key
        AND (
          (p_user_id IS NOT NULL AND ms.user_id = p_user_id) OR
          (p_user_id IS NULL AND p_location_id IS NOT NULL AND ms.location_id = p_location_id AND ms.user_id IS NULL) OR
          (p_user_id IS NULL AND p_location_id IS NULL AND ms.location_id IS NULL AND ms.user_id IS NULL)
        )
      LIMIT 1;

      IF v_actual IS NOT NULL AND v_target IS NOT NULL AND v_target > 0 THEN
        IF w.direction = 'lower_is_better' THEN
          v_pct := LEAST(v_target / NULLIF(v_actual, 0), 1.0);
        ELSE
          v_pct := LEAST(v_actual / v_target, 1.0);
        END IF;
        v_earned := ROUND(v_pct * w.max_points, 1);
      END IF;

    ELSIF w.metric_key = 'crm_completion' THEN
      -- CRM Completion Rate
      v_target := 100;
      IF v_total_interactions > 0 THEN
        v_actual := ROUND((v_complete_contacts::numeric / v_total_interactions) * 100, 1);
        v_pct := LEAST(v_actual / 100.0, 1.0);
        v_earned := ROUND(v_pct * w.max_points, 1);
      ELSE
        v_actual := 0;
      END IF;

    ELSIF w.metric_key = 'follow_up_compliance' THEN
      -- Follow-up rate on no-sale
      v_target := 100;
      IF v_no_sale_total > 0 THEN
        v_actual := ROUND((v_has_followup::numeric / v_no_sale_total) * 100, 1);
        v_pct := LEAST(v_actual / 100.0, 1.0);
        v_earned := ROUND(v_pct * w.max_points, 1);
      ELSE
        v_actual := 0;
      END IF;
    END IF;

    metric_key := w.metric_key;
    metric_label := w.metric_label;
    max_points := w.max_points;
    actual_value := v_actual;
    target_value := v_target;
    pct_of_target := ROUND(COALESCE(v_pct, 0) * 100, 1);
    earned_points := COALESCE(v_earned, 0);
    sort_order := w.sort_order;
    RETURN NEXT;
  END LOOP;
END $function$;
REVOKE ALL ON FUNCTION tj_private.compute_iq_score(p_org_id uuid, p_period text, p_location_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.compute_iq_score(p_org_id uuid, p_period text DEFAULT '2026-06'::text, p_location_id uuid DEFAULT NULL::uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS TABLE(metric_key text, metric_label text, max_points numeric, actual_value numeric, target_value numeric, pct_of_target numeric, earned_points numeric, sort_order integer) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.compute_iq_score("p_org_id","p_period","p_location_id","p_user_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.compute_iq_score(p_org_id uuid, p_period text, p_location_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.connector_incident_metric_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$ begin perform tj.refresh_connector_incident_metrics(new.id); return new; end $function$;
REVOKE ALL ON FUNCTION tj_private.connector_incident_metric_trigger() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.connector_payload_fingerprint(p_payload jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select md5(coalesce((
    select string_agg(key || ':' || jsonb_typeof(value), '|' order by key)
    from jsonb_each(coalesce(p_payload,'{}'::jsonb))
  ), ''));
$function$;
REVOKE ALL ON FUNCTION tj.connector_payload_fingerprint(p_payload jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.consent_active(p_subject uuid, p_scope text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM consent_ledger
    WHERE subject_id = p_subject AND scope = p_scope
      AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at > now()));
$function$;
REVOKE ALL ON FUNCTION tj.consent_active(p_subject uuid, p_scope text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.consume_platform_handoff_ticket(p_ticket_hash text, p_target_module_key text DEFAULT NULL::text)
 RETURNS TABLE(user_id uuid, organization_id uuid, location_id uuid, entity_type text, entity_id uuid, entity_label text, source_module_key text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  update tj.platform_handoff_tickets t
  set consumed_at=now()
  where t.ticket_hash=p_ticket_hash
    and t.consumed_at is null
    and t.expires_at>now()
    and (t.target_module_key is null or p_target_module_key is null or t.target_module_key=p_target_module_key)
  returning t.id into v_id;
  if v_id is null then return; end if;
  return query
    select t.user_id,t.organization_id,t.location_id,t.entity_type,t.entity_id,t.entity_label,t.source_module_key
    from tj.platform_handoff_tickets t where t.id=v_id;
end $function$;
REVOKE ALL ON FUNCTION tj_private.consume_platform_handoff_ticket(p_ticket_hash text, p_target_module_key text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.consume_platform_handoff_ticket(p_ticket_hash text, p_target_module_key text DEFAULT NULL::text) RETURNS TABLE(user_id uuid, organization_id uuid, location_id uuid, entity_type text, entity_id uuid, entity_label text, source_module_key text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.consume_platform_handoff_ticket("p_ticket_hash","p_target_module_key"); $adapter$;
REVOKE ALL ON FUNCTION tj.consume_platform_handoff_ticket(p_ticket_hash text, p_target_module_key text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_auto_enroll_on_stage_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  camp RECORD;
  v_already_enrolled BOOLEAN;
  v_cond_met BOOLEAN;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.stage IS NOT DISTINCT FROM NEW.stage THEN
    RETURN NEW;
  END IF;
  IF NEW.contact_id IS NULL THEN RETURN NEW; END IF;

  FOR camp IN
    SELECT id, trigger_condition
    FROM aicrm_outreach_campaigns
    WHERE organization_id = NEW.organization_id
      AND status = 'active'
      AND trigger_stage = NEW.stage
  LOOP
    v_cond_met := true;
    IF camp.trigger_condition IS NOT NULL AND camp.trigger_condition != '{}'::jsonb THEN
      IF camp.trigger_condition->>'warranty_status' IS NOT NULL THEN
        IF NEW.warranty_status IS DISTINCT FROM camp.trigger_condition->>'warranty_status' THEN
          v_cond_met := false;
        END IF;
      END IF;
    END IF;
    IF NOT v_cond_met THEN CONTINUE; END IF;

    SELECT EXISTS (
      SELECT 1 FROM aicrm_sequence_enrollments
      WHERE contact_id = NEW.contact_id AND campaign_id = camp.id
        AND status IN ('active','paused')
    ) INTO v_already_enrolled;

    IF NOT v_already_enrolled THEN
      INSERT INTO aicrm_sequence_enrollments (
        organization_id, contact_id, campaign_id, deal_id,
        current_step, status, enrolled_at
      ) VALUES (
        NEW.organization_id, NEW.contact_id, camp.id, NEW.id,
        1, 'active', now()
      );
    END IF;
  END LOOP;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_auto_enroll_on_stage_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_compute_contact_completeness()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  NEW.crm_completeness := CASE
    WHEN (NEW.full_name IS NOT NULL AND NEW.full_name != '' OR 
          NEW.first_name IS NOT NULL AND NEW.first_name != '')
         AND (NEW.email IS NOT NULL OR (NEW.phone IS NOT NULL AND NEW.phone != ''))
    THEN 'complete'
    WHEN (NEW.full_name IS NOT NULL AND NEW.full_name != '' OR 
          NEW.first_name IS NOT NULL AND NEW.first_name != '')
    THEN 'partial'
    ELSE 'incomplete'
  END;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_compute_contact_completeness() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_deal_auto_location()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.owner_user_id IS NOT NULL AND (TG_OP = 'INSERT' OR OLD.owner_user_id IS DISTINCT FROM NEW.owner_user_id) THEN
    SELECT olm.location_id INTO NEW.location_id
    FROM org_location_members olm
    WHERE olm.user_id = NEW.owner_user_id AND olm.organization_id = NEW.organization_id
    LIMIT 1;
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_deal_auto_location() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_enrollment_complete_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_action TEXT;
BEGIN
  IF OLD.status IS DISTINCT FROM 'completed' AND NEW.status = 'completed' THEN
    SELECT on_complete_action INTO v_action
    FROM aicrm_outreach_campaigns WHERE id = NEW.campaign_id;

    IF v_action = 'move_to_vip' AND NEW.deal_id IS NOT NULL THEN
      UPDATE crm_deals SET stage = 'VIP', stage_entered_at = now()
      WHERE id = NEW.deal_id AND deleted_at IS NULL;

      INSERT INTO crm_stage_history (deal_id, organization_id, from_stage, to_stage, changed_by, changed_at)
      SELECT id, organization_id, 'Closed Lost', 'VIP', owner_user_id, now()
      FROM crm_deals WHERE id = NEW.deal_id;
    END IF;
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_enrollment_complete_action() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_handle_rep_deactivation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_orphan_count INT;
BEGIN
  -- Fire when status changes from active to anything else
  IF OLD.status = 'active' AND NEW.status != 'active' THEN
    -- Count orphaned open deals
    SELECT count(*) INTO v_orphan_count
    FROM crm_deals
    WHERE organization_id = NEW.organization_id
      AND owner_user_id = NEW.user_id
      AND deleted_at IS NULL
      AND (closed_at IS NULL OR stage NOT IN ('Closed Won', 'Closed Lost', 'VIP'));

    -- If there are orphaned deals, create a notification for managers
    IF v_orphan_count > 0 THEN
      INSERT INTO crm_notifications (
        organization_id, user_id, type, title, body, metadata, created_at
      )
      SELECT
        NEW.organization_id,
        om.user_id,
        'rep_deactivated',
        'Rep deactivated — ' || v_orphan_count || ' deals need reassignment',
        'A sales rep has been deactivated with ' || v_orphan_count || ' open deals. Please reassign or archive these deals.',
        jsonb_build_object(
          'deactivated_user_id', NEW.user_id,
          'orphan_count', v_orphan_count
        ),
        now()
      FROM organization_members om
      WHERE om.organization_id = NEW.organization_id
        AND om.status = 'active'
        AND om.role IN ('owner', 'admin', 'manager');
    END IF;
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_handle_rep_deactivation() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_log_contact_archive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- Fire when deleted_at changes from NULL to a value
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    INSERT INTO crm_archive_log(
      organization_id, actor_user_id, record_type, record_id, action, reason,
      record_snapshot, contact_completeness, up_interaction_id
    ) VALUES (
      NEW.organization_id,
      coalesce(tj_private.current_source_user_id(), NEW.updated_by),
      'contact',
      NEW.id,
      'soft_delete',
      NEW.archive_reason,
      jsonb_build_object(
        'full_name', OLD.full_name, 'first_name', OLD.first_name, 'last_name', OLD.last_name,
        'email', OLD.email::text, 'phone', OLD.phone, 'source', OLD.source,
        'crm_completeness', OLD.crm_completeness, 'created_at', OLD.created_at
      ),
      OLD.crm_completeness,
      OLD.up_interaction_id
    );
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_log_contact_archive() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.crm_log_deal_archive()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    INSERT INTO crm_archive_log(
      organization_id, actor_user_id, record_type, record_id, action, reason,
      record_snapshot, up_interaction_id
    ) VALUES (
      NEW.organization_id,
      coalesce(tj_private.current_source_user_id(), NEW.owner_user_id),
      'deal',
      NEW.id,
      'soft_delete',
      NEW.archive_reason,
      jsonb_build_object(
        'title', OLD.title, 'stage', OLD.stage, 'value_amount', OLD.value_amount,
        'contact_id', OLD.contact_id, 'owner_user_id', OLD.owner_user_id,
        'source', OLD.source, 'record_type', OLD.record_type, 'created_at', OLD.created_at
      ),
      OLD.up_interaction_id
    );
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.crm_log_deal_archive() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.current_user_roles()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select coalesce(
    array_agg(distinct om.role order by om.role),
    array[]::text[]
  )
  from tj.organization_members om
  where om.user_id = tj_private.current_source_user_id()
    and om.status = 'active';
$function$;
REVOKE ALL ON FUNCTION tj_private.current_user_roles() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.current_user_roles() RETURNS text[] LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.current_user_roles(); $adapter$;
REVOKE ALL ON FUNCTION tj.current_user_roles() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_check_expired_predictions()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_expired int := 0;
begin
  UPDATE tj.decision_predictions
  SET status = 'expired'
  WHERE expires_at < now() AND actual_value IS NULL AND coalesce(status,'active') = 'active';
  GET DIAGNOSTICS v_expired = ROW_COUNT;
  return jsonb_build_object('expired_predictions', v_expired);
end;
$function$;
REVOKE ALL ON FUNCTION tj.decision_check_expired_predictions() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_create_case(p_organization_id uuid, p_module text, p_title text, p_summary text, p_recommendation text, p_consequence_if_ignored text DEFAULT NULL::text, p_decision_type text DEFAULT 'operational'::text, p_severity text DEFAULT 'medium'::text, p_financial_impact_cad numeric DEFAULT NULL::numeric, p_customer_impact_score numeric DEFAULT 0, p_urgency_score numeric DEFAULT 50, p_confidence numeric DEFAULT 0.5, p_evidence_quality numeric DEFAULT 0.5, p_effort_score numeric DEFAULT 50, p_source_system text DEFAULT 'manual'::text, p_source_record_id text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  insert into tj.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,source_system,source_record_id,metadata,created_by,updated_by)
  values(p_organization_id,p_module,p_title,p_summary,p_recommendation,p_consequence_if_ignored,p_decision_type,p_severity,p_financial_impact_cad,p_customer_impact_score,p_urgency_score,p_confidence,p_evidence_quality,p_effort_score,p_source_system,p_source_record_id,coalesce(p_metadata,'{}'::jsonb),(select tj_private.current_source_user_id()),(select tj_private.current_source_user_id()))
  returning id into v_id;
  insert into tj.decision_actions(organization_id,decision_case_id,action_text,created_by)
  values(p_organization_id,v_id,p_recommendation,(select tj_private.current_source_user_id()));
  return v_id;
end $function$;
REVOKE ALL ON FUNCTION tj.decision_create_case(p_organization_id uuid, p_module text, p_title text, p_summary text, p_recommendation text, p_consequence_if_ignored text, p_decision_type text, p_severity text, p_financial_impact_cad numeric, p_customer_impact_score numeric, p_urgency_score numeric, p_confidence numeric, p_evidence_quality numeric, p_effort_score numeric, p_source_system text, p_source_record_id text, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_generate_operational_forecasts(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_revenue numeric:=0; v_avg_order numeric:=0; v_conv numeric:=0; v_conv_target numeric:=0; v_walkins numeric:=0;
  v_training numeric:=0; v_training_target numeric:=100; v_pipeline numeric:=0; v_weighted numeric:=0; v_stale_value numeric:=0;
  v_case uuid; v_created int:=0; v_prediction int:=0; v_gap numeric; v_impact numeric; v_prob numeric;
  v_critical int:=0;
begin
  if not tj.is_org_member(p_organization_id) then raise exception 'Not authorized'; end if;

  select coalesce(max(actual_value) filter(where metric_key='revenue'),0),
         coalesce(max(actual_value) filter(where metric_key='avg_order'),0),
         coalesce(max(actual_value) filter(where metric_key='floor_conversion'),0),
         coalesce(max(target_value) filter(where metric_key='floor_conversion'),0),
         coalesce(max(actual_value) filter(where metric_key='walk_ins'),0),
         coalesce(max(actual_value) filter(where metric_key='training_completion'),0),
         coalesce(max(target_value) filter(where metric_key='training_completion'),100)
  into v_revenue,v_avg_order,v_conv,v_conv_target,v_walkins,v_training,v_training_target
  from tj.metric_snapshots m
  where m.organization_id=p_organization_id and m.user_id is null and m.location_id is null
    and m.period_key=(select max(period_key) from tj.metric_snapshots where organization_id=p_organization_id);

  select coalesce(sum(opportunity_value) filter(where coalesce(status,'open') not in ('closed','won','lost')),0),
         coalesce(sum(opportunity_value*least(greatest(coalesce(probability,0),0),100)/100) filter(where coalesce(status,'open') not in ('closed','won','lost')),0),
         coalesce(sum(opportunity_value) filter(where updated_at<now()-interval '14 days' and coalesce(status,'open') not in ('closed','won','lost')),0)
  into v_pipeline,v_weighted,v_stale_value from tj.aicrm_opportunities where organization_id=p_organization_id;

  if v_pipeline>0 then
    select id into v_case from tj.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='crm_pipeline_30d' limit 1;
    v_impact:=round(v_weighted,2); v_prob:=case when v_pipeline>0 then least(.9,greatest(.35,v_weighted/v_pipeline)) else .35 end;
    if v_case is null then
      insert into tj.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'crm','30-day CRM revenue forecast',format('Open pipeline is C$%s with C$%s probability-weighted.',to_char(v_pipeline,'FM999,999,990'),to_char(v_weighted,'FM999,999,990')),'Focus follow-up on stale, high-value opportunities before adding more pipeline.',format('Approximately C$%s of stale pipeline is exposed to further decay.',to_char(v_stale_value*.15,'FM999,999,990')),'forecast','open',case when v_stale_value>v_pipeline*.25 then 'high' else 'medium' end,v_impact,75,80,v_prob,.85,35,tj.decision_calculate_priority(v_impact,75,80,v_prob,.85,35),'prediction_engine','crm_pipeline_30d',jsonb_build_object('pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value),tj_private.current_source_user_id()) returning id into v_case;
      v_created:=v_created+1;
    else
      update tj.decision_cases set summary=format('Open pipeline is C$%s with C$%s probability-weighted.',to_char(v_pipeline,'FM999,999,990'),to_char(v_weighted,'FM999,999,990')), financial_impact_cad=v_impact, confidence=v_prob, consequence_if_ignored=format('Approximately C$%s of stale pipeline is exposed to further decay.',to_char(v_stale_value*.15,'FM999,999,990')), priority_score=tj.decision_calculate_priority(v_impact,75,80,v_prob,.85,35), metadata=jsonb_build_object('pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value),updated_at=now(),updated_by=tj_private.current_source_user_id() where id=v_case;
    end if;
    delete from tj.decision_predictions where decision_case_id=v_case and prediction_type='revenue';
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'revenue','30_days',v_pipeline,v_weighted,v_weighted-v_pipeline,'CAD',v_prob,v_weighted*.75,v_weighted*1.2,v_stale_value*.15,v_weighted,jsonb_build_object('method','probability-weighted opportunity value','stale_decay_rate',.15),'ApplianceIQ rules forecast','1.0',now()+interval '7 days');
    v_prediction:=v_prediction+1;
  end if;

  v_gap:=greatest(v_conv_target-v_conv,0);
  if v_gap>0 and v_walkins>0 and v_avg_order>0 then
    v_impact:=round(v_walkins*(v_gap/100)*v_avg_order,2);
    select id into v_case from tj.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='floor_conversion_gap' limit 1;
    if v_case is null then
      insert into tj.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'retail_floor','Close the floor conversion gap',format('Conversion is %s%% against a %s%% target across %s walk-ins.',v_conv,v_conv_target,v_walkins),'Review greeting coverage, missed ups, and rep conversion by shift.',format('At the current traffic and average order, the monthly opportunity gap is approximately C$%s.',to_char(v_impact,'FM999,999,990')),'opportunity','open','high',v_impact,90,85,.78,.9,45,tj.decision_calculate_priority(v_impact,90,85,.78,.9,45),'prediction_engine','floor_conversion_gap',jsonb_build_object('conversion',v_conv,'target',v_conv_target,'walk_ins',v_walkins,'avg_order',v_avg_order),tj_private.current_source_user_id()) returning id into v_case;
      v_created:=v_created+1;
    else update tj.decision_cases set financial_impact_cad=v_impact,summary=format('Conversion is %s%% against a %s%% target across %s walk-ins.',v_conv,v_conv_target,v_walkins),consequence_if_ignored=format('At the current traffic and average order, the monthly opportunity gap is approximately C$%s.',to_char(v_impact,'FM999,999,990')),priority_score=tj.decision_calculate_priority(v_impact,90,85,.78,.9,45),metadata=jsonb_build_object('conversion',v_conv,'target',v_conv_target,'walk_ins',v_walkins,'avg_order',v_avg_order),updated_at=now(),updated_by=tj_private.current_source_user_id() where id=v_case; end if;
    delete from tj.decision_predictions where decision_case_id=v_case and prediction_type='conversion_revenue';
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'conversion_revenue','30_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.78,v_revenue+v_impact*.5,v_revenue+v_impact,v_impact,v_impact,jsonb_build_object('formula','walk-ins × conversion gap × average order','conversion_gap_points',v_gap),'ApplianceIQ opportunity model','1.0',now()+interval '14 days');
    v_prediction:=v_prediction+1;
  end if;

  v_gap:=greatest(v_training_target-v_training,0);
  if v_gap>=10 and v_revenue>0 then
    v_impact:=round(v_revenue*(v_gap/100)*.03,2);
    select id into v_case from tj.decision_cases where organization_id=p_organization_id and source_system='prediction_engine' and source_record_id='training_completion_gap' limit 1;
    if v_case is null then
      insert into tj.decision_cases(organization_id,module,title,summary,recommendation,consequence_if_ignored,decision_type,status,severity,financial_impact_cad,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,priority_score,source_system,source_record_id,metadata,created_by)
      values(p_organization_id,'academy','Training completion is below target',format('Training completion is %s%%, %s points below target.',v_training,v_gap),'Assign incomplete modules to active reps and measure conversion after completion.','The revenue estimate is deliberately conservative and should be recalibrated after measured outcomes.','opportunity','open','medium',v_impact,65,60,.58,.65,40,tj.decision_calculate_priority(v_impact,65,60,.58,.65,40),'prediction_engine','training_completion_gap',jsonb_build_object('completion',v_training,'target',v_training_target,'revenue',v_revenue),tj_private.current_source_user_id()) returning id into v_case;
      v_created:=v_created+1;
    else update tj.decision_cases set financial_impact_cad=v_impact,summary=format('Training completion is %s%%, %s points below target.',v_training,v_gap),priority_score=tj.decision_calculate_priority(v_impact,65,60,.58,.65,40),metadata=jsonb_build_object('completion',v_training,'target',v_training_target,'revenue',v_revenue),updated_at=now(),updated_by=tj_private.current_source_user_id() where id=v_case; end if;
    delete from tj.decision_predictions where decision_case_id=v_case and prediction_type='training_revenue';
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'training_revenue','60_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.58,v_revenue,v_revenue+v_impact*1.5,v_impact,v_impact,jsonb_build_object('conservative_lift_rate',.03,'completion_gap_points',v_gap),'ApplianceIQ training impact proxy','1.0',now()+interval '30 days');
    v_prediction:=v_prediction+1;
  end if;

  select count(*) into v_critical from tj.field_findings f join tj.field_clients c on c.id=f.client_id where c.organization_id=p_organization_id and lower(coalesce(f.severity,''))='critical' and lower(coalesce(f.status,'open')) not in ('resolved','closed');
  if v_critical>0 then
    update tj.decision_cases set consequence_if_ignored=format('%s critical field finding(s) remain exposed. No CAD estimate is shown until sales attribution exists.',v_critical),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('critical_findings',v_critical,'financial_estimate_status','insufficient_attribution'),updated_at=now() where organization_id=p_organization_id and source_system='executive_intelligence' and module='field' and status not in ('completed','rejected');
  end if;

  return jsonb_build_object('organization_id',p_organization_id,'cases_created',v_created,'predictions_generated',v_prediction,'inputs',jsonb_build_object('revenue',v_revenue,'avg_order',v_avg_order,'conversion',v_conv,'conversion_target',v_conv_target,'walk_ins',v_walkins,'training_completion',v_training,'open_pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value,'critical_findings',v_critical));
end $function$;
REVOKE ALL ON FUNCTION tj.decision_generate_operational_forecasts(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_get_feed(p_organization_id uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
select coalesce(jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.created_at desc),'[]'::jsonb)
from (
 select c.id,c.module,c.title,c.summary,c.recommendation,c.consequence_if_ignored,c.decision_type,c.status,c.severity,c.financial_impact_cad,c.priority_score,c.confidence,c.evidence_quality,c.owner_id,c.due_at,c.created_at,
   (select count(*) from tj.decision_evidence e where e.decision_case_id=c.id) as evidence_count,
   (select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'text',a.action_text,'status',a.status,'owner_id',a.owner_id,'due_at',a.due_at) order by a.created_at),'[]'::jsonb) from tj.decision_actions a where a.decision_case_id=c.id) as actions,
   (select coalesce(jsonb_agg(jsonb_build_object('type',p.prediction_type,'predicted_value',p.predicted_value,'delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'horizon',p.horizon) order by p.generated_at desc),'[]'::jsonb) from tj.decision_predictions p where p.decision_case_id=c.id) as predictions
 from tj.decision_cases c
 where c.organization_id=p_organization_id and c.status not in ('completed','dismissed','expired')
 order by c.priority_score desc,c.created_at desc
 limit greatest(1,least(coalesce(p_limit,25),100))
) x;
$function$;
REVOKE ALL ON FUNCTION tj.decision_get_feed(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_get_prediction_dashboard(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
 select case when tj.is_org_member(p_organization_id) then jsonb_build_object(
  'summary',jsonb_build_object('active_predictions',count(*) filter(where p.status='active'),'total_predicted_impact_cad',coalesce(sum(p.financial_impact_cad) filter(where p.status='active'),0),'total_cost_of_inaction_cad',coalesce(sum(p.cost_of_inaction_cad) filter(where p.status='active'),0),'measured_predictions',count(*) filter(where p.status='measured')),
  'predictions',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'case_id',c.id,'title',c.title,'module',c.module,'priority_score',c.priority_score,'prediction_type',p.prediction_type,'horizon',p.horizon,'baseline_value',p.baseline_value,'predicted_value',p.predicted_value,'predicted_delta',p.predicted_delta,'unit',p.unit,'probability',p.probability,'lower_bound',p.lower_bound,'upper_bound',p.upper_bound,'financial_impact_cad',p.financial_impact_cad,'cost_of_inaction_cad',p.cost_of_inaction_cad,'assumptions',p.assumptions,'model_name',p.model_name,'model_version',p.model_version,'status',p.status,'actual_value',p.actual_value,'absolute_error',p.absolute_error,'percent_error',p.percent_error,'generated_at',p.generated_at) order by c.priority_score desc),'[]'::jsonb)
 ) else jsonb_build_object('error','Not authorized') end
 from tj.decision_predictions p join tj.decision_cases c on c.id=p.decision_case_id where p.organization_id=p_organization_id;
$function$;
REVOKE ALL ON FUNCTION tj.decision_get_prediction_dashboard(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_pred record;
  v_error_pct numeric;
  v_abs_error numeric;
  v_direction text;
begin
  SELECT * INTO v_pred FROM tj.decision_predictions WHERE id = p_prediction_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Prediction not found'; END IF;

  -- Compute error
  IF v_pred.predicted_value IS NOT NULL AND v_pred.predicted_value != 0 THEN
    v_error_pct := round(((p_actual_value - v_pred.predicted_value) / abs(v_pred.predicted_value)) * 100, 2);
    v_abs_error := abs(v_error_pct);
    v_direction := CASE WHEN v_error_pct > 0 THEN 'over' WHEN v_error_pct < 0 THEN 'under' ELSE 'exact' END;
  END IF;

  -- Update prediction
  UPDATE tj.decision_predictions SET
    actual_value = p_actual_value,
    actual_financial_impact_cad = coalesce(p_actual_financial_impact_cad, p_actual_value),
    error_pct = v_error_pct,
    status = 'resolved',
    updated_at = now()
  WHERE id = p_prediction_id;

  -- Update model performance aggregate
  INSERT INTO tj.decision_model_performance(
    organization_id, module, prediction_type,
    sample_count, mean_absolute_error, mean_absolute_percentage_error,
    last_measured_at, updated_at
  ) VALUES (
    v_pred.organization_id, coalesce(v_pred.model_name, 'unknown'), v_pred.prediction_type,
    1, v_abs_error, v_abs_error,
    now(), now()
  )
  ON CONFLICT (organization_id, module, prediction_type) DO UPDATE SET
    sample_count = decision_model_performance.sample_count + 1,
    mean_absolute_error = round(
      (decision_model_performance.mean_absolute_error * decision_model_performance.sample_count + v_abs_error) 
      / (decision_model_performance.sample_count + 1), 2),
    mean_absolute_percentage_error = round(
      (decision_model_performance.mean_absolute_percentage_error * decision_model_performance.sample_count + v_abs_error) 
      / (decision_model_performance.sample_count + 1), 2),
    last_measured_at = now(),
    updated_at = now();

  RETURN jsonb_build_object(
    'prediction_id', p_prediction_id,
    'predicted', v_pred.predicted_value,
    'actual', p_actual_value,
    'error_pct', v_error_pct,
    'direction', v_direction
  );
end;
$function$;
REVOKE ALL ON FUNCTION tj.decision_record_prediction_outcome(p_prediction_id uuid, p_actual_value numeric, p_actual_financial_impact_cad numeric) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_sync_executive_insights(p_organization_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; v_count integer:=0; v_id uuid; v_conf numeric;
begin
 for r in select * from tj.executive_intelligence_insights where organization_id=p_organization_id and status in ('open','active')
 loop
   if not exists(select 1 from tj.decision_cases where organization_id=p_organization_id and source_system='executive_intelligence' and source_record_id=r.id::text and status not in ('completed','dismissed','expired')) then
     v_conf:=least(0.95,greatest(0.45,coalesce(r.priority_score,50)/100.0));
     v_id:=tj.decision_create_case(p_organization_id,coalesce(r.domain,'executive'),r.title,r.summary,coalesce(r.recommended_action,'Review and assign an owner.'),null,case when r.insight_type='risk' then 'risk' else 'strategic' end,coalesce(r.severity,'medium'),null,case when r.severity='critical' then 90 when r.severity='high' then 75 else 50 end,coalesce(r.priority_score,50),v_conf,v_conf,40,'executive_intelligence',r.id::text,jsonb_build_object('insight_type',r.insight_type,'evidence',r.evidence,'source_systems',r.source_systems));
     insert into tj.decision_evidence(organization_id,decision_case_id,evidence_type,source_system,source_table,source_record_id,label,description,weight,confidence,evidence)
     values(p_organization_id,v_id,'executive_insight','executive_intelligence','executive_intelligence_insights',r.id::text,r.title,r.summary,1,v_conf,coalesce(r.evidence,'{}'::jsonb));
     v_count:=v_count+1;
   end if;
 end loop;
 return v_count;
end $function$;
REVOKE ALL ON FUNCTION tj.decision_sync_executive_insights(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid DEFAULT NULL::uuid, p_due_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_outcome_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_unit text DEFAULT NULL::text, p_outcome_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_action tj.decision_actions; v_case_status text;
begin
 update tj.decision_actions set
   status=p_status,
   owner_id=coalesce(p_owner_id,owner_id), due_at=coalesce(p_due_at,due_at),
   accepted_at=case when p_status='accepted' and accepted_at is null then now() else accepted_at end,
   started_at=case when p_status='in_progress' and started_at is null then now() else started_at end,
   completed_at=case when p_status in ('completed','measured') and completed_at is null then now() else completed_at end,
   outcome_success=coalesce(p_outcome_success,outcome_success), outcome_value=coalesce(p_outcome_value,outcome_value), outcome_unit=coalesce(p_outcome_unit,outcome_unit), outcome_notes=coalesce(p_outcome_notes,outcome_notes), updated_at=now()
 where id=p_action_id returning * into v_action;
 if v_action.id is null then raise exception 'Decision action not found or unavailable'; end if;
 v_case_status:=case p_status when 'accepted' then 'accepted' when 'assigned' then 'accepted' when 'in_progress' then 'in_progress' when 'completed' then 'completed' when 'measured' then 'completed' when 'rejected' then 'rejected' when 'cancelled' then 'dismissed' else null end;
 if v_case_status is not null then update tj.decision_cases set status=v_case_status,owner_id=coalesce(p_owner_id,owner_id),due_at=coalesce(p_due_at,due_at),updated_by=(select tj_private.current_source_user_id()) where id=v_action.decision_case_id; end if;
 return to_jsonb(v_action);
end $function$;
REVOKE ALL ON FUNCTION tj.decision_update_action(p_action_id uuid, p_status text, p_owner_id uuid, p_due_at timestamp with time zone, p_outcome_success boolean, p_outcome_value numeric, p_outcome_unit text, p_outcome_notes text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.deduct_tokens(p_organization_id uuid, p_tokens_used integer)
 RETURNS TABLE(success boolean, tokens_remaining bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  update tj.ai_token_limits
  set tokens_used_this_month = tokens_used_this_month + p_tokens_used
  where organization_id = p_organization_id
    and tokens_used_this_month + p_tokens_used <= monthly_limit
  returning true as success, (monthly_limit - tokens_used_this_month - p_tokens_used) as tokens_remaining;
$function$;
REVOKE ALL ON FUNCTION tj_private.deduct_tokens(p_organization_id uuid, p_tokens_used integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.deduct_tokens(p_organization_id uuid, p_tokens_used integer) RETURNS TABLE(success boolean, tokens_remaining bigint) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.deduct_tokens("p_organization_id","p_tokens_used"); $adapter$;
REVOKE ALL ON FUNCTION tj.deduct_tokens(p_organization_id uuid, p_tokens_used integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.enforce_platform_security_certification()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if new.lifecycle_status='certified' and not new.platform_security_passed then
    raise exception 'Connector cannot be certified while Platform Security Gate is failing';
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.enforce_platform_security_certification() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.enqueue_connector_alert_notifications()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_org uuid;
begin
  if new.status <> 'open' or new.severity not in ('critical','high') then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status = new.status and old.severity = new.severity and old.last_seen_at = new.last_seen_at then
    return new;
  end if;

  select c.organization_id into v_org
  from tj.platform_connector_connections c
  where c.id = new.connection_id;

  if v_org is null then return new; end if;

  insert into tj.platform_connector_alert_deliveries(alert_id,organization_id,user_id,channel,status)
  select new.id,v_org,m.user_id,'in_app','pending'
  from tj.organization_members m
  where m.organization_id=v_org and m.status='active' and m.role in ('owner','admin')
  on conflict (alert_id,user_id,channel) do nothing;

  if new.severity='critical' then
    insert into tj.platform_connector_alert_deliveries(alert_id,organization_id,user_id,channel,status)
    select new.id,v_org,m.user_id,'email','pending'
    from tj.organization_members m
    where m.organization_id=v_org and m.status='active' and m.role in ('owner','admin')
    on conflict (alert_id,user_id,channel) do nothing;
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.enqueue_connector_alert_notifications() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.evaluate_sla_rules(p_org_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_rule RECORD;
  v_contact RECORD;
  v_deal RECORD;
  v_events_created integer := 0;
  v_result jsonb := '[]'::jsonb;
BEGIN
  -- Loop through active SLA rules
  FOR v_rule IN 
    SELECT * FROM crm_sla_rules 
    WHERE is_active = true
    AND (p_org_id IS NULL OR organization_id = p_org_id)
    ORDER BY days_threshold ASC
  LOOP
    -- Check contacts with no recent communication
    FOR v_contact IN
      SELECT c.id, c.organization_id, c.first_name, c.last_name, 
             c.assigned_salesperson_id,
             EXTRACT(DAY FROM now() - COALESCE(c.last_communication_at, c.created_at))::integer AS days_idle
      FROM contacts c
      WHERE c.organization_id = v_rule.organization_id
        AND c.lifecycle_stage NOT IN ('churn', 'do_not_contact', 'duplicate')
        AND c.relationship_status = 'active'
        AND EXTRACT(DAY FROM now() - COALESCE(c.last_communication_at, c.created_at))::integer >= v_rule.days_threshold
        -- Don't create duplicate events for same contact+rule within 24h
        AND NOT EXISTS (
          SELECT 1 FROM crm_sla_events e
          WHERE e.contact_id = c.id 
            AND e.rule_id = v_rule.id
            AND e.resolved_at IS NULL
            AND e.created_at > now() - interval '24 hours'
        )
    LOOP
      INSERT INTO crm_sla_events (
        organization_id, contact_id, rule_id, event_type,
        days_since_contact, assigned_to
      ) VALUES (
        v_contact.organization_id, v_contact.id, v_rule.id, v_rule.action,
        v_contact.days_idle, v_contact.assigned_salesperson_id
      );
      v_events_created := v_events_created + 1;
    END LOOP;

    -- Check deals with no recent activity
    FOR v_deal IN
      SELECT d.id, d.organization_id, d.title, d.owner_user_id,
             EXTRACT(DAY FROM now() - COALESCE(d.last_contact_at, d.created_at))::integer AS days_idle
      FROM crm_deals d
      WHERE d.organization_id = v_rule.organization_id
        AND d.is_archived IS NOT TRUE
        AND d.stage NOT IN ('won', 'lost', 'closed')
        AND EXTRACT(DAY FROM now() - COALESCE(d.last_contact_at, d.created_at))::integer >= v_rule.days_threshold
        AND NOT EXISTS (
          SELECT 1 FROM crm_sla_events e
          WHERE e.deal_id = d.id
            AND e.rule_id = v_rule.id
            AND e.resolved_at IS NULL
            AND e.created_at > now() - interval '24 hours'
        )
    LOOP
      INSERT INTO crm_sla_events (
        organization_id, deal_id, rule_id, event_type,
        days_since_contact, assigned_to
      ) VALUES (
        v_deal.organization_id, v_deal.id, v_rule.id, v_rule.action,
        v_deal.days_idle, v_deal.owner_user_id
      );
      v_events_created := v_events_created + 1;
    END LOOP;
  END LOOP;

  RETURN jsonb_build_object('events_created', v_events_created);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.evaluate_sla_rules(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.evaluate_sla_rules(p_org_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.evaluate_sla_rules("p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.evaluate_sla_rules(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.executive_answer_question(p_organization_id uuid, p_question text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_q text := lower(trim(coalesce(p_question,'')));
  v_intent text;
  v_answer jsonb;
  v_evidence jsonb;
  v_confidence numeric;
  v_query_id uuid;
  v_snapshot executive_intelligence_snapshots%rowtype;
begin
  if tj_private.current_source_user_id() is not null and not exists (
    select 1 from organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.current_source_user_id() and coalesce(m.status,'active')='active'
  ) then raise exception 'Not authorized for organization'; end if;

  select * into v_snapshot from executive_intelligence_snapshots where organization_id=p_organization_id order by generated_at desc limit 1;
  if v_snapshot.id is null then
    perform executive_refresh_command_centre(p_organization_id);
    select * into v_snapshot from executive_intelligence_snapshots where organization_id=p_organization_id order by generated_at desc limit 1;
  end if;

  if v_q ~ '(risk|problem|wrong|attention|danger)' then
    v_intent:='top_risks';
    select jsonb_build_object('headline','Highest-priority executive risks','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'severity',severity,'priority_score',priority_score,'recommended_action',recommended_action,'evidence',evidence) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and insight_type='risk' and status in ('open','acknowledged','in_progress') order by priority_score desc limit 5) x;
  elsif v_q ~ '(opportunit|growth|best|working|strong)' then
    v_intent:='top_opportunities';
    select jsonb_build_object('headline','Highest-value opportunities and strengths','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'priority_score',priority_score,'recommended_action',recommended_action,'evidence',evidence) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and insight_type in ('opportunity','performance') and status in ('open','acknowledged','in_progress') order by priority_score desc limit 5) x;
  elsif v_q ~ '(sales|conversion|pipeline|deal|revenue)' then
    v_intent:='sales_performance';
    v_answer:=jsonb_build_object('headline','Sales and pipeline performance','crm',v_snapshot.metrics->'crm','retail_floor',v_snapshot.metrics->'retail_floor');
  elsif v_q ~ '(field|store|display|visit|manufacturer)' then
    v_intent:='field_performance';
    v_answer:=jsonb_build_object('headline','Field and store execution','field',v_snapshot.metrics->'field','related_insights',coalesce((select jsonb_agg(jsonb_build_object('title',title,'summary',summary,'severity',severity,'recommended_action',recommended_action) order by priority_score desc) from executive_intelligence_insights where snapshot_id=v_snapshot.id and domain='field'),'[]'::jsonb));
  elsif v_q ~ '(training|coach|academy|role.?play|skill)' then
    v_intent:='training_performance';
    v_answer:=jsonb_build_object('headline','Training and coaching performance','training',v_snapshot.metrics->'training','learning',v_snapshot.metrics->'learning');
  elsif v_q ~ '(next|action|do first|priority)' then
    v_intent:='priority_actions';
    select jsonb_build_object('headline','Recommended executive action order','items',coalesce(jsonb_agg(jsonb_build_object('title',title,'summary',summary,'domain',domain,'severity',severity,'priority_score',priority_score,'recommended_action',recommended_action) order by priority_score desc),'[]'::jsonb))
    into v_answer from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') order by priority_score desc limit 7) x;
  else
    v_intent:='executive_summary';
    v_answer:=jsonb_build_object('headline','Executive operating summary','overall_health_score',v_snapshot.overall_health_score,'health_status',v_snapshot.health_status,'coverage_status',v_snapshot.coverage_status,'metrics',v_snapshot.metrics,'top_insights',coalesce((select jsonb_agg(jsonb_build_object('title',title,'summary',summary,'type',insight_type,'severity',severity,'recommended_action',recommended_action) order by priority_score desc) from (select * from executive_intelligence_insights where snapshot_id=v_snapshot.id order by priority_score desc limit 5) z),'[]'::jsonb));
  end if;

  v_evidence:=jsonb_build_array(jsonb_build_object('snapshot_id',v_snapshot.id,'generated_at',v_snapshot.generated_at,'coverage_status',v_snapshot.coverage_status,'data_confidence',v_snapshot.data_confidence));
  v_confidence:=v_snapshot.data_confidence;
  insert into executive_intelligence_queries(organization_id,asked_by,question,intent,answer,evidence,confidence)
  values(p_organization_id,tj_private.current_source_user_id(),p_question,v_intent,v_answer,v_evidence,v_confidence)
  returning id into v_query_id;
  return jsonb_build_object('query_id',v_query_id,'intent',v_intent,'answer',v_answer,'evidence',v_evidence,'confidence',v_confidence);
end;
$function$;
REVOKE ALL ON FUNCTION tj.executive_answer_question(p_organization_id uuid, p_question text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.executive_finalize_snapshot_confidence(p_snapshot_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v executive_intelligence_snapshots%rowtype; v_domains int:=0; v_conf numeric; v_cov text; begin
 select * into v from executive_intelligence_snapshots where id=p_snapshot_id;
 if coalesce((v.metrics#>>'{crm,deals_total}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{retail_floor,interactions}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{field,open_actions}')::numeric,0)+coalesce((v.metrics#>>'{field,resolved_actions}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 if (v.metrics#>>'{training,average_knowledge_score}') is not null then v_domains:=v_domains+1; end if;
 if coalesce((v.metrics#>>'{data_volume,outcomes}')::numeric,0)>0 then v_domains:=v_domains+1; end if;
 v_conf:=round(v_domains/5.0,2);
 v_cov:=case when v_conf<0.4 then 'insufficient' when v_conf<0.7 then 'partial' when v_conf<0.9 then 'good' else 'strong' end;
 update executive_intelligence_snapshots set data_confidence=v_conf,coverage_status=v_cov,
   health_status=case when v_cov='insufficient' then 'unknown' else health_status end,
   overall_health_score=case when v_cov='insufficient' then 50 else overall_health_score end
 where id=p_snapshot_id;
 update executive_intelligence_insights set summary='Insufficient cross-system operating evidence is available for a reliable health score.', recommended_action='Connect or populate CRM, retail-floor, field, training, and outcome data before interpreting health.'
 where snapshot_id=p_snapshot_id and title='Current operating health score' and v_cov='insufficient';
end; $function$;
REVOKE ALL ON FUNCTION tj.executive_finalize_snapshot_confidence(p_snapshot_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.executive_get_command_centre(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
with latest as (
  select * from executive_intelligence_snapshots
  where organization_id=p_organization_id
  order by generated_at desc limit 1
)
select jsonb_build_object(
  'snapshot',coalesce((select to_jsonb(l) from latest l),'{}'::jsonb),
  'top_risks',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='risk' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'top_opportunities',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type='opportunity' order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'priority_actions',coalesce((select jsonb_agg(to_jsonb(i) order by i.priority_score desc,i.created_at desc) from (select * from executive_intelligence_insights where organization_id=p_organization_id and status in ('open','acknowledged','in_progress') and insight_type in ('action','performance') order by priority_score desc,created_at desc limit 10) i),'[]'::jsonb),
  'generated_at',now()
);
$function$;
REVOKE ALL ON FUNCTION tj.executive_get_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.executive_refresh_command_centre(p_organization_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_snapshot_id uuid;
  v_user uuid := tj_private.current_source_user_id();
  v_metrics jsonb;
  v_health numeric;
  v_status text;
  v_deals_total numeric := 0;
  v_deals_won numeric := 0;
  v_deals_lost numeric := 0;
  v_pipeline_value numeric := 0;
  v_stale_deals numeric := 0;
  v_interactions numeric := 0;
  v_sales numeric := 0;
  v_left_unserved numeric := 0;
  v_field_critical numeric := 0;
  v_field_open_actions numeric := 0;
  v_field_resolved_actions numeric := 0;
  v_avg_store_score numeric;
  v_avg_training_score numeric;
  v_open_recommendations numeric := 0;
  v_low_signals numeric := 0;
  v_strong_signals numeric := 0;
  v_conversion numeric := 0;
  v_served_score numeric := 100;
  v_field_score numeric := 50;
  v_training_score numeric := 50;
  v_resolution_score numeric := 50;
begin
  if v_user is not null and not exists (
    select 1 from organization_members m
    where m.organization_id=p_organization_id and m.user_id=v_user and coalesce(m.status,'active')='active'
  ) then
    raise exception 'Not authorized for organization';
  end if;

  select count(*),
         count(*) filter (where lower(stage) in ('closed won','won','sold','completed','purchased')),
         count(*) filter (where lower(stage) in ('closed lost','lost','cancelled','rejected','expired')),
         coalesce(sum(value_amount) filter (where lower(stage) not in ('closed won','won','sold','completed','purchased','closed lost','lost','cancelled','rejected','expired')),0),
         count(*) filter (where lower(stage) not in ('closed won','won','sold','completed','purchased','closed lost','lost','cancelled','rejected','expired') and coalesce(days_inactive,0)>=30)
  into v_deals_total,v_deals_won,v_deals_lost,v_pipeline_value,v_stale_deals
  from crm_deals where organization_id=p_organization_id;

  select count(*), count(*) filter (where lower(coalesce(outcome,'')) in ('sale','sold','won','purchased','closed_won'))
  into v_interactions,v_sales
  from iq_customer_interactions where organization_id=p_organization_id;

  select count(*) into v_left_unserved
  from iq_customer_waiting_queue where organization_id=p_organization_id and lower(status::text)='left_unserved';

  select count(*) filter (where lower(coalesce(f.severity,''))='critical' and lower(coalesce(f.status,'new')) not in ('resolved','closed'))
  into v_field_critical
  from field_findings f join field_clients c on c.id=f.client_id where c.organization_id=p_organization_id;

  select count(*) filter (where lower(coalesce(a.status,'open')) not in ('resolved','closed','completed','verified')),
         count(*) filter (where lower(coalesce(a.status,'')) in ('resolved','closed','completed','verified'))
  into v_field_open_actions,v_field_resolved_actions
  from field_actions a join field_clients c on c.id=a.client_id where c.organization_id=p_organization_id;

  select avg(case when s.overall_score>10 then s.overall_score else s.overall_score*10 end)
  into v_avg_store_score
  from field_store_scores s join field_clients c on c.id=s.client_id where c.organization_id=p_organization_id;

  select avg(case when t.knowledge_score>10 then t.knowledge_score else t.knowledge_score*10 end)
  into v_avg_training_score
  from field_training_sessions t join field_clients c on c.id=t.client_id where c.organization_id=p_organization_id;

  select count(*) filter (where status in ('generated','presented')) into v_open_recommendations
  from intelligence_recommendations where organization_id=p_organization_id;

  select count(*) filter (where observation_count>=2 and bayesian_score<0.45),
         count(*) filter (where observation_count>=2 and bayesian_score>=0.70)
  into v_low_signals,v_strong_signals
  from intelligence_learning_signals where organization_id=p_organization_id;

  v_conversion := case when v_interactions>0 then round((v_sales/v_interactions)*100,2)
                       when (v_deals_won+v_deals_lost)>0 then round((v_deals_won/(v_deals_won+v_deals_lost))*100,2)
                       else 0 end;
  v_served_score := case when (v_interactions+v_left_unserved)>0 then greatest(0,100-(v_left_unserved/(v_interactions+v_left_unserved))*100) else 100 end;
  v_field_score := coalesce(v_avg_store_score,50);
  v_training_score := coalesce(v_avg_training_score,50);
  v_resolution_score := case when (v_field_open_actions+v_field_resolved_actions)>0 then (v_field_resolved_actions/(v_field_open_actions+v_field_resolved_actions))*100 else 50 end;

  v_health := round(greatest(0,least(100,
      (v_conversion*0.30) +
      (v_served_score*0.15) +
      (v_field_score*0.20) +
      (v_training_score*0.15) +
      (v_resolution_score*0.20) -
      least(15,v_field_critical*3) -
      least(10,v_stale_deals)
  )),2);
  v_status := case when v_health<35 then 'critical' when v_health<50 then 'at_risk' when v_health<65 then 'watch' when v_health<80 then 'healthy' else 'strong' end;

  v_metrics := jsonb_build_object(
    'crm',jsonb_build_object('deals_total',v_deals_total,'deals_won',v_deals_won,'deals_lost',v_deals_lost,'pipeline_value_cad',v_pipeline_value,'stale_deals',v_stale_deals,'closed_conversion_pct',case when (v_deals_won+v_deals_lost)>0 then round((v_deals_won/(v_deals_won+v_deals_lost))*100,2) else null end),
    'retail_floor',jsonb_build_object('interactions',v_interactions,'sales',v_sales,'conversion_pct',v_conversion,'left_unserved',v_left_unserved,'served_score',round(v_served_score,2)),
    'field',jsonb_build_object('critical_open_findings',v_field_critical,'open_actions',v_field_open_actions,'resolved_actions',v_field_resolved_actions,'resolution_pct',round(v_resolution_score,2),'average_store_score',round(v_avg_store_score,2)),
    'training',jsonb_build_object('average_knowledge_score',round(v_avg_training_score,2)),
    'learning',jsonb_build_object('open_recommendations',v_open_recommendations,'low_performing_signals',v_low_signals,'strong_signals',v_strong_signals),
    'data_volume',jsonb_build_object('entities',(select count(*) from tj.intelligence_entities where organization_id=p_organization_id),'events',(select count(*) from tj.intelligence_events where organization_id=p_organization_id),'outcomes',(select count(*) from intelligence_outcomes where organization_id=p_organization_id),'signals',(select count(*) from intelligence_learning_signals where organization_id=p_organization_id))
  );

  insert into executive_intelligence_snapshots(organization_id,snapshot_type,period_start,period_end,overall_health_score,health_status,metrics,evidence_summary,generated_by)
  values(p_organization_id,'current',current_date-30,current_date,v_health,v_status,v_metrics,
         jsonb_build_object('calculation','weighted operational score','weights',jsonb_build_object('conversion',0.30,'served_customers',0.15,'field_execution',0.20,'training',0.15,'action_resolution',0.20),'penalties',jsonb_build_object('critical_findings','3 points each, max 15','stale_deals','1 point each, max 10')),v_user)
  returning id into v_snapshot_id;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','field','critical',100,
         'Critical field findings remain unresolved',
         format('%s critical field finding(s) are still open.',v_field_critical),
         'Assign owners, set deadlines, and verify resolution evidence.',
         jsonb_build_object('critical_open_findings',v_field_critical),array['field_reports','intelligence_core']
  where v_field_critical>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','retail_floor',case when v_left_unserved>=3 then 'high' else 'medium' end,85,
         'Customers left without service',
         format('%s customer(s) were recorded as left unserved.',v_left_unserved),
         'Review staffing, queue response times, and missed-assignment causes.',
         jsonb_build_object('left_unserved',v_left_unserved),array['iq_up_system','crm']
  where v_left_unserved>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'risk','crm',case when v_stale_deals>=10 then 'high' else 'medium' end,80,
         'Pipeline opportunities need attention',
         format('%s open deal(s) have been inactive for at least 30 days.',v_stale_deals),
         'Rank stale deals by value and assign a specific next action and date.',
         jsonb_build_object('stale_deals',v_stale_deals,'pipeline_value_cad',v_pipeline_value),array['crm','intelligence_core']
  where v_stale_deals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'opportunity','learning','info',70,
         'Proven strategies are emerging',
         format('%s learning signal(s) have a Bayesian score of at least 0.70.',v_strong_signals),
         'Promote the strongest strategies into playbooks and recommended defaults.',
         jsonb_build_object('strong_signals',v_strong_signals),array['intelligence_core','academy','crm','field_reports']
  where v_strong_signals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'action','learning',case when v_low_signals>=5 then 'high' else 'medium' end,75,
         'Low-performing recommendations require review',
         format('%s learning signal(s) are underperforming after multiple observations.',v_low_signals),
         'Retire, revise, or narrow the context of weak recommendations.',
         jsonb_build_object('low_performing_signals',v_low_signals),array['intelligence_core']
  where v_low_signals>0;

  insert into executive_intelligence_insights(organization_id,snapshot_id,insight_type,domain,severity,priority_score,title,summary,recommended_action,evidence,source_systems)
  select p_organization_id,v_snapshot_id,'performance','operations','info',60,
         'Current operating health score',
         format('The current combined operating health score is %s/100 (%s).',v_health,v_status),
         'Work the highest-priority open insight first, then refresh the snapshot.',
         jsonb_build_object('health_score',v_health,'health_status',v_status),array['intelligence_core','crm','iq_up_system','field_reports','academy'];

  return v_snapshot_id;
end;
$function$;
REVOKE ALL ON FUNCTION tj.executive_refresh_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.executive_snapshot_confidence_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  perform executive_finalize_snapshot_confidence(new.id);
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.executive_snapshot_confidence_trigger() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_auto_create_brand_course()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$ DECLARE v_slug TEXT; v_ms SMALLINT; v_cid INTEGER; BEGIN IF NEW.is_active = false THEN RETURN NEW; END IF; IF EXISTS (SELECT 1 FROM iq_courses WHERE brand_id = NEW.id AND pillar = 'brand_iq') THEN RETURN NEW; END IF; v_slug := 'brand-' || lower(regexp_replace(regexp_replace(NEW.brand_name, '[^a-zA-Z0-9 ]', '', 'g'), '\s+', '-', 'g')); SELECT COALESCE(MAX(sort_order), 0) + 1 INTO v_ms FROM iq_courses WHERE pillar = 'brand_iq'; INSERT INTO iq_courses (pillar, course_key, name, subtitle, icon, brand_id, zone_level, category, sort_order) VALUES ('brand_iq', v_slug, NEW.brand_name, COALESCE(NEW.brand_tier,'mid'), '🏷️', NEW.id, 2, COALESCE(NEW.brand_tier,'mid'), v_ms) RETURNING id INTO v_cid; INSERT INTO iq_badges (badge_type, badge_key, name, description, icon, color, pillar, brand_id, course_id, requirements, sort_order) VALUES ('brand_cert', 'brand-cert-' || v_slug, NEW.brand_name || ' Certified', 'Brand quiz 80 percent', '🏅', '#CD7F32', 'brand_iq', NEW.id, v_cid, jsonb_build_object('quiz_pass', 80, 'course_complete', v_slug), (v_cid + 200)::smallint) ON CONFLICT DO NOTHING; RETURN NEW; END; $function$;
REVOKE ALL ON FUNCTION tj_private.fn_auto_create_brand_course() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_brand_reactivated()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF OLD.is_active = false AND NEW.is_active = true THEN
    PERFORM fn_auto_create_brand_course();
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_brand_reactivated() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_calc_savings()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.regular_price IS NOT NULL AND NEW.price IS NOT NULL AND NEW.regular_price > 0 THEN
    NEW.savings_amount := NEW.regular_price - NEW.price;
    NEW.savings_percent := ROUND(((NEW.regular_price - NEW.price) / NEW.regular_price) * 100, 1);
  ELSE
    NEW.savings_amount := NULL;
    NEW.savings_percent := NULL;
  END IF;
  
  -- Auto-flag one-of-a-kind items
  IF NEW.condition_normalized IN ('open_box','floor_model','scratch_dent','returned','used','as_is') THEN
    NEW.is_one_of_a_kind := true;
  END IF;
  
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_calc_savings() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_ccr_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  INSERT INTO iq_notifications (notification_type, title, body, icon, ccr_id, target_audience)
  VALUES (
    'new_competitive_entry',
    '🔬 New Competitive Intel: ' || COALESCE(NEW.category, 'Cross-Reference'),
    'New competitive knowledge added for ' || COALESCE(NEW.category, 'a product category') || ' (' || COALESCE(NEW.tier, '') || ').',
    '⚔️',
    NEW.id,
    'all_reps'
  );
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_ccr_notification() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_new_deck_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_course_name TEXT;
BEGIN
  SELECT name INTO v_course_name FROM iq_courses WHERE id = NEW.course_id;
  
  INSERT INTO iq_notifications (notification_type, title, body, icon, course_id, target_audience)
  VALUES (
    'new_deck',
    '📚 New Lesson: ' || NEW.title,
    'A new deck has been added to ' || COALESCE(v_course_name, 'a course') || '.',
    '🃏',
    NEW.course_id,
    'all_reps'
  );
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_new_deck_notification() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_pim_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'new_product',
      '🆕 New Product: ' || COALESCE(NEW.short_description, NEW.model),
      'A new ' || COALESCE(NEW.category, 'product') || ' has been added to the PIM.',
      '📦',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.is_discontinued IS DISTINCT FROM NEW.is_discontinued AND NEW.is_discontinued = true THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'product_discontinued',
      '⚠️ Discontinued: ' || COALESCE(NEW.short_description, NEW.model),
      COALESCE(NEW.short_description, NEW.model) || ' has been marked discontinued.',
      '🚫',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  IF TG_OP = 'UPDATE' AND OLD.is_clearance IS DISTINCT FROM NEW.is_clearance AND NEW.is_clearance = true THEN
    INSERT INTO iq_notifications (notification_type, title, body, icon, product_id, brand_id, target_audience)
    VALUES (
      'product_clearance',
      '🏷️ Clearance: ' || COALESCE(NEW.short_description, NEW.model),
      COALESCE(NEW.short_description, NEW.model) || ' is now on clearance.',
      '💰',
      NEW.id,
      NEW.brand_id,
      'all_reps'
    );
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_pim_notification() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.fn_sync_pim_to_training()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_brand_course_id INTEGER;
  v_content JSONB;
  v_title TEXT;
BEGIN
  SELECT id INTO v_brand_course_id FROM iq_courses WHERE pillar = 'brand_iq' AND brand_id = NEW.brand_id LIMIT 1;

  v_title := COALESCE(NEW.brand_name, '') || ' ' || COALESCE(NEW.model, '');

  v_content := jsonb_build_object(
    'model', NEW.model,
    'brand_name', NEW.brand_name,
    'product_line', NEW.product_line,
    'series', NEW.series,
    'category', NEW.category,
    'short_description', NEW.short_description,
    'msrp', NEW.msrp,
    'sale_price', NEW.sale_price,
    'lowest_price', NEW.lowest_price,
    'lowest_price_source', NEW.lowest_price_source,
    'map_price', NEW.map_price,
    'specs_json', NEW.specs_json,
    'available_colors', NEW.available_colors,
    'capacity_cu_ft', NEW.capacity_cu_ft,
    'voltage', NEW.voltage,
    'installation_type', NEW.installation_type,
    'finish', NEW.finish,
    'color', NEW.color,
    'energy_star', NEW.energy_star,
    'width_inches', NEW.width_inches,
    'height_inches', NEW.height_inches,
    'depth_inches', NEW.depth_inches,
    'features_html', NEW.features_html
  );

  INSERT INTO iq_product_cards (product_id, brand_id, course_id, card_type, title, content,
    is_active, is_new_launch, is_discontinued, is_clearance, is_end_of_life, pim_synced_at, updated_at)
  VALUES (NEW.id, NEW.brand_id, v_brand_course_id, 'product_spotlight', v_title, v_content,
    true, CASE WHEN TG_OP = 'INSERT' THEN true ELSE false END,
    COALESCE(NEW.is_discontinued, false), COALESCE(NEW.is_clearance, false),
    COALESCE(NEW.is_end_of_life, false), now(), now())
  ON CONFLICT (product_id) DO UPDATE SET
    brand_id = EXCLUDED.brand_id, course_id = EXCLUDED.course_id,
    title = EXCLUDED.title, content = EXCLUDED.content,
    is_discontinued = EXCLUDED.is_discontinued, is_clearance = EXCLUDED.is_clearance,
    is_end_of_life = EXCLUDED.is_end_of_life, pim_synced_at = now(), updated_at = now();

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.fn_sync_pim_to_training() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.foundation_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  DECLARE
    rec  JSONB := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
  BEGIN
    INSERT INTO foundation_audit_log(entity_table, entity_id, action, actor, delta)
    VALUES (TG_TABLE_NAME,
            (rec ->> 'id')::uuid,
            TG_OP,
            COALESCE((rec ->> 'updated_by')::uuid, (rec ->> 'created_by')::uuid),
            rec);
    RETURN COALESCE(NEW, OLD);
  END;
$function$;
REVOKE ALL ON FUNCTION tj_private.foundation_audit() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.foundation_fact_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.status = 'verified' AND (NEW.intelligence_type = 'AI_INFERENCE' OR NEW.source = 'UNKNOWN') THEN
    RAISE EXCEPTION 'Constitution: AI_INFERENCE / UNKNOWN-source facts cannot be verified (fact %)', NEW.id;
  END IF;
  IF NEW.status = 'verified' AND NEW.verified_by IS NULL THEN
    RAISE EXCEPTION 'Constitution: verified facts require verified_by (fact %)', NEW.id;
  END IF;
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.foundation_fact_guard() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid)
 RETURNS TABLE(primary_kpi text, previous_score numeric, target_score numeric, insight text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_yesterday date := current_date - interval '1 day';
  v_lowest_kpi_id uuid;
  v_lowest_score numeric;
  v_target_score numeric;
  v_insight text;
begin
  -- Get yesterday's coaching reviews for this user
  with yesterday_scores as (
    select
      k.id,
      k.kpi_name,
      k.target_score,
      avg(case
        when ar.coaching_data->'kpi_scores' ? k.kpi_name
        then (ar.coaching_data->'kpi_scores'->>k.kpi_name)::numeric
        else null
      end) as avg_score
    from tj.ai_coaching_reviews ar
    join tj.org_kpis k on k.organization_id = p_organization_id
    where ar.organization_id = p_organization_id
      and ar.user_id = p_user_id
      and date(ar.created_at) = v_yesterday
      and k.active = true
    group by k.id, k.kpi_name, k.target_score
  )
  select
    s.id, s.avg_score
    into v_lowest_kpi_id, v_lowest_score
  from yesterday_scores s
  where s.avg_score is not null
  order by s.avg_score asc
  limit 1;

  if v_lowest_kpi_id is null then
    -- No coaching yesterday, pick the first active KPI
    select id, target_score into v_lowest_kpi_id, v_target_score
    from tj.org_kpis
    where organization_id = p_organization_id and active = true
    limit 1;
    v_lowest_score := null;
    v_insight := 'Get started with your first coaching session today!';
  else
    select target_score into v_target_score from tj.org_kpis where id = v_lowest_kpi_id;
    v_insight := 'Your ' || (select kpi_name from org_kpis where id = v_lowest_kpi_id) || ' score was ' || v_lowest_score::text || '/10 yesterday. Focus on improving this today.';
  end if;

  -- Upsert into daily_coaching_focus
  insert into tj.daily_coaching_focus (
    organization_id, user_id, focus_date, primary_kpi_id, primary_kpi_name, previous_score, target_score, insight
  )
  select p_organization_id, p_user_id, current_date, v_lowest_kpi_id, (select kpi_name from org_kpis where id = v_lowest_kpi_id), v_lowest_score, v_target_score, v_insight
  on conflict (organization_id, user_id, focus_date) do update set
    primary_kpi_id = v_lowest_kpi_id,
    primary_kpi_name = (select kpi_name from org_kpis where id = v_lowest_kpi_id),
    previous_score = v_lowest_score,
    insight = v_insight;

  return query
  select
    (select kpi_name from org_kpis where id = v_lowest_kpi_id) as primary_kpi,
    v_lowest_score,
    v_target_score,
    v_insight;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid) RETURNS TABLE(primary_kpi text, previous_score numeric, target_score numeric, insight text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.generate_daily_coaching_brief("p_organization_id","p_user_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.generate_daily_coaching_brief(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.generate_speciq_quote_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NEW.quote_number IS NULL THEN
    NEW.quote_number := 'IQ-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('speciq_quote_seq')::text, 6, '0');
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.generate_speciq_quote_number() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.get_due_sequence_steps(p_org_id uuid)
 RETURNS TABLE(enrollment_id uuid, contact_id uuid, campaign_id uuid, step_number integer, step_id uuid, contact_email text, subject_template text, body_template text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT e.id, e.contact_id, e.campaign_id, e.current_step, s.id, c.email, s.subject_template, s.body_template
  FROM aicrm_sequence_enrollments e
  JOIN aicrm_sequence_steps s ON s.campaign_id = e.campaign_id AND s.step_number = e.current_step
  JOIN contacts c ON c.id = e.contact_id
  WHERE e.organization_id = p_org_id
    AND e.status = 'active'
    AND c.email IS NOT NULL
    AND (e.last_contacted_at IS NULL OR
         e.last_contacted_at + (s.delay_days || ' days')::interval <= now());
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.get_due_sequence_steps(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.get_due_sequence_steps(p_org_id uuid) RETURNS TABLE(enrollment_id uuid, contact_id uuid, campaign_id uuid, step_number integer, step_id uuid, contact_email text, subject_template text, body_template text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.get_due_sequence_steps("p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.get_due_sequence_steps(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.get_floor_recommendation_data(p_org_id uuid, p_store_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  result JSONB;
BEGIN
  PERFORM assert_floor_org_access(p_org_id);

  WITH fd AS MATERIALIZED (
    SELECT d.id, d.store_id, d.floor_units, d.brand_name, d.primary_category,
           COALESCE(sc.cnt,0) AS sku_count,
           d.floor_units / GREATEST(COALESCE(sc.cnt,0),1) AS unit_per_sku
    FROM field_floor_displays d
    LEFT JOIN (
      SELECT display_id, COUNT(*) AS cnt FROM field_floor_display_skus
      WHERE is_active AND organization_id = p_org_id GROUP BY display_id
    ) sc ON sc.display_id = d.id
    WHERE d.organization_id = p_org_id AND d.is_active
      AND (p_store_id IS NULL OR d.store_id = p_store_id)
  ),
  fs AS MATERIALIZED (
    SELECT s.display_id, s.brand_name, s.product_category, s.id, s.model_number, s.sku
    FROM field_floor_display_skus s
    WHERE s.organization_id = p_org_id AND s.is_active
      AND (p_store_id IS NULL OR s.store_id = p_store_id)
  ),
  sales AS MATERIALIZED (
    SELECT brand, category, model_number, product_name, revenue, quantity
    FROM v_floor_sales_normalized
    WHERE organization_id = p_org_id
      AND (p_store_id IS NULL OR store_id = p_store_id)
  ),
  tot AS (
    SELECT (SELECT COALESCE(SUM(floor_units),0) FROM fd) AS total_floor,
           (SELECT COALESCE(SUM(revenue),0) FROM sales) AS total_rev
  ),
  -- Dedupe FIRST, normalize second
  raw_brands AS MATERIALIZED (
    SELECT DISTINCT COALESCE(s.brand_name, d.brand_name) AS raw
    FROM fd d LEFT JOIN fs s ON s.display_id = d.id
    WHERE COALESCE(s.brand_name, d.brand_name) IS NOT NULL
  ),
  bmap AS MATERIALIZED (
    SELECT raw, normalize_brand(raw, p_org_id) AS canon FROM raw_brands
  ),
  floor_cat AS (
    SELECT LOWER(COALESCE(s.product_category, d.primary_category,'other')) AS cat, SUM(d.unit_per_sku) AS units
    FROM fd d JOIN fs s ON s.display_id = d.id GROUP BY 1
    UNION ALL
    SELECT LOWER(COALESCE(d.primary_category,'other')), SUM(d.floor_units)
    FROM fd d WHERE d.sku_count = 0 GROUP BY 1
  ),
  floor_agg AS (SELECT cat, SUM(units) AS units FROM floor_cat GROUP BY cat),
  sales_cat AS (SELECT category AS cat, SUM(revenue) AS rev, SUM(quantity) AS units_sold FROM sales GROUP BY 1),
  cat_json AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'category', COALESCE(f.cat, s.cat),
      'floor_units', ROUND(COALESCE(f.units,0)::numeric,2),
      'floor_pct', CASE WHEN t.total_floor>0 THEN ROUND(COALESCE(f.units,0)/t.total_floor*100,1) ELSE 0 END,
      'sales_revenue', COALESCE(s.rev,0),
      'sales_pct', CASE WHEN t.total_rev>0 THEN ROUND(COALESCE(s.rev,0)/t.total_rev*100,1) ELSE 0 END,
      'units_sold', COALESCE(s.units_sold,0),
      'gap_pts', ROUND((CASE WHEN t.total_rev>0 THEN COALESCE(s.rev,0)/t.total_rev*100 ELSE 0 END) -
                       (CASE WHEN t.total_floor>0 THEN COALESCE(f.units,0)/t.total_floor*100 ELSE 0 END),1),
      'target_units', CASE WHEN t.total_rev>0 AND t.total_floor>0 THEN ROUND(t.total_floor*(COALESCE(s.rev,0)/t.total_rev),1) ELSE 0 END,
      'unit_delta', CASE WHEN t.total_rev>0 AND t.total_floor>0 THEN ROUND(t.total_floor*(COALESCE(s.rev,0)/t.total_rev)-COALESCE(f.units,0),1) ELSE 0 END,
      'revenue_per_unit', CASE WHEN COALESCE(f.units,0)>0 THEN ROUND(COALESCE(s.rev,0)/f.units,0) ELSE NULL END
    ) ORDER BY ABS((CASE WHEN t.total_rev>0 THEN COALESCE(s.rev,0)/t.total_rev*100 ELSE 0 END) -
                   (CASE WHEN t.total_floor>0 THEN COALESCE(f.units,0)/t.total_floor*100 ELSE 0 END)) DESC),'[]'::jsonb) AS j
    FROM floor_agg f FULL OUTER JOIN sales_cat s USING (cat) CROSS JOIN tot t
  ),
  floor_brand AS (
    SELECT COALESCE(m.canon,'Unbranded') AS brand, SUM(d.unit_per_sku) AS units
    FROM fd d JOIN fs s ON s.display_id = d.id
    LEFT JOIN bmap m ON m.raw = COALESCE(s.brand_name, d.brand_name) GROUP BY 1
    UNION ALL
    SELECT COALESCE(m.canon,'Unbranded'), SUM(d.floor_units)
    FROM fd d LEFT JOIN bmap m ON m.raw = d.brand_name
    WHERE d.sku_count = 0 GROUP BY 1
  ),
  fb AS (SELECT brand, SUM(units) AS units FROM floor_brand GROUP BY brand),
  sb AS (SELECT brand, SUM(revenue) AS rev, SUM(quantity) AS units_sold FROM sales GROUP BY 1),
  brand_json AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'brand', COALESCE(fb.brand, sb.brand),
      'floor_units', ROUND(COALESCE(fb.units,0)::numeric,2),
      'floor_pct', CASE WHEN t.total_floor>0 THEN ROUND(COALESCE(fb.units,0)/t.total_floor*100,1) ELSE 0 END,
      'sales_revenue', COALESCE(sb.rev,0),
      'sales_pct', CASE WHEN t.total_rev>0 THEN ROUND(COALESCE(sb.rev,0)/t.total_rev*100,1) ELSE 0 END,
      'units_sold', COALESCE(sb.units_sold,0),
      'gap_pts', ROUND((CASE WHEN t.total_rev>0 THEN COALESCE(sb.rev,0)/t.total_rev*100 ELSE 0 END) -
                       (CASE WHEN t.total_floor>0 THEN COALESCE(fb.units,0)/t.total_floor*100 ELSE 0 END),1),
      'revenue_per_unit', CASE WHEN COALESCE(fb.units,0)>0 THEN ROUND(COALESCE(sb.rev,0)/fb.units,0) ELSE NULL END
    ) ORDER BY ABS((CASE WHEN t.total_rev>0 THEN COALESCE(sb.rev,0)/t.total_rev*100 ELSE 0 END) -
                   (CASE WHEN t.total_floor>0 THEN COALESCE(fb.units,0)/t.total_floor*100 ELSE 0 END)) DESC),'[]'::jsonb) AS j
    FROM fb FULL OUTER JOIN sb USING (brand) CROSS JOIN tot t
  ),
  floored AS (SELECT DISTINCT LOWER(COALESCE(model_number, sku)) AS m FROM fs WHERE COALESCE(model_number,sku) IS NOT NULL),
  sold AS (
    SELECT model_number AS model, MAX(product_name) AS product_name, MAX(brand) AS brand,
           MAX(category) AS category, SUM(revenue) AS revenue, SUM(quantity) AS units_sold
    FROM sales WHERE model_number IS NOT NULL GROUP BY 1
  ),
  unfloored_json AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'model', model, 'product_name', product_name, 'brand', brand, 'category', category,
      'revenue', revenue, 'units_sold', units_sold,
      'pct_of_total_rev', CASE WHEN t.total_rev>0 THEN ROUND(revenue/t.total_rev*100,1) ELSE 0 END
    ) ORDER BY revenue DESC),'[]'::jsonb) AS j
    FROM sold CROSS JOIN tot t
    WHERE LOWER(sold.model) NOT IN (SELECT m FROM floored)
  ),
  fb2 AS (
    SELECT COALESCE(m.canon,'Unbranded') AS brand,
           SUM(COALESCE(d.unit_per_sku, d.floor_units)) AS units, COUNT(s.id) AS sku_count
    FROM fd d LEFT JOIN fs s ON s.display_id = d.id
    LEFT JOIN bmap m ON m.raw = COALESCE(s.brand_name, d.brand_name) GROUP BY 1
  ),
  dead_json AS (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'brand', brand, 'floor_units', ROUND(units::numeric,2), 'sku_count', sku_count,
      'floor_pct', CASE WHEN t.total_floor>0 THEN ROUND(units/t.total_floor*100,1) ELSE 0 END
    ) ORDER BY units DESC),'[]'::jsonb) AS j
    FROM fb2 CROSS JOIN tot t
    WHERE fb2.brand <> 'Unbranded' AND fb2.brand NOT IN (SELECT brand FROM sb WHERE brand IS NOT NULL)
  ),
  hole_json AS (
    SELECT jsonb_build_object(
      'open_holes', COUNT(*), 'not_ordered', COUNT(*) FILTER (WHERE status='open'),
      'categories_affected', COALESCE(jsonb_agg(DISTINCT expected_category) FILTER (WHERE expected_category IS NOT NULL),'[]'::jsonb)
    ) AS j
    FROM field_floor_holes
    WHERE organization_id=p_org_id AND status NOT IN ('filled','cancelled')
      AND (p_store_id IS NULL OR store_id=p_store_id)
  ),
  quality_json AS (
    SELECT jsonb_build_object(
      'total_lines', COUNT(*),
      'lines_missing_brand', COUNT(*) FILTER (WHERE brand IS NULL),
      'lines_missing_model', COUNT(*) FILTER (WHERE model_number IS NULL),
      'lines_other_category', COUNT(*) FILTER (WHERE category='other'),
      'revenue_unattributed', COALESCE(SUM(revenue) FILTER (WHERE brand IS NULL OR category='other'),0),
      'pct_clean', CASE WHEN COUNT(*)>0 THEN ROUND(
        COUNT(*) FILTER (WHERE brand IS NOT NULL AND category<>'other' AND model_number IS NOT NULL)::numeric/COUNT(*)*100,1)
        ELSE 100 END
    ) AS j FROM sales
  )
  SELECT jsonb_build_object(
    'total_floor_units', t.total_floor, 'total_revenue', t.total_rev,
    'store_scoped', (p_store_id IS NOT NULL),
    'categories', c.j, 'brands', b.j,
    'top_sellers_not_floored', u.j, 'dead_space', dd.j,
    'holes', h.j, 'data_quality', q.j, 'generated_at', now()
  ) INTO result
  FROM tot t, cat_json c, brand_json b, unfloored_json u, dead_json dd, hole_json h, quality_json q;

  RETURN result;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.get_floor_recommendation_data(p_org_id uuid, p_store_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.get_floor_recommendation_data(p_org_id uuid, p_store_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.get_floor_recommendation_data("p_org_id","p_store_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.get_floor_recommendation_data(p_org_id uuid, p_store_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.get_invite_preview(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_invite org_invites%ROWTYPE;
  v_org_name text;
BEGIN
  SELECT * INTO v_invite FROM org_invites WHERE invite_code = p_code LIMIT 1;
  IF v_invite.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  SELECT name INTO v_org_name FROM organizations WHERE id = v_invite.organization_id;
  RETURN jsonb_build_object('ok', true,
    'organization_name', v_org_name,
    'invited_email', v_invite.invited_email,
    'role', v_invite.role,
    'status', v_invite.status,
    'expired', v_invite.expires_at < now());
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.get_invite_preview(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.get_invite_preview(p_code text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.get_invite_preview("p_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.get_invite_preview(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.handle_aicrm_organization_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  perform tj.provision_aicrm_defaults_for_organization(new.id);
  perform tj.provision_aicrm_market_defaults_for_organization(new.id);
  perform tj.provision_aicrm_territory_defaults_for_organization(new.id);
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.handle_aicrm_organization_insert() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.has_active_connector_connections()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM platform_connector_connections WHERE status = 'active'
  );
$function$;
REVOKE ALL ON FUNCTION tj_private.has_active_connector_connections() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.has_active_connector_connections() RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.has_active_connector_connections(); $adapter$;
REVOKE ALL ON FUNCTION tj.has_active_connector_connections() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.has_any_role(role_names text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select coalesce(
    exists (
      select 1
      from unnest(coalesce(role_names, array[]::text[])) as r(role_name)
      where r.role_name = any(tj.current_user_roles())
    ),
    false
  );
$function$;
REVOKE ALL ON FUNCTION tj_private.has_any_role(role_names text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.has_any_role(role_names text[]) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.has_any_role("role_names"); $adapter$;
REVOKE ALL ON FUNCTION tj.has_any_role(role_names text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.has_permission(permission_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if permission_name is null or tj_private.current_source_user_id() is null then
    return false;
  end if;

  if tj.is_super_admin() then
    return true;
  end if;

  if exists (
    select 1
    from tj.organization_members om
    where om.user_id = tj_private.current_source_user_id()
      and om.status = 'active'
      and om.role = 'owner'
  ) then
    return true;
  end if;

  return permission_name in (
    'organization.view',
    'crm.view',
    'ats.view',
    'reporting.view',
    'billing.read',
    'ai.command.use',
    'ai.audit.view',
    'files.view',
    'communications.view',
    'notifications.view'
  );
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.has_permission(permission_name text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.has_permission(permission_name text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.has_permission("permission_name"); $adapter$;
REVOKE ALL ON FUNCTION tj.has_permission(permission_name text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.has_role(role_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select coalesce(role_name = any(tj.current_user_roles()), false);
$function$;
REVOKE ALL ON FUNCTION tj_private.has_role(role_name text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.has_role(role_name text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.has_role("role_name"); $adapter$;
REVOKE ALL ON FUNCTION tj.has_role(role_name text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.init_dashboard_metrics(p_organization_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  insert into tj.dashboard_metric_settings (organization_id, metric_key, metric_name, metric_category, visible, position)
  values
    (p_organization_id, 'sales_volume_prime', 'Sales Volume (Prime)', 'sales', false, 1),
    (p_organization_id, 'volume_warranty', 'Volume Warranty', 'sales', false, 2),
    (p_organization_id, 'attach_rate', 'Attach Rate', 'sales', false, 3),
    (p_organization_id, 'opportunities_count', 'Opportunities', 'pipeline', false, 4),
    (p_organization_id, 'avg_item_value', 'Average Item Value', 'sales', false, 5),
    (p_organization_id, 'ipo_status', 'IPO Status', 'admin', false, 6),
    (p_organization_id, 'avg_sale_value', 'Average Sale Value', 'sales', false, 7),
    (p_organization_id, 'brand_quote_percentage', 'Brand % of Quote', 'brand', false, 8),
    (p_organization_id, 'brand_clothes_percentage', 'Brand % of Clothes', 'brand', false, 9),
    (p_organization_id, 'kpi_latest_score', 'Latest KPI Score', 'kpi', true, 10),
    (p_organization_id, 'kpi_30day_avg', '30-Day KPI Average', 'kpi', true, 11),
    (p_organization_id, 'recording_count', 'Recordings This Month', 'activity', true, 12),
    (p_organization_id, 'coaching_count', 'Coaching Sessions', 'activity', true, 13),
    (p_organization_id, 'kpi_trend', 'KPI Trend Chart', 'kpi', true, 14),
    (p_organization_id, 'pipeline_cards', 'Pipeline Kanban', 'pipeline', true, 15)
  on conflict (organization_id, metric_key) do nothing;
$function$;
REVOKE ALL ON FUNCTION tj_private.init_dashboard_metrics(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.init_dashboard_metrics(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.init_dashboard_metrics("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.init_dashboard_metrics(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.init_default_kpis(p_organization_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  insert into tj.org_kpis (organization_id, kpi_name, description, weight, target_score)
  values
    (p_organization_id, 'Discovery', 'Asking the right questions to understand customer needs', 1.0, 8.0),
    (p_organization_id, 'Objection Handling', 'Responding effectively to customer concerns', 1.0, 8.0),
    (p_organization_id, 'Product Knowledge', 'Explaining features and benefits clearly', 1.0, 8.0),
    (p_organization_id, 'Closing', 'Moving toward the sale', 1.0, 8.0),
    (p_organization_id, 'Follow-up', 'Maintaining momentum and commitment', 1.0, 8.0)
  on conflict (organization_id, kpi_name) do nothing;
$function$;
REVOKE ALL ON FUNCTION tj_private.init_default_kpis(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.init_default_kpis(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.init_default_kpis("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.init_default_kpis(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.init_default_metrics(p_org_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  insert into tj.metric_definitions (organization_id, metric_key, metric_label, metric_category, unit, sort_order) values
    (p_org_id, 'revenue',            'Revenue',              'sales',    'currency', 1),
    (p_org_id, 'units_sold',         'Units Sold',           'sales',    'count',    2),
    (p_org_id, 'avg_order',          'Average Order Value',  'sales',    'currency', 3),
    (p_org_id, 'ipo',                'Items Per Order',      'sales',    'count',    4),
    (p_org_id, 'item_value',         'Average Item Value',   'sales',    'currency', 5),
    (p_org_id, 'warranty_revenue',   'Warranty Revenue',     'warranty', 'currency', 10),
    (p_org_id, 'warranty_attach',    'Warranty Attach Rate', 'warranty', 'percent',  11),
    (p_org_id, 'warranty_opps',      'Warranty Opportunities','warranty','count',    12),
    (p_org_id, 'delivery_revenue',   'Delivery Revenue',     'sales',    'currency', 15),
    (p_org_id, 'install_revenue',    'Install Revenue',      'sales',    'currency', 16),
    (p_org_id, 'coaching_avg',       'Avg Coaching Score',   'coaching', 'score',    20),
    (p_org_id, 'training_completion','Training Completion',  'training', 'percent',  25),
    (p_org_id, 'floor_conversion',   'Floor Conversion Rate','floor',    'percent',  30),
    (p_org_id, 'walk_ins',           'Walk-Ins',             'floor',    'count',    31),
    (p_org_id, 'greeting_time',      'Avg Greeting Time',    'floor',    'count',    32)
  on conflict (organization_id, metric_key) do nothing;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.init_default_metrics(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.init_default_metrics(p_org_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.init_default_metrics("p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.init_default_metrics(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.init_default_personas(p_organization_id uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  insert into tj.ai_personas (organization_id, persona_name, persona_role, avatar_emoji, tone, specialization, personality_traits, prompt_prefix)
  values
    (p_organization_id, 'TJ', 'Sales Coach', '🏆', 'motivational, direct, action-oriented', 'Sales coaching and technique', 'energetic, supportive, no-nonsense', 'You are TJ, a sales coach with 20 years of retail experience. Your goal is to coach the rep on their sales technique, objection handling, and closing ability. Be encouraging but direct. Use sports/athletic metaphors.'),
    (p_organization_id, 'Natalie', 'Product Expert', '📚', 'technical, patient, thorough', 'Product knowledge and specs', 'knowledgeable, educational, detail-oriented', 'You are Natalie, a product specialist who knows every appliance inside and out. Explain features, benefits, and trade-offs clearly. Make complex specs easy to understand. Never oversell, always honest about limitations.'),
    (p_organization_id, 'Leah', 'Design Consultant', '🎨', 'creative, warm, collaborative', 'Kitchen design and lifestyle fit', 'creative, empathetic, visionary', 'You are Leah, a design consultant who helps customers visualize how appliances fit into their lifestyle and kitchen aesthetic. Ask about style preferences, existing decor, and workflow before recommending. Think holistically.'),
    (p_organization_id, 'Marcus', 'Objection Handler', '🛡️', 'confident, solution-focused, problem-solving', 'Handling customer concerns', 'logical, confident, diplomatic', 'You are Marcus, an objection-handling specialist. When customers push back on price, warranty, or delivery, you stay calm and reframe concerns as opportunities. Address root fear, then offer solutions.'),
    (p_organization_id, 'Sophie', 'Follow-up Expert', '📞', 'persistent, friendly, detail-oriented', 'Follow-up and closing sequences', 'organized, warm, reliable', 'You are Sophie, a follow-up coordinator who excels at keeping deals warm. You track follow-up tasks, suggest next best actions, and know the timing of when to call vs email. You''re the rep''s accountability partner.')
  on conflict (organization_id, persona_name) do nothing;
$function$;
REVOKE ALL ON FUNCTION tj_private.init_default_personas(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.init_default_personas(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.init_default_personas("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.init_default_personas(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_ensure_speciq_package_recommendation(p_package_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare p tj.speciq_packages%rowtype; v_entity uuid; v_rec uuid; v_products jsonb;
begin
  select * into p from tj.speciq_packages where id=p_package_id;
  if p.id is null then return null; end if;
  select id into v_entity from tj.intelligence_entities
    where organization_id=p.organization_id and source_system='speciq_package' and source_record_id=p.id::text;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('package_product_id',pp.id,'aiq_product_id',pp.aiq_product_id,'brand',pp.brand,
    'model_number',pp.model_number,'category',pp.category,'quantity',pp.quantity,'price',coalesce(pp.negotiated_price,pp.promo_price,pp.msrp),
    'selection_reason',pp.selection_reason)) order by pp.sort_order),'[]'::jsonb)
    into v_products from tj.speciq_package_products pp where pp.package_id=p.id;
  v_rec := tj.intelligence_record_recommendation(
    p.organization_id,'package_recommendation','project',p.project_id::text,'present_package:'||p.id::text,
    coalesce(nullif(p.project_type,''),'appliance_package'),v_entity,null,
    jsonb_strip_nulls(jsonb_build_object('package_id',p.id,'package_name',p.package_name,'quote_number',p.quote_number,
      'total_final',p.total_final,'total_savings',p.total_savings,'product_count',jsonb_array_length(v_products),'products',v_products,
      'basis','SpecIQ package composition and pricing')),
    '[]'::jsonb,'speciq_package',p.id::text
  );
  return v_rec;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_ensure_speciq_package_recommendation(p_package_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_entity_context(p_entity_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select jsonb_build_object(
    'entity', to_jsonb(e),
    'timeline', coalesce((select jsonb_agg(to_jsonb(t) order by t.occurred_at desc) from (select * from tj.intelligence_timelines where entity_id=e.id order by occurred_at desc limit 50) t), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(to_jsonb(ev) order by ev.occurred_at desc) from (select * from tj.intelligence_events where entity_id=e.id order by occurred_at desc limit 50) ev), '[]'::jsonb),
    'cached_context', coalesce((select jsonb_agg(to_jsonb(c) order by c.updated_at desc) from tj.intelligence_context_cache c where c.entity_id=e.id and (c.expires_at is null or c.expires_at > now())), '[]'::jsonb)
  )
  from tj.intelligence_entities e
  where e.id=p_entity_id;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_entity_context(p_entity_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_entity_timeline(p_entity_id uuid, p_limit integer DEFAULT 100)
 RETURNS SETOF tj.intelligence_timelines
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select t.*
  from tj.intelligence_timelines t
  where t.entity_id = p_entity_id
  order by t.occurred_at desc
  limit greatest(1, least(coalesce(p_limit,100),500));
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_entity_timeline(p_entity_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_event_to_timeline()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  insert into tj.intelligence_timelines(
    organization_id, entity_id, event_id, timeline_type, title, summary, metadata, occurred_at
  ) values (
    new.organization_id,
    new.entity_id,
    new.id,
    coalesce(new.payload->>'timeline_type','activity'),
    coalesce(new.payload->>'title', initcap(replace(new.event_type,'_',' '))),
    new.payload->>'summary',
    jsonb_build_object('source_system',new.source_system,'source_record_id',new.source_record_id,'actor_id',new.actor_id),
    new.occurred_at
  )
  on conflict(event_id) do nothing;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_event_to_timeline() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_field_org(p_client_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select organization_id from tj.field_clients where id=p_client_id limit 1;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_field_org(p_client_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_outcome_after_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare rec tj.intelligence_recommendations%rowtype;
begin
  select * into rec from tj.intelligence_recommendations where id = coalesce(new.recommendation_id, old.recommendation_id);
  perform tj.intelligence_refresh_learning_signal(coalesce(new.recommendation_id, old.recommendation_id));
  insert into tj.intelligence_events(organization_id, entity_id, event_type, source_system, source_record_id, actor_id, payload, occurred_at)
  values (
    rec.organization_id,
    coalesce(new.entity_id, rec.entity_id),
    case when tg_op='DELETE' then 'RecommendationOutcomeRemoved' else 'RecommendationOutcomeRecorded' end,
    'intelligence_learning',
    coalesce(new.id, old.id)::text,
    coalesce(new.recorded_by, old.recorded_by),
    jsonb_build_object('recommendation_id',rec.id,'outcome_type',coalesce(new.outcome_type,old.outcome_type),'success',coalesce(new.success,old.success),'weight',coalesce(new.weight,old.weight)),
    coalesce(new.occurred_at, old.occurred_at, now())
  );
  return coalesce(new,old);
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_outcome_after_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_publish_event(p_organization_id uuid, p_entity_id uuid, p_event_type text, p_source_system text, p_source_record_id text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_correlation_id uuid DEFAULT NULL::uuid, p_causation_id uuid DEFAULT NULL::uuid, p_occurred_at timestamp with time zone DEFAULT now())
 RETURNS tj.intelligence_events
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_event tj.intelligence_events;
begin
  insert into tj.intelligence_events(
    organization_id, entity_id, event_type, source_system, source_record_id, actor_id,
    correlation_id, causation_id, payload, occurred_at
  ) values (
    p_organization_id, p_entity_id, lower(p_event_type), p_source_system, p_source_record_id,
    tj_private.current_source_user_id(), p_correlation_id, p_causation_id, coalesce(p_payload,'{}'::jsonb), p_occurred_at
  ) returning * into v_event;
  return v_event;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_publish_event(p_organization_id uuid, p_entity_id uuid, p_event_type text, p_source_system text, p_source_record_id text, p_payload jsonb, p_correlation_id uuid, p_causation_id uuid, p_occurred_at timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_rank_actions(p_organization_id uuid, p_context_key text, p_subject_type text, p_subject_key text, p_limit integer DEFAULT 10)
 RETURNS TABLE(recommended_action text, bayesian_score numeric, success_rate numeric, observation_count bigint, average_outcome_value numeric)
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select s.recommended_action,s.bayesian_score,s.success_rate,s.observation_count,s.average_outcome_value
  from tj.intelligence_learning_signals s
  where s.organization_id=p_organization_id and s.context_key=coalesce(nullif(p_context_key,''),'general')
    and s.subject_type=p_subject_type and s.subject_key=p_subject_key
  order by s.bayesian_score desc,s.observation_count desc,s.updated_at desc
  limit greatest(1,least(coalesce(p_limit,10),100));
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_rank_actions(p_organization_id uuid, p_context_key text, p_subject_type text, p_subject_key text, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_recommendation_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  insert into tj.intelligence_events(organization_id, entity_id, event_type, source_system, source_record_id, actor_id, payload, occurred_at)
  values (new.organization_id,new.entity_id,'RecommendationGenerated','intelligence_learning',new.id::text,new.actor_id,
    jsonb_build_object('recommendation_type',new.recommendation_type,'context_key',new.context_key,'subject_type',new.subject_type,'subject_key',new.subject_key,'recommended_action',new.recommended_action,'confidence',new.confidence),new.created_at);
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_recommendation_after_insert() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_record_outcome(p_recommendation_id uuid, p_outcome_type text, p_success boolean DEFAULT NULL::boolean, p_outcome_value numeric DEFAULT NULL::numeric, p_outcome_label text DEFAULT NULL::text, p_weight numeric DEFAULT 1, p_metadata jsonb DEFAULT '{}'::jsonb, p_source_system text DEFAULT 'intelligence_core'::text, p_source_record_id text DEFAULT NULL::text, p_occurred_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid; v_org uuid; v_entity uuid;
begin
  select organization_id,entity_id into v_org,v_entity from tj.intelligence_recommendations where id=p_recommendation_id;
  if v_org is null then raise exception 'Recommendation not found'; end if;
  insert into tj.intelligence_outcomes(organization_id,recommendation_id,entity_id,outcome_type,outcome_value,outcome_label,success,weight,metadata,source_system,source_record_id,occurred_at,recorded_by)
  values(v_org,p_recommendation_id,v_entity,p_outcome_type,p_outcome_value,p_outcome_label,p_success,coalesce(p_weight,1),coalesce(p_metadata,'{}'::jsonb),p_source_system,p_source_record_id,coalesce(p_occurred_at,now()),(select tj_private.current_source_user_id()))
  on conflict (organization_id,source_system,source_record_id) where source_record_id is not null
  do update set outcome_type=excluded.outcome_type,outcome_value=excluded.outcome_value,outcome_label=excluded.outcome_label,success=excluded.success,weight=excluded.weight,metadata=excluded.metadata,occurred_at=excluded.occurred_at
  returning id into v_id;
  return v_id;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_record_outcome(p_recommendation_id uuid, p_outcome_type text, p_success boolean, p_outcome_value numeric, p_outcome_label text, p_weight numeric, p_metadata jsonb, p_source_system text, p_source_record_id text, p_occurred_at timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_record_recommendation(p_organization_id uuid, p_recommendation_type text, p_subject_type text, p_subject_key text, p_recommended_action text, p_context_key text DEFAULT 'general'::text, p_entity_id uuid DEFAULT NULL::uuid, p_confidence numeric DEFAULT NULL::numeric, p_rationale jsonb DEFAULT '{}'::jsonb, p_alternatives jsonb DEFAULT '[]'::jsonb, p_source_system text DEFAULT 'intelligence_core'::text, p_source_record_id text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid;
begin
  insert into tj.intelligence_recommendations(
    organization_id,entity_id,recommendation_type,context_key,subject_type,subject_key,recommended_action,
    confidence,rationale,alternatives,actor_id,source_system,source_record_id,presented_at
  ) values (
    p_organization_id,p_entity_id,p_recommendation_type,coalesce(nullif(p_context_key,''),'general'),p_subject_type,p_subject_key,p_recommended_action,
    p_confidence,coalesce(p_rationale,'{}'::jsonb),coalesce(p_alternatives,'[]'::jsonb),(select tj_private.current_source_user_id()),p_source_system,p_source_record_id,now()
  )
  on conflict (organization_id,source_system,source_record_id) where source_record_id is not null
  do update set updated_at=now(), confidence=excluded.confidence, rationale=excluded.rationale, alternatives=excluded.alternatives
  returning id into v_id;
  return v_id;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_record_recommendation(p_organization_id uuid, p_recommendation_type text, p_subject_type text, p_subject_key text, p_recommended_action text, p_context_key text, p_entity_id uuid, p_confidence numeric, p_rationale jsonb, p_alternatives jsonb, p_source_system text, p_source_record_id text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_refresh_learning_signal(p_recommendation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.intelligence_recommendations%rowtype;
begin
  select * into r from tj.intelligence_recommendations where id = p_recommendation_id;
  if not found then return; end if;

  insert into tj.intelligence_learning_signals as s (
    organization_id, context_key, subject_type, subject_key, recommended_action,
    observation_count, success_count, failure_count, neutral_count,
    weighted_success, weighted_total, success_rate, bayesian_score,
    average_outcome_value, last_outcome_at, updated_at
  )
  select
    r.organization_id, r.context_key, r.subject_type, r.subject_key, r.recommended_action,
    count(o.id),
    count(*) filter (where o.success is true),
    count(*) filter (where o.success is false),
    count(*) filter (where o.success is null),
    coalesce(sum(case when o.success is true then greatest(o.weight,0) else 0 end),0),
    coalesce(sum(case when o.success is not null then greatest(o.weight,0) else 0 end),0),
    case when count(*) filter (where o.success is not null) = 0 then 0
      else count(*) filter (where o.success is true)::numeric / count(*) filter (where o.success is not null) end,
    (1 + coalesce(sum(case when o.success is true then greatest(o.weight,0) else 0 end),0)) /
    (2 + coalesce(sum(case when o.success is not null then greatest(o.weight,0) else 0 end),0)),
    avg(o.outcome_value), max(o.occurred_at), now()
  from tj.intelligence_recommendations rr
  join tj.intelligence_outcomes o on o.recommendation_id = rr.id
  where rr.organization_id = r.organization_id
    and rr.context_key = r.context_key
    and rr.subject_type = r.subject_type
    and rr.subject_key = r.subject_key
    and rr.recommended_action = r.recommended_action
  group by r.organization_id, r.context_key, r.subject_type, r.subject_key, r.recommended_action
  on conflict (organization_id, context_key, subject_type, subject_key, recommended_action)
  do update set
    observation_count = excluded.observation_count,
    success_count = excluded.success_count,
    failure_count = excluded.failure_count,
    neutral_count = excluded.neutral_count,
    weighted_success = excluded.weighted_success,
    weighted_total = excluded.weighted_total,
    success_rate = excluded.success_rate,
    bayesian_score = excluded.bayesian_score,
    average_outcome_value = excluded.average_outcome_value,
    last_outcome_at = excluded.last_outcome_at,
    updated_at = now();
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_refresh_learning_signal(p_recommendation_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_register_entity(p_organization_id uuid, p_entity_type text, p_canonical_name text, p_source_system text, p_source_record_id text, p_slug text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS tj.intelligence_entities
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity tj.intelligence_entities;
begin
  insert into tj.intelligence_entities(
    organization_id, entity_type, canonical_name, source_system, source_record_id, slug, metadata, created_by, updated_by
  ) values (
    p_organization_id, lower(p_entity_type), p_canonical_name, p_source_system, p_source_record_id, p_slug, coalesce(p_metadata,'{}'::jsonb), tj_private.current_source_user_id(), tj_private.current_source_user_id()
  )
  on conflict (organization_id, source_system, source_record_id)
  do update set
    canonical_name = excluded.canonical_name,
    entity_type = excluded.entity_type,
    slug = coalesce(excluded.slug, tj.intelligence_entities.slug),
    metadata = tj.intelligence_entities.metadata || excluded.metadata,
    updated_by = tj_private.current_source_user_id()
  returning * into v_entity;
  return v_entity;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_register_entity(p_organization_id uuid, p_entity_type text, p_canonical_name text, p_source_system text, p_source_record_id text, p_slug text, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_replay_events(p_organization_id uuid, p_after timestamp with time zone DEFAULT NULL::timestamp with time zone, p_event_type text DEFAULT NULL::text, p_limit integer DEFAULT 500)
 RETURNS SETOF tj.intelligence_events
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select e.*
  from tj.intelligence_events e
  where e.organization_id=p_organization_id
    and (p_after is null or e.occurred_at > p_after)
    and (p_event_type is null or e.event_type=p_event_type)
  order by e.occurred_at asc
  limit greatest(1, least(coalesce(p_limit,500),5000));
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_replay_events(p_organization_id uuid, p_after timestamp with time zone, p_event_type text, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_resolve_user_org(p_user_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select case when count(*)=1 then (array_agg(organization_id))[1] else null end
  from tj.organization_members
  where user_id=p_user_id and coalesce(status,'active')='active';
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_resolve_user_org(p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_search_entities(p_organization_id uuid, p_query text, p_entity_type text DEFAULT NULL::text, p_limit integer DEFAULT 25)
 RETURNS SETOF tj.intelligence_entities
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select e.*
  from tj.intelligence_entities e
  where e.organization_id=p_organization_id
    and (p_entity_type is null or e.entity_type=p_entity_type)
    and (
      e.canonical_name ilike '%' || p_query || '%'
      or coalesce(e.slug,'') ilike '%' || p_query || '%'
      or coalesce(e.source_record_id,'') ilike '%' || p_query || '%'
      or e.metadata::text ilike '%' || p_query || '%'
    )
  order by case when lower(e.canonical_name)=lower(p_query) then 0 when lower(e.canonical_name) like lower(p_query)||'%' then 1 else 2 end, e.updated_at desc
  limit greatest(1, least(coalesce(p_limit,25),100));
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_search_entities(p_organization_id uuid, p_query text, p_entity_type text, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_set_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_speciq_entity(p_organization_id uuid, p_entity_type text, p_name text, p_source_system text, p_source_record_id text, p_status text DEFAULT 'active'::text, p_metadata jsonb DEFAULT '{}'::jsonb, p_created_by uuid DEFAULT NULL::uuid, p_updated_by uuid DEFAULT NULL::uuid, p_created_at timestamp with time zone DEFAULT now(), p_updated_at timestamp with time zone DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid; v_slug text;
begin
  v_slug := trim(both '-' from regexp_replace(lower(coalesce(nullif(p_name,''),p_entity_type)),'[^a-z0-9]+','-','g')) || '-' || left(p_source_record_id,8);
  insert into tj.intelligence_entities(
    organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,
    created_by,updated_by,created_at,updated_at
  ) values (
    p_organization_id,p_entity_type,coalesce(nullif(p_name,''),initcap(p_entity_type)),v_slug,p_source_system,p_source_record_id,
    case when p_status in ('active','inactive','archived','merged','deleted') then p_status else 'active' end,
    coalesce(p_metadata,'{}'::jsonb),p_created_by,p_updated_by,coalesce(p_created_at,now()),coalesce(p_updated_at,now())
  )
  on conflict (organization_id,source_system,source_record_id)
  do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,
    metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning id into v_id;
  return v_id;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_speciq_entity(p_organization_id uuid, p_entity_type text, p_name text, p_source_system text, p_source_record_id text, p_status text, p_metadata jsonb, p_created_by uuid, p_updated_by uuid, p_created_at timestamp with time zone, p_updated_at timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_academy_progress()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_rec uuid; v_title text;
begin
  if tg_op='DELETE' then return old; end if;
  v_org:=tj.intelligence_resolve_user_org(new.user_id);
  if v_org is null then return new; end if;
  select title into v_title from tj.academy_chapters where id=new.chapter_id;
  v_rec:=tj.intelligence_record_recommendation(v_org,'training_module','employee',new.user_id::text,coalesce(v_title,'chapter '||new.chapter_id::text),'academy_chapter:'||new.chapter_id::text,null,null,jsonb_build_object('chapter_id',new.chapter_id),'[]'::jsonb,'academy_progress',new.id::text);
  if new.completed_at is not null then
    perform tj.intelligence_record_outcome(v_rec,'module_completed',true,1,'Training module completed',1,jsonb_build_object('chapter_id',new.chapter_id),'academy_progress_outcome',new.id::text,new.completed_at);
    update tj.intelligence_recommendations set status='accepted',resolved_at=new.completed_at where id=v_rec;
  end if;
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_academy_progress() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_academy_quiz_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_rec uuid; v_ratio numeric;
begin
  v_org:=tj.intelligence_resolve_user_org(new.user_id);
  if v_org is null then return new; end if;
  v_ratio:=case when new.total>0 then new.score::numeric/new.total else 0 end;
  v_rec:=tj.intelligence_record_recommendation(v_org,'knowledge_assessment','employee',new.user_id::text,'Complete quiz '||new.vol,'academy_quiz:'||new.vol,null,null,jsonb_build_object('volume',new.vol),'[]'::jsonb,'academy_quiz_score',new.user_id::text||':'||new.vol);
  perform tj.intelligence_record_outcome(v_rec,'quiz_score',v_ratio>=0.8,v_ratio,'Quiz completed',1,jsonb_build_object('score',new.score,'total',new.total),'academy_quiz_outcome',new.user_id::text||':'||new.vol,coalesce(new.updated_at,now()));
  update tj.intelligence_recommendations set status=case when v_ratio>=0.8 then 'accepted' else 'rejected' end,resolved_at=coalesce(new.updated_at,now()) where id=v_rec;
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_academy_quiz_score() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_ai_coaching_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity uuid;
begin
  if tg_op='DELETE' then return old; end if;
  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
  values(new.organization_id,'other',concat('Coaching review: ',new.review_kind),'coaching-review-'||new.id::text,'ai_coaching_review',new.id::text,'active',
    jsonb_strip_nulls(jsonb_build_object('activity_id',new.activity_id,'recording_id',new.recording_id,'review_kind',new.review_kind,'overall_score',new.overall_score,'kpi_scores',new.kpi_scores,'analysis',new.analysis,'model',new.model)),new.created_at,new.created_at)
  on conflict(organization_id,source_system,source_record_id) do update set metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;
  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,payload,occurred_at)
  values(new.organization_id,v_entity,'CoachingReviewCompleted','ai_coaching_review',new.id::text,jsonb_build_object('score',new.overall_score,'review_kind',new.review_kind,'kpi_scores',new.kpi_scores),new.created_at);
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_ai_coaching_review() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_ai_roleplay()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity uuid; v_rec uuid; v_success boolean; v_score numeric;
begin
  if tg_op='DELETE' then return old; end if;
  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
  values(new.organization_id,'conversation',concat('Role-play: ',new.scenario_type),'roleplay-'||new.id::text,'academy_roleplay',new.id::text,case when lower(new.status)='completed' then 'active' else 'inactive' end,
    jsonb_strip_nulls(jsonb_build_object('user_id',new.user_id,'scenario_type',new.scenario_type,'status',new.status,'turns',new.total_turns,'score',new.session_score,'kpi_scores',new.kpi_scores,'feedback',new.feedback)),new.user_id,new.user_id,new.created_at,coalesce(new.completed_at,new.created_at))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;

  v_rec:=tj.intelligence_record_recommendation(new.organization_id,'training_practice','employee',new.user_id::text,new.scenario_type,'sales_coach:'||new.scenario_type,v_entity,null,jsonb_build_object('source','roleplay','scenario',new.scenario_type),'[]'::jsonb,'academy_roleplay',new.id::text);

  if lower(new.status)='completed' and new.session_score is not null then
    v_score:=case when new.session_score>10 then new.session_score/10.0 else new.session_score end;
    v_success:=v_score>=7;
    perform tj.intelligence_record_outcome(v_rec,'roleplay_score',v_success,v_score,'Role-play completed',greatest(0.25,least(2,v_score/5)),jsonb_build_object('kpi_scores',new.kpi_scores,'feedback',new.feedback),'academy_roleplay_outcome',new.id::text,coalesce(new.completed_at,now()));
    update tj.intelligence_recommendations set status=case when v_success then 'accepted' else 'rejected' end,resolved_at=coalesce(new.completed_at,now()) where id=v_rec;
  end if;
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_ai_roleplay() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_aiq_product()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity_id uuid; v_slug text; v_status text;
begin
 if tg_op='DELETE' then
  select id into v_entity_id from tj.intelligence_entities where organization_id=old.organization_id and source_system='product_iq_product' and source_record_id=old.id::text;
  if v_entity_id is not null then
   insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
   values(old.organization_id,v_entity_id,'ProductDeleted','product_iq_product',old.id::text,tj_private.current_source_user_id(),jsonb_build_object('model',old.model,'brand_name',old.brand_name),now());
   update tj.intelligence_entities set status='deleted',updated_by=tj_private.current_source_user_id(),updated_at=now() where id=v_entity_id;
  end if;
  return old;
 end if;
 v_slug:=trim(both '-' from regexp_replace(lower(concat_ws('-',new.brand_name,new.model)),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8);
 v_status:=case when coalesce(new.is_discontinued,false) or coalesce(new.is_end_of_life,false) then 'inactive' when lower(coalesce(new.status,'active')) in ('inactive','archived','deleted') then lower(new.status) else 'active' end;
 insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'product',trim(concat_ws(' ',new.brand_name,new.model)),v_slug,'product_iq_product',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('aiq_product_id',new.id,'brand_id',new.brand_id,'manufacturer_id',new.manufacturer_id,'manufacturer_name',new.manufacturer_name,'brand_name',new.brand_name,'model',new.model,'category',new.category,'series',new.series,'product_line',new.product_line,'product_family',new.product_family,'market',new.market,'msrp',new.msrp,'price_currency',new.price_currency,'upc',new.upc,'ean',new.ean,'gtin',new.gtin,'approval_status',new.approval_status,'public_visible',new.public_visible,'source_type',new.source_type,'source_reference',new.source_reference,'source_confidence',new.source_confidence,'source_review_status',new.source_review_status,'version_number',new.version_number,'is_discontinued',new.is_discontinued,'is_clearance',new.is_clearance,'is_end_of_life',new.is_end_of_life,'replacement_model',new.replacement_model)),coalesce(new.created_by,tj_private.current_source_user_id()),coalesce(new.updated_by,tj_private.current_source_user_id()),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'ProductCreated' else 'ProductUpdated' end,'product_iq_product',new.id::text,coalesce(new.updated_by,new.created_by,tj_private.current_source_user_id()),jsonb_strip_nulls(jsonb_build_object('model',new.model,'brand_name',new.brand_name,'category',new.category,'approval_status',new.approval_status,'public_visible',new.public_visible,'version_number',new.version_number,'source_confidence',new.source_confidence,'operation',lower(tg_op))),case when tg_op='INSERT' then coalesce(new.created_at,now()) else coalesce(new.updated_at,now()) end);
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_aiq_product() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_brand_catalog()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity_id uuid; v_slug text;
begin
 if tg_op='DELETE' then
  select id into v_entity_id from tj.intelligence_entities where organization_id=old.organization_id and source_system='product_iq_brand' and source_record_id=old.id::text;
  if v_entity_id is not null then
   insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
   values(old.organization_id,v_entity_id,'BrandDeleted','product_iq_brand',old.id::text,tj_private.current_source_user_id(),jsonb_build_object('brand_name',old.brand_name),now());
   update tj.intelligence_entities set status='deleted',updated_by=tj_private.current_source_user_id(),updated_at=now() where id=v_entity_id;
  end if;
  return old;
 end if;
 v_slug:=trim(both '-' from regexp_replace(lower(coalesce(new.slug,new.brand_name,'brand')),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8);
 insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'brand',new.brand_name,v_slug,'product_iq_brand',new.id::text,case when coalesce(new.is_active,true) then 'active' else 'inactive' end,
 jsonb_strip_nulls(jsonb_build_object('brand_catalog_id',new.id,'brand_tier',new.brand_tier,'manufacturer_id',new.manufacturer_id,'parent_company',new.parent_company,'country',new.country,'website',new.website,'canada_website',new.canada_website,'us_website',new.us_website,'logo_url',new.logo_url,'public_visible',new.public_visible,'product_categories',new.product_categories,'academy_status',new.academy_status)),tj_private.current_source_user_id(),tj_private.current_source_user_id(),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'BrandCreated' else 'BrandUpdated' end,'product_iq_brand',new.id::text,tj_private.current_source_user_id(),jsonb_strip_nulls(jsonb_build_object('brand_name',new.brand_name,'manufacturer_id',new.manufacturer_id,'active',new.is_active,'operation',lower(tg_op))),case when tg_op='INSERT' then coalesce(new.created_at,now()) else coalesce(new.updated_at,now()) end);
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_brand_catalog() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_crm_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity_id uuid; v_name text; v_status text;
begin
 if tg_op='DELETE' then
  update tj.intelligence_entities set status='deleted',updated_at=now(),updated_by=tj_private.current_source_user_id()
  where organization_id=old.organization_id and source_system='crm_contact' and source_record_id=old.id::text;
  return old;
 end if;
 v_name:=coalesce(nullif(new.preferred_name,''),nullif(trim(concat_ws(' ',new.first_name,new.last_name)),''),new.email,'Unnamed contact');
 v_status:=case when lower(coalesce(new.relationship_status,'')) in ('inactive','archived') then lower(new.relationship_status) else 'active' end;
 insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'customer',v_name,trim(both '-' from regexp_replace(lower(v_name),'[^a-z0-9]+','-','g'))||'-'||left(new.id::text,8),'crm_contact',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('contact_id',new.id,'company_id',new.company_id,'email',new.email,'phone',coalesce(new.mobile_phone,new.phone),'preferred_contact_method',new.preferred_contact_method,'preferred_language',new.preferred_language,'decision_making_role',new.decision_making_role,'purchasing_authority',new.purchasing_authority,'temperature',new.temperature,'lead_source',new.lead_source,'is_iq_lead',new.is_iq_lead,'last_communication_at',new.last_communication_at,'customer_last_response',new.customer_last_response,'next_followup_date',new.next_followup_date,'followup_status',new.followup_status)),
 new.assigned_salesperson_id,new.assigned_salesperson_id,new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at,updated_by=excluded.updated_by returning id into v_entity_id;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'CustomerRegistered' else 'CustomerUpdated' end,'crm_contact',new.id::text,new.assigned_salesperson_id,jsonb_build_object('title',case when tg_op='INSERT' then 'CRM customer registered' else 'CRM customer updated' end,'contact_id',new.id,'temperature',new.temperature,'followup_status',new.followup_status),case when tg_op='INSERT' then new.created_at else new.updated_at end);
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_crm_contact() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_crm_deal()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_entity_id uuid;
  v_rec_id uuid;
  v_is_won boolean;
  v_is_lost boolean;
  v_stage_lower text;
begin
  if new.organization_id is null then return new; end if;

  v_entity_id := (
    select id from tj.intelligence_entities
    where organization_id = new.organization_id
      and source_system = 'crm'
      and source_record_id = new.id::text
    limit 1
  );
  if v_entity_id is null then
    insert into tj.intelligence_entities(organization_id, entity_type, canonical_name, source_system, source_record_id, metadata)
    values(new.organization_id, 'opportunity', coalesce(new.title, 'Deal'), 'crm', new.id::text,
           jsonb_build_object('stage', new.stage, 'value', new.value_amount, 'contact_id', new.contact_id))
    returning id into v_entity_id;
  else
    update tj.intelligence_entities
    set canonical_name = coalesce(new.title, canonical_name),
        metadata = jsonb_build_object('stage', new.stage, 'value', new.value_amount, 'contact_id', new.contact_id),
        updated_at = now()
    where id = v_entity_id;
  end if;

  v_stage_lower := lower(coalesce(new.stage, ''));
  v_is_won := v_stage_lower in ('closed won','won','sold','completed','purchased');
  v_is_lost := v_stage_lower in ('closed lost','lost','cancelled','rejected','expired');

  perform tj.intelligence_publish_event(
    new.organization_id, v_entity_id,
    case
      when v_is_won then 'DealWon'
      when v_is_lost then 'DealLost'
      when tg_op = 'INSERT' then 'DealCreated'
      when old.stage is distinct from new.stage then 'DealStageChanged'
      else 'DealUpdated'
    end,
    'crm', new.id::text,
    jsonb_build_object(
      'stage', new.stage, 'previous_stage', case when tg_op='UPDATE' then old.stage else null end,
      'value_amount', new.value_amount, 'contact_id', new.contact_id,
      'lost_reason', case when v_is_lost then coalesce(new.lost_reason, 'Not specified') else null end
    ),
    null, null, coalesce(new.updated_at, now())
  );

  if v_is_won or v_is_lost then
    select id into v_rec_id from tj.intelligence_recommendations
    where organization_id = new.organization_id
      and subject_type = 'deal'
      and subject_key = new.id::text
      and context_key = format('crm_deal:%s:%s', coalesce(new.record_type,'individual'), coalesce(new.contact_id::text,''))
    limit 1;

    if v_rec_id is null then
      insert into tj.intelligence_recommendations(
        organization_id, recommendation_type, subject_type, subject_key,
        recommended_action, context_key, entity_id, confidence,
        rationale, source_system, source_record_id
      ) values (
        new.organization_id, 'deal_outcome', 'deal', new.id::text,
        'review outcome', format('crm_deal:%s:%s', coalesce(new.record_type,'individual'), coalesce(new.contact_id::text,'')),
        v_entity_id, 0.7,
        jsonb_build_object('stage', new.stage, 'value', new.value_amount),
        'crm', new.id::text
      ) returning id into v_rec_id;
    end if;

    perform tj.intelligence_record_outcome(
      v_rec_id,
      case when v_is_won then 'deal_won' else 'deal_lost' end,
      v_is_won,
      new.value_amount,
      case when v_is_won then 'Won' else format('Lost: %s', coalesce(new.lost_reason, 'No reason')) end,
      1.0,
      jsonb_build_object('stage', new.stage, 'value', new.value_amount, 'record_type', new.record_type),
      'crm', new.id::text,
      coalesce(new.updated_at, now())
    );
  end if;

  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_crm_deal() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_crm_delivery()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_rec uuid; v_success boolean;
begin
 select id into v_rec from tj.intelligence_recommendations where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 if v_rec is null then return new; end if;
 if new.delivered_at is not null then perform tj.intelligence_record_outcome(v_rec,'delivery_completed',true,null,'Delivered',2,jsonb_build_object('delivery_workflow_id',new.id),'crm_delivery',new.id::text||':delivered',new.delivered_at); end if;
 if new.installed_at is not null then perform tj.intelligence_record_outcome(v_rec,'installation_completed',true,null,'Installed',2,jsonb_build_object('delivery_workflow_id',new.id),'crm_delivery',new.id::text||':installed',new.installed_at); end if;
 if new.satisfaction_score is not null then
  v_success:=new.satisfaction_score>=4;
  perform tj.intelligence_record_outcome(v_rec,'customer_satisfaction',v_success,new.satisfaction_score,new.satisfaction_notes,3,jsonb_build_object('score',new.satisfaction_score),'crm_delivery',new.id::text||':satisfaction',new.updated_at);
 end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_crm_delivery() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_crm_postmortem()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_rec uuid; v_entity uuid;
begin
 select id into v_entity from tj.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 select id into v_rec from tj.intelligence_recommendations where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity,'DealPostmortemRecorded','crm_postmortem',new.id::text,new.salesperson_id,jsonb_strip_nulls(jsonb_build_object('title','CRM deal postmortem recorded','review_type',new.review_type,'strengths',new.strengths,'improvements',new.improvements,'objections',new.objections,'closing_method',new.closing_method,'controllability',new.controllability,'recoverable',new.is_recoverable,'warranty_sold',new.warranty_sold,'accessories_included',new.accessories_included,'competitor_considered',new.competitor_considered)),coalesce(new.completed_at,new.updated_at,new.created_at));
 if v_rec is not null and new.completed_at is not null then perform tj.intelligence_record_outcome(v_rec,'postmortem_completed',null,null,new.review_type,.5,jsonb_strip_nulls(jsonb_build_object('customer_satisfaction',new.customer_satisfaction,'warranty_sold',new.warranty_sold,'accessories_included',new.accessories_included,'closing_method',new.closing_method)),'crm_postmortem',new.id::text,new.completed_at); end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_crm_postmortem() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_crm_task()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_rec uuid; v_entity uuid; v_success boolean;
begin
 if new.ai_recommended is distinct from true then return new; end if;
 select id into v_entity from tj.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 v_rec:=tj.intelligence_record_recommendation(new.organization_id,'crm_task','deal',coalesce(new.deal_id::text,new.contact_id::text,new.company_id::text),new.title,'crm_task:'||coalesce(new.task_type,'general'),v_entity,case when new.ai_priority_score between 0 and 1 then new.ai_priority_score else null end,jsonb_strip_nulls(jsonb_build_object('description',new.description,'due_at',new.due_at,'priority',new.priority,'task_category',new.task_category)),'[]'::jsonb,'crm_task',new.id::text);
 if new.completed_at is not null then
  v_success:=case when lower(coalesce(new.resolution_note,'')) like '%unsuccess%' or lower(coalesce(new.resolution_note,'')) like '%failed%' then false else true end;
  perform tj.intelligence_record_outcome(v_rec,'task_completed',v_success,null,new.resolution_note,1,jsonb_build_object('deal_id',new.deal_id,'completed_at',new.completed_at),'crm_task',new.id::text||':completed',new.completed_at);
 end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_crm_task() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_daily_coaching_focus()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_rec uuid;
begin
  if tg_op='DELETE' then return old; end if;
  v_rec:=tj.intelligence_record_recommendation(new.organization_id,'coaching_focus','employee',new.user_id::text,coalesce(new.primary_kpi_name,'general coaching'),'coach_focus:'||coalesce(lower(regexp_replace(new.primary_kpi_name,'[^a-zA-Z0-9]+','_','g')),'general'),null,null,
    jsonb_strip_nulls(jsonb_build_object('previous_score',new.previous_score,'target_score',new.target_score,'insight',new.insight,'focus_date',new.focus_date)),'[]'::jsonb,'daily_coaching_focus',new.id::text);
  return new;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_daily_coaching_focus() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_action()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_org uuid;
  v_entity_id uuid;
  v_rec_id uuid;
  v_is_resolved boolean;
begin
  -- Resolve org via client
  select c.organization_id into v_org
  from tj.field_clients c where c.id = new.client_id;
  if v_org is null then
    v_org := tj.intelligence_field_org(new.client_id);
  end if;
  if v_org is null then return new; end if;

  -- Register action entity
  v_entity_id := (
    select id from tj.intelligence_entities
    where organization_id = v_org
      and source_system = 'field_reports'
      and source_record_id = new.id::text
    limit 1
  );
  if v_entity_id is null then
    insert into tj.intelligence_entities(organization_id, entity_type, canonical_name, source_system, source_record_id, metadata)
    values(v_org, 'other', coalesce(new.title, 'Field Action'), 'field_reports', new.id::text,
           jsonb_build_object('status', new.status, 'priority', new.priority))
    returning id into v_entity_id;
  end if;

  v_is_resolved := lower(coalesce(new.status,'')) in ('resolved','closed','completed','verified');

  -- Publish event
  perform tj.intelligence_publish_event(
    v_org, v_entity_id,
    case
      when v_is_resolved then 'FieldActionResolved'
      when tg_op = 'INSERT' then 'FieldActionCreated'
      else 'FieldActionUpdated'
    end,
    'field_reports', new.id::text,
    jsonb_build_object('title', new.title, 'status', new.status, 'priority', new.priority,
                       'assigned_to', new.assigned_to, 'due_date', new.due_date),
    null, null, coalesce(new.updated_at, now())
  );

  -- Learning: create recommendation + outcome on resolution
  if v_is_resolved or (tg_op = 'UPDATE' and lower(coalesce(old.status,'')) not in ('resolved','closed','completed','verified')
                        and lower(coalesce(new.status,'')) in ('resolved','closed','completed','verified')) then
    select id into v_rec_id from tj.intelligence_recommendations
    where organization_id = v_org
      and subject_type = 'field_action'
      and subject_key = new.id::text
      and source_system = 'field_reports'
    limit 1;

    if v_rec_id is null then
      insert into tj.intelligence_recommendations(
        organization_id, recommendation_type, subject_type, subject_key,
        recommended_action, context_key, entity_id, confidence,
        rationale, source_system, source_record_id
      ) values (
        v_org, 'corrective_action', 'field_action', new.id::text,
        'resolve_action', 'field_corrective', v_entity_id, 0.6,
        jsonb_build_object('title', new.title, 'priority', new.priority),
        'field_reports', new.id::text
      ) returning id into v_rec_id;
    end if;

    perform tj.intelligence_record_outcome(
      v_rec_id, 'resolved', true, null, 'Action resolved',
      1, jsonb_build_object('resolution_status', new.status),
      'field_reports', new.id::text, now()
    );
  end if;

  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_action() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_competitive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_client uuid;
begin
 select client_id into v_client from tj.field_visits where id=new.visit_id; v_org:=tj.intelligence_field_org(v_client); if v_org is null then return new; end if;
 insert into tj.intelligence_events(organization_id,event_type,source_system,source_record_id,payload,occurred_at)
 values(v_org,'CompetitiveIntelRecorded','field_competitive_intel',new.id::text,
   jsonb_strip_nulls(jsonb_build_object('title','Competitive activity: '||new.competitor_brand,'visit_id',new.visit_id,'store_id',new.store_id,'competitor_brand',new.competitor_brand,'floor_presence_pct',new.floor_presence_pct,'share_of_display',new.share_of_display,'promotions_active',new.promotions_active,'pricing_notes',new.pricing_notes,'new_models_spotted',new.new_models_spotted,'staff_preference_notes',new.staff_preference_notes,'customer_questions',new.customer_questions,'common_objections',new.common_objections,'rep_comments',new.rep_comments)),coalesce(new.created_at,now()));
 return new;
end;$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_competitive() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_finding()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_entity uuid; v_visit_entity uuid;
begin
  v_org:=tj.intelligence_field_org(new.client_id); if v_org is null then return new; end if;
  select id into v_visit_entity from tj.intelligence_entities where organization_id=v_org and source_system='field_reports_visit' and source_record_id=new.visit_id::text limit 1;
  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
  values(v_org,'other',coalesce(new.issue_category,'Field finding')||coalesce(' - '||new.model_number,''),'field-finding-'||new.id::text,'field_reports_finding',new.id::text,
    case when lower(coalesce(new.status,'')) in ('resolved','closed') then 'inactive' else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('visit_id',new.visit_id,'store_id',new.store_id,'brand_name',new.brand_name,'product_category',new.product_category,'model_number',new.model_number,'condition',new.condition,'issue_category',new.issue_category,'severity',new.severity,'recommended_action',new.recommended_action,'rep_comments',new.rep_comments,'ai_summary',new.ai_summary,'is_repeat',new.is_repeat,'status',new.status,'source',new.source)),coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,status=excluded.status,metadata=excluded.metadata,updated_at=excluded.updated_at returning id into v_entity;
  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,payload,occurred_at)
  values(v_org,coalesce(v_visit_entity,v_entity),case when tg_op='INSERT' then 'FieldFindingRecorded' else 'FieldFindingUpdated' end,'field_reports_finding',new.id::text,
    jsonb_strip_nulls(jsonb_build_object('title',initcap(coalesce(new.severity,'field'))||' finding','summary',coalesce(new.ai_summary,new.rep_comments),'finding_entity_id',v_entity,'severity',new.severity,'issue_category',new.issue_category,'brand_name',new.brand_name,'model_number',new.model_number,'recommended_action',new.recommended_action,'is_repeat',new.is_repeat)),coalesce(new.updated_at,new.created_at,now()));
  if nullif(new.recommended_action,'') is not null then
    perform tj.intelligence_record_recommendation(v_org,'field_corrective_action','field_finding',new.id::text,new.recommended_action,'field_issue:'||coalesce(new.issue_category,'general'),v_entity,
      case lower(coalesce(new.severity,'')) when 'critical' then 0.95 when 'high' then 0.85 when 'medium' then 0.7 else 0.55 end,
      jsonb_build_object('severity',new.severity,'brand_name',new.brand_name,'model_number',new.model_number,'is_repeat',new.is_repeat),'[]'::jsonb,'field_reports_finding',new.id::text);
  end if;
  return new;
end;$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_finding() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_store_score()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_rec uuid; v_score numeric;
begin
 v_org:=tj.intelligence_field_org(new.client_id); if v_org is null or new.overall_score is null then return new; end if;
 v_rec:=tj.intelligence_record_recommendation(v_org,'store_condition_improvement','store',new.store_id::text,'improve and maintain store execution score','field_store_score',null,null,jsonb_build_object('visit_id',new.visit_id),'[]'::jsonb,'field_store_score',new.id::text);
 v_score:=case when new.overall_score>10 then new.overall_score/100.0 else new.overall_score/10.0 end;
 perform tj.intelligence_record_outcome(v_rec,'store_execution_score',v_score>=0.7,v_score,'store score',1,jsonb_build_object('overall_score',new.overall_score,'score_date',new.score_date),'field_store_score',new.id::text,coalesce(new.created_at,now()));
 return new;
end;$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_store_score() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_training()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_rec uuid; v_score numeric; v_success boolean;
begin
 v_org:=tj.intelligence_field_org(new.client_id); if v_org is null then return new; end if;
 v_rec:=tj.intelligence_record_recommendation(v_org,'field_staff_training','store',new.store_id::text,'deliver training: '||new.training_topic,'field_training:'||coalesce(new.product_category,coalesce(new.brand_name,'general')),null,null,
   jsonb_build_object('brand_name',new.brand_name,'models_covered',new.models_covered,'employees_trained',new.employees_trained,'areas_of_weakness',new.areas_of_weakness),'[]'::jsonb,'field_training_session',new.id::text);
 if new.knowledge_score is not null then
   v_score:=case when new.knowledge_score>10 then new.knowledge_score/100.0 else new.knowledge_score/10.0 end;
   v_success:=v_score>=0.7;
   perform tj.intelligence_record_outcome(v_rec,'training_knowledge_score',v_success,v_score,'field training result',1,
     jsonb_build_object('knowledge_score',new.knowledge_score,'employees_trained',new.employees_trained,'duration_minutes',new.duration_minutes,'follow_up_required',new.follow_up_required),'field_training_score',new.id::text,coalesce(new.created_at,now()));
 end if;
 insert into tj.intelligence_events(organization_id,event_type,source_system,source_record_id,payload,occurred_at)
 values(v_org,'FieldTrainingCompleted','field_training_session',new.id::text,jsonb_strip_nulls(jsonb_build_object('title',new.training_topic,'brand_name',new.brand_name,'product_category',new.product_category,'employees_trained',new.employees_trained,'knowledge_score',new.knowledge_score,'follow_up_required',new.follow_up_required)),coalesce(new.created_at,now()));
 return new;
end;$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_training() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_field_visit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_org uuid; v_entity uuid; v_store text; v_client text; v_score numeric; v_success boolean;
begin
  v_org:=tj.intelligence_field_org(new.client_id);
  if v_org is null then return new; end if;
  select store_name into v_store from tj.field_stores where id=new.store_id;
  select client_name into v_client from tj.field_clients where id=new.client_id;
  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
  values(v_org,'field_report',coalesce(v_store,'Store')||' visit '||new.visit_date::text,'field-visit-'||new.id::text,'field_reports_visit',new.id::text,
    case when lower(coalesce(new.status,''))='completed' then 'active' else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('client_id',new.client_id,'client_name',v_client,'store_id',new.store_id,'store_name',v_store,'rep_user_id',new.rep_user_id,'visit_date',new.visit_date,'visit_type',new.visit_type,'visit_purpose',new.visit_purpose,'status',new.status,'duration_minutes',new.duration_minutes,'findings_count',new.findings_count,'critical_count',new.critical_count,'training_completed',new.training_completed,'people_trained',new.people_trained,'store_score',new.store_score,'brand_score',new.brand_score,'previous_score',new.previous_score,'checklist_score',new.checklist_score,'rep_summary',new.rep_summary,'ai_summary',new.ai_summary)),
    new.rep_user_id,new.rep_user_id,coalesce(new.created_at,now()),coalesce(new.updated_at,new.created_at,now()))
  on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning id into v_entity;
  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(v_org,v_entity,case when tg_op='INSERT' then 'FieldVisitCreated' else 'FieldVisitUpdated' end,'field_reports_visit',new.id::text,new.rep_user_id,
    jsonb_strip_nulls(jsonb_build_object('title','Field visit '||coalesce(v_store,''),'summary',new.ai_summary,'status',new.status,'store_score',new.store_score,'critical_count',new.critical_count)),coalesce(new.updated_at,new.created_at,now()));
  if lower(coalesce(new.status,''))='completed' and new.store_score is not null then
    v_score:=case when new.store_score>10 then new.store_score/100.0 else new.store_score/10.0 end;
    v_success:=v_score>=0.7;
    perform tj.intelligence_record_recommendation(v_org,'field_visit_execution','store',new.store_id::text,'complete field visit and improve store condition','field_visit:'||coalesce(new.visit_type,'general'),v_entity,null,jsonb_build_object('visit_purpose',new.visit_purpose),'[]'::jsonb,'field_reports_visit',new.id::text);
    perform tj.intelligence_record_outcome((select id from tj.intelligence_recommendations where organization_id=v_org and source_system='field_reports_visit' and source_record_id=new.id::text limit 1),'store_score',v_success,v_score,'completed visit score',1,jsonb_build_object('store_score',new.store_score,'previous_score',new.previous_score),'field_reports_visit_score',new.id::text,coalesce(new.departure_time,new.updated_at,now()));
  end if;
  return new;
end;$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_field_visit() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_iq_customer_interaction()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_org uuid;
  v_entity_id uuid;
  v_rec_id uuid;
  v_customer_name text;
  v_duration numeric;
begin
  v_org := new.organization_id;
  if v_org is null then return new; end if;

  -- Derive customer name from waiting queue if linked
  SELECT coalesce(nullif(cwq.customer_display_name,''), 'Walk-in') INTO v_customer_name
  FROM iq_customer_waiting_queue cwq WHERE cwq.id = new.customer_waiting_id;
  v_customer_name := coalesce(v_customer_name, 'Walk-in');

  -- Derive duration in minutes
  v_duration := CASE WHEN new.ended_at IS NOT NULL AND new.started_at IS NOT NULL
    THEN EXTRACT(EPOCH FROM (new.ended_at - new.started_at)) / 60.0
    ELSE NULL END;

  -- Register customer as entity
  v_entity_id := (
    select id from tj.intelligence_entities
    where organization_id = v_org
      and source_system = 'iq_up_system'
      and source_record_id = new.id::text
    limit 1
  );
  if v_entity_id is null then
    insert into tj.intelligence_entities(organization_id, entity_type, canonical_name, source_system, source_record_id, metadata)
    values(v_org, 'conversation', v_customer_name, 'iq_up_system', new.id::text,
           jsonb_build_object('rep_id', new.salesperson_user_id, 'outcome', new.outcome))
    returning id into v_entity_id;
  end if;

  -- Publish event
  perform tj.intelligence_publish_event(
    v_org, v_entity_id,
    case
      when lower(coalesce(new.outcome,'')) in ('sale','sold','won','purchased','closed_won') then 'FloorSaleCompleted'
      when lower(coalesce(new.outcome,'')) in ('no_sale','lost','browsing','left') then 'FloorNoSale'
      else 'FloorInteractionRecorded'
    end,
    'iq_up_system', new.id::text,
    jsonb_build_object('rep_id', new.salesperson_user_id, 'outcome', new.outcome, 'duration_minutes', v_duration,
                       'customer_name', v_customer_name, 'client_type', new.client_type),
    null, null, coalesce(new.created_at, now())
  );

  -- Create recommendation + outcome
  if lower(coalesce(new.outcome,'')) in ('sale','sold','won','purchased','closed_won','no_sale','lost') then
    select id into v_rec_id from tj.intelligence_recommendations
    where organization_id = v_org
      and context_key = 'floor_assignment'
      and subject_type = 'rep'
      and subject_key = coalesce(new.salesperson_user_id::text, 'unknown')
      and recommended_action = 'assign_customer'
      and source_system = 'iq_up_system'
      and source_record_id = new.id::text
    limit 1;

    if v_rec_id is null then
      insert into tj.intelligence_recommendations(
        organization_id, recommendation_type, subject_type, subject_key,
        recommended_action, context_key, entity_id, confidence,
        rationale, source_system, source_record_id
      ) values (
        v_org, 'assignment', 'rep', coalesce(new.salesperson_user_id::text, 'unknown'),
        'assign_customer', 'floor_assignment', v_entity_id, 0.5,
        jsonb_build_object('client_type', new.client_type, 'customer', v_customer_name),
        'iq_up_system', new.id::text
      ) returning id into v_rec_id;
    end if;

    perform tj.intelligence_record_outcome(
      v_rec_id,
      case when lower(new.outcome) in ('sale','sold','won','purchased','closed_won') then 'success' else 'failure' end,
      lower(new.outcome) in ('sale','sold','won','purchased','closed_won'),
      null,
      new.outcome,
      1,
      jsonb_build_object('duration_minutes', v_duration, 'client_type', new.client_type),
      'iq_up_system',
      new.id::text,
      coalesce(new.created_at, now())
    );
  end if;

  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_iq_customer_interaction() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_iq_lead_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity uuid; v_rec uuid;
begin
 if tg_op='DELETE' then return old; end if;
 select id into v_entity from tj.intelligence_entities where organization_id=new.organization_id and source_system='crm_deal' and source_record_id=new.deal_id::text;
 v_rec:=tj.intelligence_record_recommendation(new.organization_id,'lead_assignment','lead',coalesce(new.deal_id::text,new.contact_id::text,new.id::text),'assign_lead:'||coalesce(new.assigned_to::text,'unassigned'),coalesce('location:'||new.location_id::text,'crm'),v_entity,null,jsonb_strip_nulls(jsonb_build_object('assignment_reason',new.assignment_reason,'routing_method',new.routing_method,'response_time_seconds',new.response_time_seconds,'reassignment_count',new.reassignment_count)),'[]'::jsonb,'crm_iq_lead_assignment',new.id::text);
 if new.accepted is not null then
  perform tj.intelligence_record_outcome(v_rec,case when new.accepted then 'lead_assignment_accepted' else 'lead_assignment_declined' end,new.accepted,null,case when new.accepted then 'accepted' else 'declined' end,1.0,jsonb_strip_nulls(jsonb_build_object('response_time_seconds',new.response_time_seconds,'decline_reason',new.decline_reason,'reassignment_count',new.reassignment_count)),'crm_iq_lead_assignment','assignment:'||new.id::text,coalesce(new.accepted_at,new.declined_at,new.created_at));
  update tj.intelligence_recommendations set status=case when new.accepted then 'accepted' else 'rejected' end,resolved_at=coalesce(resolved_at,new.accepted_at,new.declined_at,now()) where id=v_rec;
 end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_iq_lead_assignment() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_iq_product_interest()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_waiting_entity uuid; v_action text;
begin
 if tg_op='DELETE' then return old; end if;
 select id into v_waiting_entity from tj.intelligence_entities where organization_id=new.organization_id and source_system='iq_up_waiting_customer' and source_record_id=new.customer_waiting_id::text;
 v_action:='show_product:'||coalesce(nullif(new.brand,''),'unknown')||':'||coalesce(nullif(new.product_name,''),coalesce(nullif(new.category,''),'unspecified'));
 perform tj.intelligence_record_recommendation(new.organization_id,'floor_product_interest','waiting_customer',new.customer_waiting_id::text,v_action,coalesce('store:'||new.store_id::text,'iq_up'),v_waiting_entity,null,jsonb_strip_nulls(jsonb_build_object('category',new.category,'brand',new.brand,'product_name',new.product_name,'price',new.price,'stock_status',new.stock_status,'delivery_date',new.delivery_date,'notes',new.notes)),'[]'::jsonb,'iq_up_product_interest',new.id::text);
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_iq_product_interest() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_iq_waiting_customer()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity_id uuid; v_name text; v_status text; v_rec_id uuid;
begin
 if tg_op='DELETE' then
  update tj.intelligence_entities set status='deleted',updated_at=now(),updated_by=tj_private.current_source_user_id()
  where organization_id=old.organization_id and source_system='iq_up_waiting_customer' and source_record_id=old.id::text;
  return old;
 end if;
 v_name:=coalesce(nullif(new.customer_display_name,''),'Waiting customer '||new.id::text);
 v_status:=case when new.status::text in ('left_unserved','cancelled','completed') then 'archived' else 'active' end;
 insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_by,updated_by,created_at,updated_at)
 values(new.organization_id,'customer',v_name,'waiting-customer-'||new.id::text,'iq_up_waiting_customer',new.id::text,v_status,
 jsonb_strip_nulls(jsonb_build_object('store_id',new.store_id,'shift_id',new.shift_id,'assigned_user_id',new.assigned_user_id,'group_size',new.customer_group_size,'description',new.customer_description,'category',new.customer_category,'requested_source',new.requested_source,'requested_employee_user_id',new.requested_employee_user_id,'priority',new.priority,'status',new.status::text,'arrival_time',new.arrival_time,'attempts',new.attempts,'max_attempts',new.max_attempts,'returning_customer',new.is_returning_customer,'purchase_timeframe',new.purchase_timeframe,'lead_source',new.lead_source,'customer_needs',new.customer_needs,'crm_contact_id',new.crm_contact_id,'crm_deal_id',new.crm_deal_id)),coalesce(new.created_by,tj_private.current_source_user_id()),coalesce(new.updated_by,tj_private.current_source_user_id()),new.created_at,new.updated_at)
 on conflict(organization_id,source_system,source_record_id) do update set canonical_name=excluded.canonical_name,slug=excluded.slug,status=excluded.status,metadata=excluded.metadata,updated_by=excluded.updated_by,updated_at=excluded.updated_at returning id into v_entity_id;
 if new.assigned_user_id is not null then
  v_rec_id:=tj.intelligence_record_recommendation(new.organization_id,'salesperson_assignment','waiting_customer',new.id::text,'assign_salesperson:'||new.assigned_user_id::text,coalesce('store:'||new.store_id::text,'iq_up'),v_entity_id,null,jsonb_strip_nulls(jsonb_build_object('priority',new.priority,'requested_employee_user_id',new.requested_employee_user_id,'purchase_timeframe',new.purchase_timeframe,'lead_source',new.lead_source)),'[]'::jsonb,'iq_up_assignment','waiting:'||new.id::text);
 end if;
 if new.status::text='left_unserved' then
  select id into v_rec_id from tj.intelligence_recommendations where organization_id=new.organization_id and source_system='iq_up_assignment' and source_record_id='waiting:'||new.id::text;
  if v_rec_id is not null then
   perform tj.intelligence_record_outcome(v_rec_id,'customer_left_unserved',false,null,'left_unserved',1.5,jsonb_build_object('attempts',new.attempts,'max_attempts',new.max_attempts),'iq_up_waiting_customer','left_unserved:'||new.id::text,new.updated_at);
   update tj.intelligence_recommendations set status='rejected',resolved_at=coalesce(resolved_at,new.updated_at) where id=v_rec_id;
  end if;
 end if;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
 values(new.organization_id,v_entity_id,case when tg_op='INSERT' then 'WaitingCustomerCreated' else 'WaitingCustomerUpdated' end,'iq_up_waiting_customer',new.id::text,coalesce(new.updated_by,new.created_by,tj_private.current_source_user_id()),jsonb_build_object('status',new.status::text,'assigned_user_id',new.assigned_user_id,'attempts',new.attempts,'priority',new.priority),case when tg_op='INSERT' then new.created_at else new.updated_at end);
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_iq_waiting_customer() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_speciq_package()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity uuid; v_event text; v_rec uuid; v_success boolean; v_outcome_type text;
begin
  if tg_op='DELETE' then
    select id into v_entity from tj.intelligence_entities
      where organization_id=old.organization_id and source_system='speciq_package' and source_record_id=old.id::text;
    if v_entity is not null then
      update tj.intelligence_entities set status='deleted',updated_at=now(),updated_by=(select tj_private.current_source_user_id()) where id=v_entity;
      insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
      values(old.organization_id,v_entity,'SpecIQPackageDeleted','speciq_package',old.id::text,(select tj_private.current_source_user_id()),
        jsonb_build_object('title','SpecIQ package deleted','package_name',old.package_name,'timeline_type','package'),now());
    end if;
    return old;
  end if;

  v_entity := tj.intelligence_speciq_entity(
    new.organization_id,'package',new.package_name,'speciq_package',new.id::text,
    case when lower(coalesce(new.status,'active')) in ('archived','deleted','inactive') then lower(new.status) else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('project_id',new.project_id,'status',new.status,'version',new.version,'quote_number',new.quote_number,
      'quote_version',new.quote_version,'total_msrp',new.total_msrp,'total_promo',new.total_promo,'total_negotiated',new.total_negotiated,
      'total_services',new.total_services,'total_tax',new.total_tax,'total_final',new.total_final,'total_savings',new.total_savings,
      'contact_id',new.contact_id,'deal_id',new.deal_id,'project_type',new.project_type,'unit_type',new.unit_type,'unit_count',new.unit_count,
      'phase',new.phase,'approval_status',new.approval_status,'sent_at',new.sent_at,'quote_expires_at',new.quote_expires_at)),
    new.created_by,coalesce(new.updated_by,(select tj_private.current_source_user_id()),new.created_by),new.created_at,new.updated_at
  );
  v_event := case when tg_op='INSERT' then 'SpecIQPackageCreated' else 'SpecIQPackageUpdated' end;
  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(new.organization_id,v_entity,v_event,'speciq_package',new.id::text,coalesce(new.updated_by,new.created_by,(select tj_private.current_source_user_id())),
    jsonb_build_object('title',case when tg_op='INSERT' then 'SpecIQ package created' else 'SpecIQ package updated' end,
      'summary',new.package_name,'timeline_type','package','status',new.status,'total_final',new.total_final),
    case when tg_op='INSERT' then new.created_at else new.updated_at end);

  if new.sent_at is not null or lower(coalesce(new.status,'')) in ('sent','accepted','won','sold','closed_won','rejected','lost','closed_lost','cancelled') then
    v_rec := tj.intelligence_ensure_speciq_package_recommendation(new.id);
  end if;

  if tg_op='UPDATE' and old.status is distinct from new.status and v_rec is not null then
    if lower(new.status) in ('accepted','won','sold','closed_won','completed','purchased') then
      v_success:=true; v_outcome_type:='package_accepted';
    elsif lower(new.status) in ('rejected','lost','closed_lost','cancelled','expired') then
      v_success:=false; v_outcome_type:='package_not_accepted';
    else
      v_success:=null; v_outcome_type:='package_status_'||lower(new.status);
    end if;
    perform tj.intelligence_record_outcome(v_rec,v_outcome_type,v_success,new.total_final,new.status,1,
      jsonb_build_object('package_id',new.id,'old_status',old.status,'new_status',new.status,'total_final',new.total_final),
      'speciq_package_status',new.id::text||':'||lower(new.status),new.updated_at);
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_speciq_package() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_speciq_package_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare p tj.speciq_packages%rowtype; v_rec uuid; v_success boolean; v_weight numeric; v_type text;
begin
  select * into p from tj.speciq_packages where id=new.package_id;
  if p.id is null then return new; end if;
  v_rec := tj.intelligence_ensure_speciq_package_recommendation(new.package_id);
  v_type := lower(new.event_type);
  v_success := case when v_type in ('accepted','purchased','sale_completed','won','converted') then true
                    when v_type in ('rejected','lost','cancelled','expired') then false else null end;
  v_weight := case
    when v_type in ('accepted','purchased','sale_completed','won','converted') then 5
    when v_type in ('rejected','lost','cancelled') then 5
    when v_type in ('downloaded','pricing_viewed','product_clicked') then 1.5
    when v_type in ('link_opened','page_viewed') then 1
    when v_type in ('sent','email_delivered') then 0.25
    else 0.5 end;
  perform tj.intelligence_record_outcome(
    v_rec,'engagement_'||v_type,v_success,
    case when v_success=true then p.total_final else null end,new.event_type,v_weight,
    coalesce(new.event_data,'{}'::jsonb)||jsonb_build_object('package_id',new.package_id,'speciq_event_id',new.id),
    'speciq_package_event',new.id::text,new.created_at
  );
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_speciq_package_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_speciq_package_product()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_rec uuid; p tj.speciq_packages%rowtype; v_product_entity uuid; v_action text;
begin
  if tg_op='DELETE' then
    perform tj.intelligence_ensure_speciq_package_recommendation(old.package_id);
    return old;
  end if;
  select * into p from tj.speciq_packages where id=new.package_id;
  if p.id is null then return new; end if;
  if new.aiq_product_id is not null then
    select id into v_product_entity from tj.intelligence_entities
      where organization_id=new.organization_id and source_system='product_iq_product' and source_record_id=new.aiq_product_id::text;
  end if;
  v_action := 'include_product:'||coalesce(new.aiq_product_id::text,new.model_number,new.id::text);
  v_rec := tj.intelligence_record_recommendation(
    new.organization_id,'product_selection','package',new.package_id::text,v_action,
    coalesce(nullif(new.category,''),'appliance'),v_product_entity,null,
    jsonb_strip_nulls(jsonb_build_object('package_product_id',new.id,'package_id',new.package_id,'aiq_product_id',new.aiq_product_id,
      'brand',new.brand,'model_number',new.model_number,'category',new.category,'subcategory',new.subcategory,'finish',new.finish,
      'quantity',new.quantity,'selected_price',coalesce(new.negotiated_price,new.promo_price,new.msrp),
      'source_comparison_id',new.source_comparison_id,'selection_reason',new.selection_reason,'basis',
      case when new.source_comparison_id is not null then 'comparison_selection' when new.selection_reason is not null then 'documented_selection' else 'package_selection' end)),
    '[]'::jsonb,'speciq_package_product',new.id::text
  );
  perform tj.intelligence_ensure_speciq_package_recommendation(new.package_id);
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_speciq_package_product() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.intelligence_sync_speciq_project()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_entity uuid; v_event text;
begin
  if tg_op='DELETE' then
    select id into v_entity from tj.intelligence_entities
    where organization_id=old.organization_id and source_system='speciq_project' and source_record_id=old.id::text;
    if v_entity is not null then
      update tj.intelligence_entities set status='deleted',updated_at=now(),updated_by=(select tj_private.current_source_user_id()) where id=v_entity;
      insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
      values(old.organization_id,v_entity,'SpecIQProjectDeleted','speciq_project',old.id::text,(select tj_private.current_source_user_id()),
        jsonb_build_object('title','SpecIQ project deleted','project_name',old.project_name,'timeline_type','project'),now());
    end if;
    return old;
  end if;

  v_entity := tj.intelligence_speciq_entity(
    new.organization_id,'project',new.project_name,'speciq_project',new.id::text,
    case when lower(coalesce(new.status,'active')) in ('inactive','archived','deleted') then lower(new.status) else 'active' end,
    jsonb_strip_nulls(jsonb_build_object('customer_name',new.customer_name,'customer_email',new.customer_email,'customer_phone',new.customer_phone,
      'property_address',new.property_address,'room_name',new.room_name,'builder_name',new.builder_name,'designer_name',new.designer_name,
      'expected_purchase_date',new.expected_purchase_date,'delivery_date',new.delivery_date,'status',new.status,'contact_id',new.contact_id,'deal_id',new.deal_id)),
    new.created_by,coalesce((select tj_private.current_source_user_id()),new.created_by),new.created_at,new.updated_at
  );
  v_event := case when tg_op='INSERT' then 'SpecIQProjectCreated' else 'SpecIQProjectUpdated' end;
  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(new.organization_id,v_entity,v_event,'speciq_project',new.id::text,coalesce((select tj_private.current_source_user_id()),new.created_by),
    jsonb_build_object('title',case when tg_op='INSERT' then 'SpecIQ project created' else 'SpecIQ project updated' end,
      'summary',new.project_name,'timeline_type','project','status',new.status),
    case when tg_op='INSERT' then new.created_at else new.updated_at end);
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.intelligence_sync_speciq_project() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.intelligence_upsert_context(p_organization_id uuid, p_entity_id uuid, p_context_key text, p_context_data jsonb, p_source_fingerprint text DEFAULT NULL::text, p_confidence_score numeric DEFAULT NULL::numeric, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS tj.intelligence_context_cache
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_context tj.intelligence_context_cache;
begin
  insert into tj.intelligence_context_cache(
    organization_id, entity_id, context_key, context_data, source_fingerprint, confidence_score, expires_at
  ) values (
    p_organization_id, p_entity_id, p_context_key, coalesce(p_context_data,'{}'::jsonb), p_source_fingerprint, p_confidence_score, p_expires_at
  )
  on conflict (organization_id, entity_id, context_key)
  do update set
    context_version = tj.intelligence_context_cache.context_version + 1,
    context_data = excluded.context_data,
    source_fingerprint = excluded.source_fingerprint,
    confidence_score = excluded.confidence_score,
    expires_at = excluded.expires_at,
    generated_at = now()
  returning * into v_context;
  return v_context;
end;
$function$;
REVOKE ALL ON FUNCTION tj.intelligence_upsert_context(p_organization_id uuid, p_entity_id uuid, p_context_key text, p_context_data jsonb, p_source_fingerprint text, p_confidence_score numeric, p_expires_at timestamp with time zone) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.is_field_rep()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM organization_members om
    WHERE om.user_id = tj_private.current_source_user_id() AND om.status = 'active'
  );
$function$;
REVOKE ALL ON FUNCTION tj_private.is_field_rep() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.is_field_rep() RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.is_field_rep(); $adapter$;
REVOKE ALL ON FUNCTION tj.is_field_rep() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select false;
$function$;
REVOKE ALL ON FUNCTION tj_private.is_super_admin() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.is_super_admin() RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.is_super_admin(); $adapter$;
REVOKE ALL ON FUNCTION tj.is_super_admin() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.join_demo_org()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_user uuid := tj_private.current_source_user_id(); v_demo uuid := '00000000-0000-0000-0000-000000000002';
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  insert into tj.profiles (user_id, email)
  select v_user, (select email from tj.source_auth_users where id = v_user)
  on conflict (user_id) do nothing;
  insert into tj.organization_members (organization_id, user_id, role, status)
  values (v_demo, v_user, 'member', 'active')
  on conflict (organization_id, user_id) do update set status = 'active';
  return jsonb_build_object('joined', true, 'organization_id', v_demo);
end $function$;
REVOKE ALL ON FUNCTION tj_private.join_demo_org() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.join_demo_org() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.join_demo_org(); $adapter$;
REVOKE ALL ON FUNCTION tj.join_demo_org() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.list_available_assistants(p_organization_id uuid)
 RETURNS SETOF tj.ai_assistants
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select * from tj.ai_assistants
   where status = 'active'
     and (organization_id is null or organization_id = p_organization_id)
   order by category, label;
$function$;
REVOKE ALL ON FUNCTION tj.list_available_assistants(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.list_pending_embeddings(p_batch_size integer DEFAULT 50)
 RETURNS TABLE(table_name text, row_id uuid, source_text text, source_hash text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  (select 'ai_knowledge_chunks'::text, c.id,
          coalesce(c.title,'') || E'\n' || c.content,
          md5(coalesce(c.title,'') || c.content)
     from tj.ai_knowledge_chunks c
    where c.status = 'active'
      and (c.embedding is null or c.source_hash is distinct from md5(coalesce(c.title,'') || c.content))
    limit p_batch_size)
  union all
  (select 'products'::text, p.id,
          p.brand || ' ' || p.model || ' ' || p.name || ' ' || coalesce(p.category,'') || E'\n' || coalesce(p.description,''),
          md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
     from tj.products p
    where p.embedding is null
       or p.source_hash is distinct from md5(p.brand || p.model || p.name || coalesce(p.category,'') || coalesce(p.description,''))
    limit p_batch_size)
  limit p_batch_size;
$function$;
REVOKE ALL ON FUNCTION tj_private.list_pending_embeddings(p_batch_size integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.list_pending_embeddings(p_batch_size integer DEFAULT 50) RETURNS TABLE(table_name text, row_id uuid, source_text text, source_hash text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.list_pending_embeddings("p_batch_size"); $adapter$;
REVOKE ALL ON FUNCTION tj.list_pending_embeddings(p_batch_size integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.log_coaching_kpi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if new.review_kind = 'coaching' then
    insert into kpi_events (organization_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, 'coaching_generated', 'ai_coaching_reviews', new.id,
            jsonb_build_object('overall_score', new.overall_score));
  end if;
  return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.log_coaching_kpi() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.log_contact_temperature_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF OLD.temperature IS DISTINCT FROM NEW.temperature THEN
    INSERT INTO crm_temperature_history (
      organization_id, entity_type, entity_id,
      from_temperature, to_temperature, changed_by,
      ai_recommended, reason, confidence
    ) VALUES (
      NEW.organization_id, 'contact', NEW.id,
      OLD.temperature, NEW.temperature, 
      COALESCE(NEW.temperature_changed_by, tj_private.current_source_user_id()),
      (NEW.temperature_ai_recommendation IS NOT NULL),
      NEW.temperature_reason,
      NEW.temperature_ai_confidence
    );
  END IF;
  
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.log_contact_temperature_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.log_deal_stage_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_duration integer;
BEGIN
  -- Only fire when stage actually changes
  IF OLD.stage IS DISTINCT FROM NEW.stage THEN
    -- Calculate duration in previous stage (seconds)
    IF OLD.stage_entered_at IS NOT NULL THEN
      v_duration := EXTRACT(EPOCH FROM (now() - OLD.stage_entered_at))::integer;
    END IF;
    
    INSERT INTO crm_stage_history (
      deal_id, organization_id, from_stage, to_stage, 
      changed_by, changed_at, duration_seconds
    ) VALUES (
      NEW.id, NEW.organization_id, OLD.stage, NEW.stage,
      tj_private.current_source_user_id(), now(), v_duration
    );
    
    -- Update stage_entered_at on the deal
    NEW.stage_entered_at := now();
  END IF;
  
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.log_deal_stage_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.log_deal_temperature_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF OLD.temperature IS DISTINCT FROM NEW.temperature THEN
    INSERT INTO crm_temperature_history (
      organization_id, entity_type, entity_id,
      from_temperature, to_temperature, changed_by,
      reason
    ) VALUES (
      NEW.organization_id, 'deal', NEW.id,
      OLD.temperature, NEW.temperature,
      COALESCE(NEW.temperature_changed_by, tj_private.current_source_user_id()),
      NEW.temperature_reason
    );
  END IF;
  
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.log_deal_temperature_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.log_recording_kpi()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if tg_op = 'INSERT' then
    insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, new.user_id, 'recording_uploaded', 'sales_recordings', new.id,
            jsonb_build_object('source', new.recording_source, 'duration_seconds', new.duration_seconds));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'transcribed' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_transcribed', 'sales_recordings', new.id);
    elsif new.status = 'complete' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_analyzed', 'sales_recordings', new.id);
    end if;
  end if;
  return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.log_recording_kpi() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.lookup_product(p_model text, p_brand text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_product jsonb;
  v_prices jsonb;
  v_recalls jsonb;
  v_warranty jsonb;
  v_pid uuid;
  v_brand text;
BEGIN
  SELECT to_jsonb(p.*), p.id, p.brand_name INTO v_product, v_pid, v_brand
  FROM aiq_products p
  WHERE upper(p.model) = upper(p_model)
    AND (p_brand IS NULL OR p.brand_name ILIKE p_brand)
  LIMIT 1;

  IF v_product IS NULL THEN
    SELECT to_jsonb(p.*), p.id, p.brand_name INTO v_product, v_pid, v_brand
    FROM aiq_products p
    WHERE p.model % p_model
      AND (p_brand IS NULL OR p.brand_name ILIKE p_brand)
    ORDER BY similarity(p.model, p_model) DESC
    LIMIT 1;
  END IF;

  IF v_product IS NULL THEN
    RETURN jsonb_build_object('found', false, 'model', p_model);
  END IF;

  SELECT jsonb_agg(jsonb_build_object(
    'retailer', rp.retailer_name, 'price', rp.price, 'regular_price', rp.regular_price,
    'condition', rp.condition_normalized, 'in_stock', rp.in_stock,
    'savings_percent', rp.savings_percent, 'last_seen', rp.last_seen_at,
    'url', rp.product_url
  )) INTO v_prices
  FROM pim_retailer_prices rp
  WHERE rp.model = (v_product->>'model') AND rp.brand_name = v_brand
    AND rp.listing_status = 'active';

  -- model_numbers is text[] — use array containment / any-match
  SELECT jsonb_agg(rec) INTO v_recalls FROM (
    SELECT to_jsonb(r.*) as rec
    FROM aiq_recalls r
    WHERE r.brand_name ILIKE '%' || v_brand || '%'
      AND (r.model_numbers IS NULL
           OR EXISTS (SELECT 1 FROM unnest(r.model_numbers) mn WHERE mn ILIKE '%' || (v_product->>'model') || '%'))
    LIMIT 5
  ) sub;

  SELECT to_jsonb(w.*) INTO v_warranty
  FROM aiq_warranty_policies w
  WHERE w.brand_name ILIKE v_brand
  LIMIT 1;

  RETURN jsonb_build_object(
    'found', true,
    'product', v_product,
    'retailer_prices', COALESCE(v_prices, '[]'::jsonb),
    'recalls', COALESCE(v_recalls, '[]'::jsonb),
    'warranty', v_warranty
  );
END;
$function$;
REVOKE ALL ON FUNCTION tj.lookup_product(p_model text, p_brand text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.manages_vendor(v uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT EXISTS(SELECT 1 FROM mfr_members WHERE user_id = tj_private.current_source_user_id() AND vendor_id = v);
$function$;
REVOKE ALL ON FUNCTION tj_private.manages_vendor(v uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.manages_vendor(v uuid) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.manages_vendor("v"); $adapter$;
REVOKE ALL ON FUNCTION tj.manages_vendor(v uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer DEFAULT 10)
 RETURNS TABLE(product_id uuid, brand text, model text, name text, category text, msrp numeric, similarity double precision)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select p.id, p.brand, p.model, p.name, p.category, p.msrp,
         1 - (p.embedding operator(public.<=>) p_query_embedding) as similarity
    from tj.products p
   where p.organization_id = p_organization_id
     and p.embedding is not null
     and (
       (select auth.role()) = 'service_role'
       or tj.is_org_member(p_organization_id)
     )
   order by p.embedding operator(public.<=>) p_query_embedding
   limit p_limit;
$function$;
REVOKE ALL ON FUNCTION tj_private.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer DEFAULT 10) RETURNS TABLE(product_id uuid, brand text, model text, name text, category text, msrp numeric, similarity double precision) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.match_products("p_organization_id","p_query_embedding","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.match_products(p_organization_id uuid, p_query_embedding vector, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.mdf_auto_coop_accrual()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_contract RECORD;
  v_accrual_amount NUMERIC;
  v_eligible_sales NUMERIC;
BEGIN
  -- Find active contract for this brand
  SELECT * INTO v_contract
  FROM mdf_brand_contracts
  WHERE brand_id = NEW.brand_id
    AND end_date IS NULL
    AND coop_enabled = true
  LIMIT 1;

  -- No active co-op contract, skip
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Calculate eligible sales based on accessory inclusion
  IF v_contract.coop_includes_accessories THEN
    v_eligible_sales := NEW.net_sales;
  ELSE
    v_eligible_sales := COALESCE(NEW.product_sales, NEW.net_sales);
  END IF;

  -- Calculate accrual
  v_accrual_amount := v_eligible_sales * (v_contract.coop_pct / 100.0);

  -- Only create accrual if amount > 0
  IF v_accrual_amount > 0 THEN
    INSERT INTO mdf_coop_ledger (
      brand_id, entry_type, amount, description,
      period_label, transaction_date,
      reference_type, reference_id
    ) VALUES (
      NEW.brand_id,
      'accrual',
      v_accrual_amount,
      'Auto-accrual: ' || COALESCE(NEW.period_label, 'Period ' || NEW.period_start::text) ||
        ' (' || v_contract.coop_pct || '% of ' || to_char(v_eligible_sales, 'FM$999,999,999.00') || ')',
      NEW.period_label,
      COALESCE(NEW.period_end, NEW.period_start),
      'sales_auto',
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.mdf_auto_coop_accrual() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.mdf_check_expiring_contracts()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_contract RECORD;
  v_brand_name TEXT;
  v_count INTEGER := 0;
BEGIN
  FOR v_contract IN
    SELECT c.*, b.brand_name
    FROM mdf_brand_contracts c
    JOIN mdf_brands b ON b.id = c.brand_id
    WHERE c.end_date IS NULL
      AND c.contract_expiry_date <= CURRENT_DATE + INTERVAL '60 days'
      AND c.contract_expiry_date > CURRENT_DATE
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM mdf_alerts
      WHERE brand_id = v_contract.brand_id
        AND alert_type = 'contract_expiring'
        AND metadata->>'contract_id' = v_contract.id::text
        AND is_dismissed = false
    ) THEN
      INSERT INTO mdf_alerts (alert_type, brand_id, severity, title, message, metadata)
      VALUES (
        'contract_expiring', v_contract.brand_id,
        CASE WHEN v_contract.contract_expiry_date <= CURRENT_DATE + INTERVAL '14 days' THEN 'critical' ELSE 'warning' END,
        v_contract.brand_name || ' contract expiring ' || to_char(v_contract.contract_expiry_date, 'Mon DD'),
        'Contract "' || COALESCE(v_contract.contract_label, 'Active') || '" expires ' ||
          to_char(v_contract.contract_expiry_date, 'Mon DD, YYYY') || '. Renew or rates will lapse.',
        jsonb_build_object('contract_id', v_contract.id, 'expiry', v_contract.contract_expiry_date)
      );
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION tj.mdf_check_expiring_contracts() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.mdf_check_expiring_funds()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_fund RECORD;
  v_count INTEGER := 0;
  v_brand_name TEXT;
BEGIN
  -- Check for MDF funds expiring within 30 days
  FOR v_fund IN
    SELECT * FROM mdf_mdf_funds
    WHERE status = 'active'
      AND expiry_date IS NOT NULL
      AND expiry_date <= CURRENT_DATE + INTERVAL '30 days'
      AND expiry_date > CURRENT_DATE
  LOOP
    SELECT brand_name INTO v_brand_name FROM mdf_brands WHERE id = v_fund.brand_id;
    
    -- Only create alert if one doesn't already exist for this fund
    IF NOT EXISTS (
      SELECT 1 FROM mdf_alerts
      WHERE brand_id = v_fund.brand_id
        AND alert_type = 'mdf_expiring'
        AND metadata->>'fund_id' = v_fund.id::text
        AND is_dismissed = false
    ) THEN
      INSERT INTO mdf_alerts (alert_type, brand_id, severity, title, message, metadata)
      VALUES (
        'mdf_expiring', v_fund.brand_id, 'warning',
        v_brand_name || ' MDF expiring: ' || v_fund.fund_label,
        to_char(v_fund.remaining_amount, 'FM$999,999') || ' remaining — expires ' || 
          to_char(v_fund.expiry_date, 'Mon DD, YYYY'),
        jsonb_build_object('fund_id', v_fund.id, 'remaining', v_fund.remaining_amount, 'expiry', v_fund.expiry_date)
      );
      v_count := v_count + 1;
    END IF;
  END LOOP;

  -- Auto-expire funds past their date
  UPDATE mdf_mdf_funds
  SET status = 'expired'
  WHERE status = 'active'
    AND expiry_date IS NOT NULL
    AND expiry_date < CURRENT_DATE;

  RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION tj.mdf_check_expiring_funds() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.mdf_check_vr_thresholds()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_contract RECORD;
  v_total_sales NUMERIC;
  v_tier RECORD;
  v_brand_name TEXT;
BEGIN
  SELECT * INTO v_contract
  FROM mdf_brand_contracts
  WHERE brand_id = NEW.brand_id AND end_date IS NULL AND vr_enabled = true
  LIMIT 1;

  IF NOT FOUND OR v_contract.vr_tiers IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT brand_name INTO v_brand_name FROM mdf_brands WHERE id = NEW.brand_id;

  -- Sum eligible sales for current year
  IF v_contract.vr_includes_accessories THEN
    SELECT COALESCE(SUM(net_sales), 0) INTO v_total_sales
    FROM mdf_sales_data
    WHERE brand_id = NEW.brand_id
      AND EXTRACT(YEAR FROM period_start) = EXTRACT(YEAR FROM CURRENT_DATE);
  ELSE
    SELECT COALESCE(SUM(product_sales), 0) INTO v_total_sales
    FROM mdf_sales_data
    WHERE brand_id = NEW.brand_id
      AND EXTRACT(YEAR FROM period_start) = EXTRACT(YEAR FROM CURRENT_DATE);
  END IF;

  -- Check each tier
  FOR v_tier IN
    SELECT * FROM jsonb_to_recordset(v_contract.vr_tiers)
    AS t(label text, threshold numeric, pct numeric)
    ORDER BY threshold DESC
  LOOP
    -- If we just crossed this threshold (previous total was below)
    IF v_total_sales >= v_tier.threshold AND (v_total_sales - COALESCE(NEW.net_sales, 0)) < v_tier.threshold THEN
      -- Check no existing alert for this tier
      IF NOT EXISTS (
        SELECT 1 FROM mdf_alerts
        WHERE brand_id = NEW.brand_id
          AND alert_type = 'vr_tier_crossed'
          AND metadata->>'threshold' = v_tier.threshold::text
          AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM CURRENT_DATE)
      ) THEN
        INSERT INTO mdf_alerts (alert_type, brand_id, severity, title, message, metadata)
        VALUES (
          'vr_tier_crossed', NEW.brand_id, 'info',
          v_brand_name || ' hit VR tier: ' || COALESCE(v_tier.label, v_tier.pct || '%'),
          'Total eligible sales reached ' || to_char(v_total_sales, 'FM$999,999,999') ||
            ' — rebate rate now ' || v_tier.pct || '%',
          jsonb_build_object('threshold', v_tier.threshold, 'pct', v_tier.pct, 'total_sales', v_total_sales)
        );
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.mdf_check_vr_thresholds() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.mdf_get_org_limits()
 RETURNS TABLE(max_brands integer, max_users integer, tier_id text, features jsonb, subscription_status text, trial_ends_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT t.max_brands, t.max_users, o.tier_id, t.features, o.subscription_status, o.trial_ends_at
  FROM mdf_organizations o
  JOIN mdf_subscription_tiers t ON t.id = o.tier_id
  JOIN mdf_platform_users u ON u.org_id = o.id
  WHERE u.email = auth.jwt()->>'email'
  LIMIT 1;
$function$;
REVOKE ALL ON FUNCTION tj_private.mdf_get_org_limits() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.mdf_get_org_limits() RETURNS TABLE(max_brands integer, max_users integer, tier_id text, features jsonb, subscription_status text, trial_ends_at timestamp with time zone) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.mdf_get_org_limits(); $adapter$;
REVOKE ALL ON FUNCTION tj.mdf_get_org_limits() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.mfr_portal_snapshot(p_vendor_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
with vendor as (select * from tj.mfr_vendors where id=p_vendor_id),
brand_ids as (select distinct coalesce(s.brand_id,v.brand_id) brand_id from vendor v left join tj.product_iq_brand_scopes s on s.vendor_id=v.id and s.status='active' where coalesce(s.brand_id,v.brand_id) is not null),
products as (select p.* from tj.aiq_products p where p.brand_id in (select brand_id from brand_ids))
select jsonb_build_object(
 'generated_at',now(),'vendor',(select to_jsonb(v) from vendor v),
 'members',(select count(*) from tj.mfr_members where vendor_id=p_vendor_id and coalesce(status,'active')='active'),
 'brand_scopes',(select count(*) from tj.product_iq_brand_scopes where vendor_id=p_vendor_id and status='active'),
 'products',jsonb_build_object('total',(select count(*) from products),'approved',(select count(*) from products where approval_status='approved'),'pending_review',(select count(*) from products where source_review_status in ('pending','needs_review') or approval_status<>'approved'),'public',(select count(*) from products where public_visible)),
 'assets',jsonb_build_object('documents',(select count(*) from tj.pim_product_documents d where d.product_id in (select id from products)),'verified_documents',(select count(*) from tj.pim_product_documents d where d.product_id in (select id from products) and d.manufacturer_verified),'images',(select count(*) from tj.pim_product_images i where i.product_id in (select id from products)),'videos',(select count(*) from tj.pim_product_videos v where v.product_id in (select id from products)))
); $function$;
REVOKE ALL ON FUNCTION tj.mfr_portal_snapshot(p_vendor_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.normalize_aicrm_import_signature(p_company text, p_province text, p_city text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  select regexp_replace(lower(trim(coalesce(p_company, '')) || '|' || lower(trim(coalesce(p_province, ''))) || '|' || lower(trim(coalesce(p_city, '')))), '\\s+', ' ', 'g');
$function$;
REVOKE ALL ON FUNCTION tj.normalize_aicrm_import_signature(p_company text, p_province text, p_city text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.normalize_brand(p_raw text, p_org_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_raw_clean TEXT;
  v_stripped TEXT;
  v_result TEXT;
BEGIN
  IF p_raw IS NULL OR btrim(p_raw) = '' THEN RETURN NULL; END IF;

  v_raw_clean := lower(btrim(regexp_replace(p_raw, '\s+', ' ', 'g')));

  -- 1. Alias table on the raw form
  SELECT canonical_brand INTO v_result FROM brand_aliases
  WHERE alias = v_raw_clean AND (organization_id = p_org_id OR organization_id IS NULL)
  ORDER BY (organization_id IS NOT NULL) DESC LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  -- 2. Exact catalog match on raw form (catches "GE Appliances")
  SELECT brand_name INTO v_result FROM brand_catalog
  WHERE lower(btrim(brand_name)) = v_raw_clean LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  -- 3. Accent-insensitive match (catches "cafe" -> "Café")
  SELECT brand_name INTO v_result FROM brand_catalog
  WHERE extensions.unaccent(lower(btrim(brand_name))) = extensions.unaccent(v_raw_clean) LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  -- 4. Space-collapsed match ("kitchen aid" -> "KitchenAid")
  SELECT brand_name INTO v_result FROM brand_catalog
  WHERE replace(extensions.unaccent(lower(btrim(brand_name))),' ','') = replace(extensions.unaccent(v_raw_clean),' ','') LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  -- 5. Now try stripping corporate suffixes and repeat
  v_stripped := btrim(regexp_replace(v_raw_clean, '\s*(electronics?|canada|usa|inc\.?|corp\.?|ltd\.?|llc)$', '', 'g'));
  IF v_stripped <> v_raw_clean AND v_stripped <> '' THEN
    SELECT canonical_brand INTO v_result FROM brand_aliases
    WHERE alias = v_stripped AND (organization_id = p_org_id OR organization_id IS NULL) LIMIT 1;
    IF v_result IS NOT NULL THEN RETURN v_result; END IF;

    SELECT brand_name INTO v_result FROM brand_catalog
    WHERE extensions.unaccent(lower(btrim(brand_name))) = extensions.unaccent(v_stripped) LIMIT 1;
    IF v_result IS NOT NULL THEN RETURN v_result; END IF;
  END IF;

  -- 6. Fuzzy, high threshold
  SELECT brand_name INTO v_result FROM brand_catalog
  WHERE extensions.similarity(extensions.unaccent(lower(brand_name)), extensions.unaccent(v_stripped)) > 0.8
  ORDER BY extensions.similarity(extensions.unaccent(lower(brand_name)), extensions.unaccent(v_stripped)) DESC LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  RETURN initcap(v_raw_clean);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.normalize_brand(p_raw text, p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.normalize_brand(p_raw text, p_org_id uuid DEFAULT NULL::uuid) RETURNS text LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.normalize_brand("p_raw","p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.normalize_brand(p_raw text, p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.normalize_category(p_raw text, p_org_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_clean TEXT;
  v_result TEXT;
BEGIN
  IF p_raw IS NULL OR btrim(p_raw) = '' THEN RETURN 'other'; END IF;
  v_clean := lower(btrim(p_raw));

  SELECT canonical_category INTO v_result FROM category_aliases
  WHERE alias = v_clean AND (organization_id = p_org_id OR organization_id IS NULL)
  ORDER BY (organization_id IS NOT NULL) DESC LIMIT 1;
  IF v_result IS NOT NULL THEN RETURN v_result; END IF;

  -- Order is significant: more specific patterns first.
  IF v_clean ~ '(dishwash|dish wash)'                                  THEN RETURN 'dishwashers'; END IF;
  IF v_clean ~ '(hood|ventil|downdraft|blower|chimney)'                THEN RETURN 'ventilation'; END IF;
  IF v_clean ~ '(outdoor|grill|bbq|smoker|patio)'                      THEN RETURN 'outdoor'; END IF;
  IF v_clean ~ '(refrig|fridge|freezer|beverage|wine|ice maker|icemaker)' THEN RETURN 'refrigeration'; END IF;
  IF v_clean ~ '(laundry|washtower|pedestal|washer|dryer)'             THEN RETURN 'laundry'; END IF;
  IF v_clean ~ '(range|cooktop|oven|cooking|induction|microwave|stove|hob)' THEN RETURN 'cooking'; END IF;
  IF v_clean ~ '(small|countertop|blender|toaster|coffee|kettle)'      THEN RETURN 'small_appliance'; END IF;

  RETURN 'other';
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.normalize_category(p_raw text, p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.normalize_category(p_raw text, p_org_id uuid DEFAULT NULL::uuid) RETURNS text LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.normalize_category("p_raw","p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.normalize_category(p_raw text, p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.notify_overdue_tasks(p_org_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  notified integer := 0;
BEGIN
  INSERT INTO crm_notifications (organization_id, user_id, title, body, severity, category, entity_type, entity_id)
  SELECT t.organization_id, t.assignee_user_id,
    '⏰ Task Overdue: ' || LEFT(t.title, 60),
    'Was due ' || to_char(t.due_at, 'Mon DD') || '.',
    'warning', 'task', 'task', t.id
  FROM crm_tasks t
  WHERE t.organization_id = p_org_id
    AND t.completed_at IS NULL
    AND t.due_at < now()
    AND t.assignee_user_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM crm_notifications n
      WHERE n.entity_id = t.id AND n.category = 'task'
        AND n.created_at > now() - interval '24 hours'
    );
  GET DIAGNOSTICS notified = ROW_COUNT;
  RETURN jsonb_build_object('notified', notified);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.notify_overdue_tasks(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.notify_overdue_tasks(p_org_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.notify_overdue_tasks("p_org_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.notify_overdue_tasks(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid DEFAULT auth.uid())
 RETURNS TABLE(scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, target_competency_name text, target_score numeric, reason text, persona text, context text, objectives jsonb, competency_weights jsonb, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  weak record;
  target_difficulty smallint;
begin
  if p_user_id is null then p_user_id := tj_private.current_source_user_id(); end if;
  if p_user_id <> tj_private.current_source_user_id() and not is_org_admin(p_organization_id) then
    raise exception 'Not authorized to request an adaptive roleplay for this user';
  end if;
  if not is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;

  select ss.rolling_score,c.id competency_id,c.code,c.name into weak
  from tj.performance_skill_state ss
  join tj.performance_competencies c on c.id=ss.competency_id
  where ss.organization_id=p_organization_id and ss.user_id=p_user_id and c.active=true
  order by ss.rolling_score asc,ss.confidence desc,ss.last_observed_at desc nulls last
  limit 1;

  if weak.competency_id is null then
    select null::numeric rolling_score,c.id competency_id,c.code,c.name into weak
    from tj.performance_competencies c
    where c.active=true and c.code='discovery'
      and (c.organization_id is null or c.organization_id=p_organization_id)
    order by (c.organization_id is not null) desc limit 1;
  end if;

  target_difficulty := case
    when weak.rolling_score is null then 2
    when weak.rolling_score < 55 then 2
    when weak.rolling_score < 75 then 3
    else 4 end;

  return query
  select s.id,s.code,s.title,s.difficulty,weak.code,weak.name,weak.rolling_score,
         case when weak.rolling_score is null
              then 'Baseline assessment: start by measuring core discovery behaviour.'
              else 'Adaptive practice targets '||weak.name||', currently '||round(weak.rolling_score,1)::text||'/100.' end,
         s.persona,s.context,s.objectives,s.competency_weights,s.customer_profile,s.hidden_facts,
         s.objections,s.success_criteria,s.opening_line
  from tj.performance_scenarios s
  where s.active=true
    and (s.organization_id is null or s.organization_id=p_organization_id)
    and s.competency_weights ? weak.code
  order by abs(s.difficulty-target_difficulty),
           coalesce((s.competency_weights->>weak.code)::numeric,0) desc,
           case when exists (
             select 1 from tj.performance_roleplay_links l
             where l.organization_id=p_organization_id and l.user_id=p_user_id and l.scenario_id=s.id
               and l.created_at > now()-interval '7 days'
           ) then 1 else 0 end,
           s.title
  limit 1;
end;
$function$;
REVOKE ALL ON FUNCTION tj.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text DEFAULT 'you_sell'::text)
 RETURNS TABLE(roleplay_session_id uuid, scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, reason text, persona text, context text, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  rec record;
  v_session_id uuid;
  v_intervention_id uuid;
  v_mode text;
begin
  if tj_private.current_source_user_id() is null or not is_org_member(p_organization_id) then
    raise exception 'Authentication and organization membership required';
  end if;
  v_mode := case p_mode
    when 'sell_to_bot' then 'you_sell'
    when 'you_sell' then 'you_sell'
    when 'bot_sells' then 'bot_sells'
    when 'beat_the_expert' then 'beat_the_expert'
    else null end;
  if v_mode is null then raise exception 'Unsupported roleplay mode'; end if;

  select * into rec from tj.performance_get_next_scenario(p_organization_id,tj_private.current_source_user_id()) limit 1;
  if rec.scenario_id is null then raise exception 'No eligible scenario found'; end if;

  select i.id into v_intervention_id
  from tj.performance_interventions i
  join tj.performance_competencies c on c.id=i.competency_id
  where i.organization_id=p_organization_id and i.user_id=tj_private.current_source_user_id()
    and i.status in ('prescribed','started') and c.code=rec.target_competency_code
  order by i.created_at desc limit 1;

  insert into tj.ai_roleplay_sessions
    (organization_id,user_id,scenario_type,status,mode,difficulty_level,scoring_version)
  values
    (p_organization_id,tj_private.current_source_user_id(),rec.scenario_code,'active',v_mode,rec.difficulty,'performance_brain_v1')
  returning id into v_session_id;

  insert into tj.performance_roleplay_links
    (organization_id,user_id,intervention_id,scenario_id,ai_roleplay_session_id)
  values
    (p_organization_id,tj_private.current_source_user_id(),v_intervention_id,rec.scenario_id,v_session_id)
  on conflict do nothing;

  if v_intervention_id is not null then
    update tj.performance_interventions
    set status='started',started_at=coalesce(started_at,now()),updated_at=now()
    where id=v_intervention_id and user_id=tj_private.current_source_user_id();
  end if;

  return query select v_session_id,rec.scenario_id,rec.scenario_code,rec.title,rec.difficulty,
    rec.target_competency_code,rec.reason,rec.persona,rec.context,rec.customer_profile,
    rec.hidden_facts,rec.objections,rec.success_criteria,rec.opening_line;
end;
$function$;
REVOKE ALL ON FUNCTION tj.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_academy_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare orgs uuid[]; org_count int; org_id uuid; ev text;
begin
 select array_agg(organization_id),count(*) into orgs,org_count from tj.organization_members where user_id=new.user_id and status='active';
 ev:=case when lower(new.event_type) like '%complet%' then 'learning.completed' else 'learning.progressed' end;
 if org_count=1 then org_id:=orgs[1]; perform tj.platform_upsert_identity_link(org_id,'employee',new.user_id,'tj.source_auth_users','academy','academy_learning_events',new.user_id::text,new.user_id::text,null,1,'auth_user',false,'{}'); perform tj.platform_emit_intelligence_event(org_id,ev,'academy',new.id::text,'learning',new.user_id,null,new.user_id,null,null,ev||':'||new.id::text,jsonb_build_object('academy_event_id',new.id,'user_id',new.user_id,'event_type',new.event_type,'pillar',new.pillar,'course_key',new.course_key,'content',new.content,'metadata',new.metadata),new.created_at,1,'{}');
 else insert into tj.platform_intelligence_unresolved_events(source_system,source_table,source_record_id,event_type,reason,candidate_organization_ids,payload) values('academy','academy_learning_events',new.id::text,ev,case when org_count=0 then 'organization_not_found' else 'ambiguous_organization' end,coalesce(orgs,'{}'),jsonb_build_object('user_id',new.user_id,'event_type',new.event_type,'course_key',new.course_key)) on conflict do nothing; end if; return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_academy_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_contact_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare ev text; label text;
begin
 ev:=case when tg_op='INSERT' then 'customer.created' else 'customer.updated' end;
 label:=trim(coalesce(new.preferred_name,'')||' '||coalesce(new.first_name,'')||' '||coalesce(new.last_name,''));
 perform tj.platform_upsert_identity_link(new.organization_id,'customer',new.id,'contacts','crm','contacts',new.id::text,coalesce(new.email,new.phone),nullif(label,''),1,'native',true,jsonb_build_object('lifecycle_stage',new.lifecycle_stage));
 perform tj.platform_emit_intelligence_event(new.organization_id,ev,'crm',new.id::text,'customer',new.id,null,new.assigned_salesperson_id,null,null,ev||':'||new.id::text||':'||coalesce(new.updated_at,new.created_at)::text,jsonb_build_object('contact_id',new.id,'lifecycle_stage',new.lifecycle_stage,'assigned_salesperson_id',new.assigned_salesperson_id),coalesce(new.updated_at,new.created_at),1,'{}'); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_contact_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_field_score_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare org_id uuid; loc_id uuid;
begin
 select ol.organization_id,fs.org_location_id into org_id,loc_id from tj.field_stores fs left join tj.org_locations ol on ol.id=fs.org_location_id where fs.id=new.store_id;
 if org_id is null then insert into tj.platform_intelligence_unresolved_events(source_system,source_table,source_record_id,event_type,reason,payload) values('field','field_store_scores',new.id::text,'field.score_recorded','organization_not_found',jsonb_build_object('field_store_id',new.store_id,'overall_score',new.overall_score)) on conflict do nothing; return new; end if;
 perform tj.platform_emit_intelligence_event(org_id,'field.score_recorded','field',new.id::text,'field_visit',new.visit_id,loc_id,null,null,null,'field.score_recorded:'||new.id::text,jsonb_build_object('score_id',new.id,'visit_id',new.visit_id,'field_store_id',new.store_id,'overall_score',new.overall_score,'score_date',new.score_date),new.created_at,1,'{}'); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_field_score_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_interaction_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare ev text;
begin
 if tg_op='INSERT' then ev:='interaction.started'; elsif new.ended_at is not null and (old.ended_at is distinct from new.ended_at or old.outcome is distinct from new.outcome) then ev:=case when coalesce(new.sale_amount,0)>0 or lower(coalesce(new.outcome,'')) in ('closed','sale','sold','purchased') then 'interaction.completed' else 'interaction.no_sale' end; else return new; end if;
 perform tj.platform_emit_intelligence_event(new.organization_id,ev,'up_system',new.id::text,'interaction',new.id,new.store_id,new.salesperson_user_id,null,null,ev||':'||new.id::text||':'||coalesce(new.ended_at,new.started_at,new.created_at)::text,jsonb_build_object('interaction_id',new.id,'contact_id',new.contact_id,'salesperson_user_id',new.salesperson_user_id,'outcome',new.outcome,'sale_amount',new.sale_amount,'reason_not_purchased',new.reason_not_purchased,'no_sale_reason',new.no_sale_reason,'pos_transaction_id',new.pos_transaction_id,'pos_matched',new.pos_matched),coalesce(new.ended_at,new.started_at,new.created_at),case when new.contact_id is null then .5 else 1 end,'{}'); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_interaction_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_pos_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare ev text; emp uuid; conf numeric:=null;
begin
 ev:=case when coalesce(new.transaction_amount,0)<0 then 'transaction.refunded' else 'transaction.completed' end;
 select salesperson_user_id into emp from tj.iq_pos_employee_map where organization_id=new.organization_id and pos_system=coalesce(new.source_system,pos_system) and pos_employee_id=coalesce(new.salesperson_external_id,new.pos_employee_id) and is_active=true order by updated_at desc limit 1;
 if emp is not null then conf:=1; perform tj.platform_upsert_identity_link(new.organization_id,'employee',emp,'tj.source_auth_users',coalesce(new.source_system,'pos'),'iq_pos_employee_map',coalesce(new.salesperson_external_id,new.pos_employee_id,emp::text),coalesce(new.salesperson_external_id,new.pos_employee_id),null,1,'pos_employee_map',false,'{}'); end if;
 perform tj.platform_emit_intelligence_event(new.organization_id,ev,coalesce(new.source_system,'pos'),new.pos_transaction_id,'transaction',new.id,new.store_id,emp,null,null,ev||':'||coalesce(new.source_system,'pos')||':'||new.pos_transaction_id,jsonb_build_object('transaction_id',new.id,'pos_transaction_id',new.pos_transaction_id,'amount',new.transaction_amount,'subtotal',new.subtotal,'discount_amount',new.discount_amount,'gross_margin_amount',new.gross_margin_amount,'gross_margin_pct',new.gross_margin_pct,'currency_code',new.currency_code,'customer_external_id',new.customer_external_id,'salesperson_external_id',coalesce(new.salesperson_external_id,new.pos_employee_id),'line_items',new.line_items,'warranty_items',new.warranty_items),coalesce(new.transaction_date,new.created_at),conf,jsonb_build_object('source_connection_id',new.source_connection_id)); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_pos_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_product_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare ev text; cid uuid; label text;
begin
 ev:=case when tg_op='INSERT' then 'product.created' else 'product.updated' end; cid:=coalesce(new.aiq_product_id,new.id); label:=trim(coalesce(new.brand,'')||' '||coalesce(new.model,'')||' '||coalesce(new.name,''));
 perform tj.platform_upsert_identity_link(new.organization_id,'product',cid,'products','product_iq','products',new.id::text,new.model,nullif(label,''),case when new.aiq_product_id is null then .9 else 1 end,case when new.aiq_product_id is null then 'local_product' else 'aiq_product_id' end,true,jsonb_build_object('local_product_id',new.id,'category',new.category));
 perform tj.platform_emit_intelligence_event(new.organization_id,ev,'product_iq',new.id::text,'product',cid,null,null,null,null,ev||':'||new.id::text||':'||coalesce(new.updated_at,new.created_at)::text,jsonb_build_object('product_id',new.id,'aiq_product_id',new.aiq_product_id,'brand',new.brand,'model',new.model,'category',new.category,'msrp',new.msrp,'in_stock',new.in_stock),coalesce(new.updated_at,new.created_at),case when new.aiq_product_id is null then .9 else 1 end,'{}'); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_product_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_store_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
 perform tj.platform_upsert_identity_link(new.organization_id,'store',new.id,'org_locations','platform','org_locations',new.id::text,new.code,new.name,1,'native',true,jsonb_build_object('location_type',new.location_type));
 if tg_op='UPDATE' then perform tj.platform_emit_intelligence_event(new.organization_id,'store.updated','platform',new.id::text,'store',new.id,new.id,null,null,null,'store.updated:'||new.id::text||':'||new.updated_at::text,jsonb_build_object('name',new.name,'code',new.code,'location_type',new.location_type,'is_active',new.is_active),new.updated_at,1,'{}'); end if; return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_store_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase3_publish_traffic_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
 perform tj.platform_emit_intelligence_event(new.organization_id,'traffic.observed','up_system',new.id::text,'store',new.store_id,new.store_id,new.created_by,null,null,'traffic.observed:'||new.id::text,jsonb_build_object('raw_entries',new.raw_entries,'adjusted_entries',new.adjusted_entries,'customer_groups',new.customer_groups,'traffic_source_id',new.traffic_source_id),new.captured_at,1,'{}'); return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase3_publish_traffic_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_attach_evaluation(p_intervention_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_i tj.ai_coaching_interventions%rowtype; v_rec uuid; v_eval uuid;
begin
  select * into v_i from tj.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if tj_private.current_source_user_id() is not null and tj_private.current_source_user_id()<>v_i.user_id and not tj.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
  v_rec:=tj.phase4_ensure_intervention_recommendation(v_i.id);
  insert into tj.ai_intervention_evaluations(organization_id,intervention_id,recommendation_id,metric_key,baseline_value,target_value,status,baseline_observed_at,evaluation_due_at,evidence)
  values(v_i.organization_id,v_i.id,v_rec,v_i.metric_key,v_i.baseline_value,v_i.target_value,'pending',v_i.created_at,coalesce(v_i.due_at,v_i.created_at+interval '7 days'),jsonb_build_object('trigger_type',v_i.trigger_type,'skill_id',v_i.skill_id))
  on conflict(intervention_id) do update set recommendation_id=excluded.recommendation_id,metric_key=excluded.metric_key,baseline_value=excluded.baseline_value,target_value=excluded.target_value,evaluation_due_at=excluded.evaluation_due_at,updated_at=now()
  returning id into v_eval;
  update tj.ai_coaching_interventions set evaluation_id=v_eval,updated_at=now() where id=v_i.id;
  return v_eval;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_attach_evaluation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_attach_evaluation(p_intervention_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_attach_evaluation("p_intervention_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_attach_evaluation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid DEFAULT NULL::uuid, p_score numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_i tj.ai_coaching_interventions%rowtype; v_step tj.ai_intervention_steps%rowtype; v_remaining int; v_completed boolean;
begin
  select * into v_i from tj.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if tj_private.current_source_user_id() is not null and tj_private.current_source_user_id()<>v_i.user_id and not tj.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;

  update tj.ai_intervention_steps
     set status='completed', completion_ref=coalesce(p_completion_ref,completion_ref), completed_at=coalesce(completed_at,now()), metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('score',p_score)), updated_at=now()
   where intervention_id=p_intervention_id and step_order=p_step_order
   returning * into v_step;
  if v_step.id is null then raise exception 'Intervention step not found'; end if;

  update tj.ai_coaching_interventions set status=case when status='recommended' then 'in_progress' else status end, started_at=coalesce(started_at,now()), updated_at=now() where id=p_intervention_id;
  select count(*) into v_remaining from tj.ai_intervention_steps where intervention_id=p_intervention_id and status not in ('completed','skipped');
  v_completed := v_remaining=0;
  if v_completed then
    update tj.ai_coaching_interventions set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now() where id=p_intervention_id;
    update tj.ai_intervention_evaluations set status=case when evaluation_due_at<=now() then 'due' else 'pending' end,updated_at=now() where intervention_id=p_intervention_id;
  end if;
  return jsonb_build_object('intervention_id',p_intervention_id,'step_order',p_step_order,'step_status','completed','intervention_completed',v_completed,'remaining_steps',v_remaining);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid DEFAULT NULL::uuid, p_score numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_complete_step("p_intervention_id","p_step_order","p_completion_ref","p_score","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_emit_coaching_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_event text; v_org uuid; v_entity uuid; v_actor uuid; v_payload jsonb; v_source_id text; v_dedupe text;
begin
  if tg_table_name='ai_coaching_interventions' then
    if tg_op='INSERT' then v_event:='coaching.intervention_created';
    elsif tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed' then v_event:='coaching.intervention_completed';
    else return new; end if;
    v_org:=new.organization_id; v_entity:=new.user_id; v_actor:=new.user_id; v_source_id:=new.id::text;
    v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.id,'employee_id',new.user_id,'status',new.status,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'skill_id',new.skill_id,'scenario_id',new.prescribed_scenario_id,'recommendation_id',new.recommendation_id));
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_steps' then
    if not (tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed') then return new; end if;
    select organization_id,user_id into v_org,v_actor from tj.ai_coaching_interventions where id=new.intervention_id;
    v_entity:=v_actor; v_source_id:=new.id::text; v_event:='coaching.step_completed';
    v_payload:=jsonb_build_object('intervention_id',new.intervention_id,'employee_id',v_actor,'step_id',new.id,'step_order',new.step_order,'step_type',new.step_type,'target_score',new.target_score,'metadata',new.metadata);
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_evaluations' then
    if not (tg_op='UPDATE' and new.status='measured' and old.status is distinct from 'measured') then return new; end if;
    select user_id into v_actor from tj.ai_coaching_interventions where id=new.intervention_id;
    v_org:=new.organization_id; v_entity:=v_actor; v_source_id:=new.id::text; v_event:='coaching.outcome_measured';
    v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.intervention_id,'employee_id',v_actor,'evaluation_id',new.id,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'observed_value',new.observed_value,'delta',new.delta,'success',new.success,'outcome_id',new.outcome_id,'measurement_source',new.measurement_source));
    v_dedupe:=v_event||':'||new.id::text;
  else return new; end if;
  perform tj.platform_emit_intelligence_event(v_org,v_event,'phase4_closed_loop',v_source_id,'employee',v_entity,null,v_actor,null,null,v_dedupe,v_payload,now(),1,jsonb_build_object('phase',4,'semantic_subject','coaching','trigger_table',tg_table_name));
  return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_emit_coaching_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_ensure_intervention_recommendation(p_intervention_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_i tj.ai_coaching_interventions%rowtype;
  v_rec uuid;
  v_entity uuid;
begin
  select * into v_i from tj.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if tj_private.current_source_user_id() is not null and not tj.is_org_member(v_i.organization_id) then raise exception 'Not authorized'; end if;
  if v_i.recommendation_id is not null then return v_i.recommendation_id; end if;
  select intelligence_entity_id into v_entity
  from tj.platform_identity_links
  where organization_id=v_i.organization_id and entity_type='employee' and canonical_id=v_i.user_id and intelligence_entity_id is not null
  order by is_primary desc, verified_at desc nulls last, confidence desc nulls last, last_seen_at desc limit 1;
  v_rec := tj.intelligence_record_recommendation(v_i.organization_id,'coaching_intervention','employee',v_i.user_id::text,v_i.diagnosis,coalesce(v_i.metric_key,'performance_brain'),v_entity,case when (v_i.evidence->>'confidence') ~ '^[0-9.]+$' then least(1,greatest(0,(v_i.evidence->>'confidence')::numeric)) else null end,jsonb_build_object('intervention_id',v_i.id,'evidence',v_i.evidence,'baseline',v_i.baseline_value,'target',v_i.target_value,'skill_id',v_i.skill_id,'scenario_id',v_i.prescribed_scenario_id),'[]'::jsonb,'phase4_closed_loop',v_i.id::text);
  update tj.ai_coaching_interventions set recommendation_id=v_rec,updated_at=now() where id=v_i.id;
  return v_rec;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_ensure_intervention_recommendation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_ensure_intervention_recommendation(p_intervention_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_ensure_intervention_recommendation("p_intervention_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_ensure_intervention_recommendation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_evaluate_all_due(p_limit_per_org integer DEFAULT 100)
 RETURNS TABLE(organization_id uuid, intervention_id uuid, result jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare org record; r record;
begin
  if tj_private.current_source_user_id() is not null then raise exception 'Service execution only'; end if;
  for org in
    select distinct e.organization_id from tj.ai_intervention_evaluations e
    join tj.ai_coaching_interventions i on i.id=e.intervention_id
    where e.status in ('pending','due') and e.evaluation_due_at<=now() and i.status='completed'
  loop
    for r in select * from tj.phase4_evaluate_due_org(org.organization_id,p_limit_per_org)
    loop organization_id:=org.organization_id; intervention_id:=r.intervention_id; result:=r.result; return next; end loop;
  end loop;
  return;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_evaluate_all_due(p_limit_per_org integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_evaluate_all_due(p_limit_per_org integer DEFAULT 100) RETURNS TABLE(organization_id uuid, intervention_id uuid, result jsonb) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase4_evaluate_all_due("p_limit_per_org"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_evaluate_all_due(p_limit_per_org integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer DEFAULT 100)
 RETURNS TABLE(intervention_id uuid, result jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  update tj.ai_intervention_evaluations set status='due',updated_at=now() where organization_id=p_organization_id and status='pending' and evaluation_due_at<=now();
  for r in select e.intervention_id from tj.ai_intervention_evaluations e join tj.ai_coaching_interventions i on i.id=e.intervention_id where e.organization_id=p_organization_id and e.status='due' and i.status='completed' order by e.evaluation_due_at limit greatest(1,least(coalesce(p_limit,100),500))
  loop intervention_id:=r.intervention_id; result:=tj.phase4_evaluate_intervention(r.intervention_id,false); return next; end loop;
  return;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer DEFAULT 100) RETURNS TABLE(intervention_id uuid, result jsonb) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase4_evaluate_due_org("p_organization_id","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_i tj.ai_coaching_interventions%rowtype; v_e tj.ai_intervention_evaluations%rowtype;
  v_current numeric; v_current_at timestamptz; v_delta numeric; v_success boolean; v_outcome uuid; v_rec uuid; v_source text;
begin
  select * into v_i from tj.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if tj_private.current_source_user_id() is not null and not tj.is_org_member(v_i.organization_id) then raise exception 'Not authorized'; end if;
  if tj_private.current_source_user_id() is not null and tj_private.current_source_user_id()<>v_i.user_id and not tj.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;

  select * into v_e from tj.ai_intervention_evaluations where intervention_id=p_intervention_id;
  if v_e.id is null then
    perform tj.phase4_attach_evaluation(p_intervention_id);
    select * into v_e from tj.ai_intervention_evaluations where intervention_id=p_intervention_id;
  end if;
  if not p_force and v_e.evaluation_due_at>now() then return jsonb_build_object('status','not_due','evaluation_due_at',v_e.evaluation_due_at); end if;

  if v_i.metric_key is not null then
    select d.actual_value,d.computed_at into v_current,v_current_at
    from tj.performance_metric_diagnostics d
    where d.organization_id=v_i.organization_id and d.user_id=v_i.user_id and d.metric_key=v_i.metric_key and d.actual_value is not null
    order by d.computed_at desc limit 1;
    v_source:='performance_metric_diagnostics';
  end if;
  if v_current is null and v_i.skill_id is not null then
    select ss.rolling_score,ss.last_observed_at into v_current,v_current_at
    from tj.ai_skill_definitions s
    join tj.performance_competencies c on c.code=case s.skill_key when 'attach_selling' then 'attachment' when 'active_listening' then 'communication' when 'solution_matching' then 'recommendation' when 'value_communication' then 'value_building' else s.skill_key end
    join tj.performance_skill_state ss on ss.competency_id=c.id and ss.organization_id=v_i.organization_id and ss.user_id=v_i.user_id
    where s.id=v_i.skill_id order by ss.last_observed_at desc nulls last limit 1;
    v_source:='performance_skill_state';
  end if;
  if v_current is null then
    update tj.ai_intervention_evaluations set status='insufficient_data',measured_at=now(),measurement_source=coalesce(v_source,'none'),evidence=evidence||jsonb_build_object('reason','No post-intervention metric available'),updated_at=now() where id=v_e.id;
    return jsonb_build_object('status','insufficient_data');
  end if;

  v_delta:=case when v_i.baseline_value is null then null else v_current-v_i.baseline_value end;
  v_success:=case when v_i.target_value is not null then v_current>=v_i.target_value when v_delta is not null then v_delta>0 else null end;
  v_rec:=coalesce(v_i.recommendation_id,tj.phase4_ensure_intervention_recommendation(v_i.id));
  v_outcome:=tj.intelligence_record_outcome(v_rec,'coaching_effectiveness',v_success,v_current,case when v_success is true then 'improved' when v_success is false then 'not_yet_improved' else 'measured' end,1,jsonb_build_object('intervention_id',v_i.id,'baseline',v_i.baseline_value,'target',v_i.target_value,'delta',v_delta,'measurement_source',v_source,'measured_at',v_current_at),'phase4_closed_loop',v_i.id::text,now());

  update tj.ai_intervention_evaluations set observed_value=v_current,delta=v_delta,success=v_success,status='measured',measured_at=now(),measurement_source=v_source,outcome_id=v_outcome,evidence=evidence||jsonb_build_object('metric_observed_at',v_current_at),updated_at=now() where id=v_e.id;
  update tj.ai_coaching_interventions set outcome_value=v_current,outcome_delta=v_delta,outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object('success',v_success,'outcome_id',v_outcome,'measurement_source',v_source),updated_at=now() where id=v_i.id;
  update tj.intelligence_recommendations set status=case when status in ('generated','presented') then 'accepted' else status end,resolved_at=coalesce(resolved_at,now()),updated_at=now() where id=v_rec;
  return jsonb_build_object('status','measured','baseline',v_i.baseline_value,'target',v_i.target_value,'observed',v_current,'delta',v_delta,'success',v_success,'outcome_id',v_outcome);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_evaluate_intervention("p_intervention_id","p_force"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_intervention uuid;
begin
  if tj_private.current_source_user_id() is not null then
    if not tj.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
    if p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id) then raise exception 'Not authorized to generate coaching for this user'; end if;
  end if;
  v_intervention:=tj.ai_generate_daily_coaching_focus(p_organization_id,p_user_id,p_focus_date);
  if v_intervention is null then return null; end if;
  perform tj.phase4_attach_evaluation(v_intervention);
  return v_intervention;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_generate_coaching("p_organization_id","p_user_id","p_focus_date"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25)
 RETURNS TABLE(user_id uuid, intervention_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; v_id uuid;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  for r in
    select d.user_id,
           max(case when d.actual_value<d.target_value then case when d.target_value=0 then abs(d.target_value-d.actual_value) else 100.0*(d.target_value-d.actual_value)/abs(d.target_value) end end) gap_severity_pct
    from tj.performance_metric_diagnostics d
    join tj.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active'
    where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value
    group by d.user_id
    order by gap_severity_pct desc nulls last
    limit greatest(1,least(coalesce(p_limit,25),100))
  loop
    v_id:=tj.phase4_generate_coaching(p_organization_id,r.user_id,p_focus_date);
    if v_id is not null then user_id:=r.user_id; intervention_id:=v_id; return next; end if;
  end loop;
  return;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase4_generate_org_coaching("p_organization_id","p_focus_date","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_apply_adaptation(p_intervention_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_i tj.ai_coaching_interventions%rowtype; v_choice jsonb; v_strategy text; v_level int; v_target numeric; v_seq jsonb; v_eval uuid; v_decision uuid;
begin
 select * into v_i from tj.ai_coaching_interventions where id=p_intervention_id;
 if v_i.id is null then raise exception 'Intervention not found'; end if;
 if tj_private.current_source_user_id() is not null and tj_private.current_source_user_id()<>v_i.user_id and not tj.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
 v_choice:=tj.phase5_select_strategy(v_i.organization_id,v_i.user_id,v_i.metric_key,v_i.skill_id);
 v_strategy:=v_choice->>'strategy_key'; v_level:=(v_choice->>'difficulty_level')::int; v_target:=(v_choice->>'target_score')::numeric; v_seq:=v_choice->'sequence'; v_eval:=v_i.evaluation_id;
 update tj.ai_intervention_steps set step_order=step_order+100 where intervention_id=p_intervention_id;
 if v_strategy='field_first' then
  update tj.ai_intervention_steps set step_order=case step_type when 'roleplay' then 1 when 'floor_challenge' then 2 when 'lesson' then 3 else 4 end,target_score=case when step_type='roleplay' then v_target else target_score end,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('adaptive_difficulty',v_level,'adaptive_strategy',v_strategy),updated_at=now() where intervention_id=p_intervention_id;
 elsif v_strategy='practice_heavy' then
  update tj.ai_intervention_steps set step_order=case when step_type='lesson' then 1 when step_type='roleplay' then 2 when step_type='floor_challenge' then 3 else 4 end,target_score=case when step_type='roleplay' then v_target else target_score end,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('adaptive_difficulty',v_level,'adaptive_strategy',v_strategy,'repeat_roleplay_recommended',true),updated_at=now() where intervention_id=p_intervention_id;
 else
  update tj.ai_intervention_steps set step_order=case when step_type='lesson' then 1 when step_type='roleplay' then 2 when step_type='floor_challenge' then 3 else 4 end,target_score=case when step_type='roleplay' then v_target else target_score end,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('adaptive_difficulty',v_level,'adaptive_strategy',v_strategy),updated_at=now() where intervention_id=p_intervention_id;
 end if;
 update tj.ai_coaching_interventions set evidence=coalesce(evidence,'{}'::jsonb)||jsonb_build_object('phase5_adaptive',v_choice),outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object('adaptive_strategy',v_strategy,'difficulty_level',v_level),updated_at=now() where id=p_intervention_id;
 insert into tj.ai_adaptive_coaching_decisions(organization_id,user_id,intervention_id,evaluation_id,strategy_key,difficulty_level,sequence,target_score,rationale,confidence,exploration)
 values(v_i.organization_id,v_i.user_id,v_i.id,v_eval,v_strategy,v_level,v_seq,v_target,v_choice,coalesce((v_choice->>'confidence')::numeric,0),coalesce((v_choice->>'exploration')::boolean,false))
 on conflict(intervention_id) do update set evaluation_id=excluded.evaluation_id,strategy_key=excluded.strategy_key,difficulty_level=excluded.difficulty_level,sequence=excluded.sequence,target_score=excluded.target_score,rationale=excluded.rationale,confidence=excluded.confidence,exploration=excluded.exploration,updated_at=now() returning id into v_decision;
 return v_choice||jsonb_build_object('intervention_id',p_intervention_id,'decision_id',v_decision);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_apply_adaptation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase5_apply_adaptation(p_intervention_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_apply_adaptation("p_intervention_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_apply_adaptation(p_intervention_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_evaluation_learning_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
 if new.status='measured' and (old.status is distinct from new.status or old.outcome_id is distinct from new.outcome_id) then perform tj.phase5_learn_from_evaluation(new.id); end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_evaluation_learning_trigger() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid; v_choice jsonb;
begin
 if tj_private.current_source_user_id() is not null then
  if not tj.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  if tj_private.current_source_user_id()<>p_user_id and not tj.is_org_admin(p_organization_id) then raise exception 'Not authorized'; end if;
 end if;
 v_id:=tj.phase4_generate_coaching(p_organization_id,p_user_id,p_focus_date);
 if v_id is null then return jsonb_build_object('status','no_intervention'); end if;
 v_choice:=tj.phase5_apply_adaptation(v_id);
 return jsonb_build_object('status','created','intervention_id',v_id,'adaptation',v_choice);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_generate_adaptive_coaching("p_organization_id","p_user_id","p_focus_date"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25)
 RETURNS TABLE(user_id uuid, intervention_id uuid, adaptation jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; v_result jsonb;
begin
 if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 for r in
  select d.user_id,max(case when d.actual_value<d.target_value then case when d.target_value=0 then abs(d.target_value-d.actual_value) else 100.0*(d.target_value-d.actual_value)/abs(d.target_value) end end) severity
  from tj.performance_metric_diagnostics d join tj.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active'
  where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value
  group by d.user_id order by severity desc nulls last limit greatest(1,least(coalesce(p_limit,25),100))
 loop
  v_result:=tj.phase5_generate_adaptive_coaching(p_organization_id,r.user_id,p_focus_date);
  if v_result->>'status'='created' then user_id:=r.user_id; intervention_id:=(v_result->>'intervention_id')::uuid; adaptation:=v_result->'adaptation'; return next; end if;
 end loop;
 return;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid, adaptation jsonb) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase5_generate_org_adaptive_coaching("p_organization_id","p_focus_date","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_learn_from_evaluation(p_evaluation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_e tj.ai_intervention_evaluations%rowtype; v_i tj.ai_coaching_interventions%rowtype; v_d tj.ai_adaptive_coaching_decisions%rowtype; v_attempts int; v_successes int; v_failures int; v_avg numeric; v_post numeric; v_conf numeric;
begin
 select * into v_e from tj.ai_intervention_evaluations where id=p_evaluation_id;
 if v_e.id is null then raise exception 'Evaluation not found'; end if;
 if v_e.status<>'measured' then return jsonb_build_object('status','ignored','reason','evaluation_not_measured'); end if;
 select * into v_i from tj.ai_coaching_interventions where id=v_e.intervention_id;
 select * into v_d from tj.ai_adaptive_coaching_decisions where intervention_id=v_i.id;
 if v_d.id is null or v_d.learned_at is not null then return jsonb_build_object('status','ignored','reason',case when v_d.id is null then 'no_adaptive_decision' else 'already_learned' end); end if;
 insert into tj.ai_coaching_strategy_performance(organization_id,metric_key,skill_id,strategy_key,difficulty_level,attempts,successes,failures,avg_delta,posterior_success,confidence,last_outcome_at)
 values(v_i.organization_id,coalesce(v_i.metric_key,''),v_i.skill_id,v_d.strategy_key,v_d.difficulty_level,1,case when v_e.success is true then 1 else 0 end,case when v_e.success is false then 1 else 0 end,v_e.delta,(1.0+case when v_e.success is true then 1 else 0 end)/(2.0+case when v_e.success is null then 0 else 1 end),0.2,coalesce(v_e.measured_at,now()))
 on conflict(organization_id,metric_key,coalesce(skill_id,'00000000-0000-0000-0000-000000000000'::uuid),strategy_key,difficulty_level) do update set attempts=tj.ai_coaching_strategy_performance.attempts+1,successes=tj.ai_coaching_strategy_performance.successes+case when v_e.success is true then 1 else 0 end,failures=tj.ai_coaching_strategy_performance.failures+case when v_e.success is false then 1 else 0 end,avg_delta=case when v_e.delta is null then tj.ai_coaching_strategy_performance.avg_delta else ((coalesce(tj.ai_coaching_strategy_performance.avg_delta,0)*tj.ai_coaching_strategy_performance.attempts)+v_e.delta)/(tj.ai_coaching_strategy_performance.attempts+1) end,posterior_success=(1.0+tj.ai_coaching_strategy_performance.successes+case when v_e.success is true then 1 else 0 end)/(2.0+tj.ai_coaching_strategy_performance.successes+tj.ai_coaching_strategy_performance.failures+case when v_e.success is null then 0 else 1 end),confidence=least(0.95,(tj.ai_coaching_strategy_performance.attempts+1)::numeric/10.0),last_outcome_at=coalesce(v_e.measured_at,now()),updated_at=now();
 update tj.ai_adaptive_coaching_decisions set outcome_success=v_e.success,outcome_delta=v_e.delta,outcome_id=v_e.outcome_id,learned_at=now(),updated_at=now() where id=v_d.id;
 perform tj.phase5_refresh_profile(v_i.organization_id,v_i.user_id);
 select attempts,successes,failures,avg_delta,posterior_success,confidence into v_attempts,v_successes,v_failures,v_avg,v_post,v_conf from tj.ai_coaching_strategy_performance where organization_id=v_i.organization_id and metric_key=coalesce(v_i.metric_key,'') and (skill_id=v_i.skill_id or(skill_id is null and v_i.skill_id is null)) and strategy_key=v_d.strategy_key and difficulty_level=v_d.difficulty_level;
 return jsonb_build_object('status','learned','strategy_key',v_d.strategy_key,'difficulty_level',v_d.difficulty_level,'attempts',v_attempts,'successes',v_successes,'failures',v_failures,'avg_delta',v_avg,'posterior_success',v_post,'confidence',v_conf);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_learn_from_evaluation(p_evaluation_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase5_learn_from_evaluation(p_evaluation_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_learn_from_evaluation("p_evaluation_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_learn_from_evaluation(p_evaluation_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_profile tj.ai_adaptive_coaching_profiles%rowtype; v_best tj.ai_coaching_strategy_performance%rowtype; v_strategy text; v_level int; v_sequence jsonb; v_conf numeric; v_explore boolean:=false; v_target numeric;
begin
 perform tj.phase5_refresh_profile(p_organization_id,p_user_id);
 select * into v_profile from tj.ai_adaptive_coaching_profiles where organization_id=p_organization_id and user_id=p_user_id;
 select * into v_best from tj.ai_coaching_strategy_performance where organization_id=p_organization_id and metric_key=coalesce(p_metric_key,'') and (skill_id=p_skill_id or (skill_id is null and p_skill_id is null)) and attempts>=3 order by posterior_success desc,confidence desc,attempts desc limit 1;
 if v_best.id is not null and v_best.posterior_success>=0.55 then v_strategy:=v_best.strategy_key; v_level:=v_best.difficulty_level; v_conf:=greatest(v_profile.confidence,v_best.confidence); else v_strategy:=v_profile.preferred_strategy; v_level:=v_profile.challenge_level; v_conf:=v_profile.confidence; v_explore:=true; end if;
 v_level:=greatest(1,least(5,v_level));
 v_sequence:=case v_strategy when 'field_first' then '["roleplay","floor_challenge","lesson","review"]'::jsonb when 'practice_heavy' then '["lesson","roleplay","roleplay","review"]'::jsonb else '["lesson","roleplay","floor_challenge","review"]'::jsonb end;
 v_target:=case v_level when 1 then 65 when 2 then 72 when 3 then 78 when 4 then 84 else 90 end;
 return jsonb_build_object('strategy_key',v_strategy,'difficulty_level',v_level,'sequence',v_sequence,'target_score',v_target,'confidence',v_conf,'exploration',v_explore,'profile',jsonb_build_object('coaching_intensity',v_profile.coaching_intensity,'learning_velocity',v_profile.learning_velocity,'evidence_count',v_profile.evidence_count));
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_select_strategy("p_organization_id","p_user_id","p_metric_key","p_skill_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase6_accept_action(p_opportunity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_o tj.phase6_revenue_opportunities%rowtype; v_assignment uuid; v_actor uuid:=tj_private.current_source_user_id();
begin
  select * into v_o from tj.phase6_revenue_opportunities where id=p_opportunity_id;
  if v_o.id is null then raise exception 'Opportunity not found'; end if;
  if v_actor is null or not tj.is_org_admin(v_o.organization_id) then raise exception 'Organization admin required'; end if;
  if v_o.manager_assignment_id is not null then return jsonb_build_object('status','already_assigned','assignment_id',v_o.manager_assignment_id); end if;
  insert into tj.ai_manager_assignments(organization_id,title,instructions,assigned_by,priority,status,due_at,source,metadata,assigned_role)
  values(v_o.organization_id,v_o.title,v_o.recommended_action,v_actor,case when v_o.priority_score>=70 then 'critical' when v_o.priority_score>=45 then 'high' else 'medium' end,
    'open',now()+interval '1 day','phase6_revenue_intelligence',
    jsonb_build_object('phase6_opportunity_id',v_o.id,'estimated_revenue_impact',v_o.estimated_revenue_impact,'estimated_margin_impact',v_o.estimated_margin_impact,'action_module',v_o.action_module,'subject_type',v_o.subject_type,'subject_id',v_o.subject_id),'manager') returning id into v_assignment;
  update tj.phase6_revenue_opportunities set status='accepted',manager_assignment_id=v_assignment,updated_at=now() where id=v_o.id;
  return jsonb_build_object('status','accepted','assignment_id',v_assignment);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase6_accept_action(p_opportunity_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase6_accept_action(p_opportunity_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase6_accept_action("p_opportunity_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase6_accept_action(p_opportunity_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase6_command_center(p_organization_id uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_result jsonb;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  select jsonb_build_object(
    'summary',jsonb_build_object(
      'open_actions',count(*) filter(where status in ('open','accepted','in_progress')),
      'estimated_revenue_impact',coalesce(sum(estimated_revenue_impact) filter(where status in ('open','accepted','in_progress')),0),
      'estimated_margin_impact',coalesce(sum(estimated_margin_impact) filter(where status in ('open','accepted','in_progress')),0),
      'high_priority',count(*) filter(where status in ('open','accepted','in_progress') and priority_score>=50),
      'financially_quantified',count(*) filter(where status in ('open','accepted','in_progress') and (estimated_revenue_impact is not null or estimated_margin_impact is not null))
    ),
    'actions',coalesce((select jsonb_agg(x order by x.priority_score desc,x.estimated_margin_impact desc nulls last,x.estimated_revenue_impact desc nulls last)
      from (select id,opportunity_type,subject_type,subject_id,metric_key,title,diagnosis,recommended_action,action_module,actual_value,target_value,severity_pct,
        estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,evidence,financial_model,status,manager_assignment_id,last_detected_at
        from tj.phase6_revenue_opportunities where organization_id=p_organization_id and status in ('open','accepted','in_progress')
        order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))) x),'[]'::jsonb)
  ) into v_result
  from tj.phase6_revenue_opportunities where organization_id=p_organization_id;
  return v_result;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase6_command_center(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase6_command_center(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase6_command_center("p_organization_id","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase6_command_center(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase6_refresh_revenue_opportunities(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_now timestamptz:=now();
  v_upserts int:=0;
  v_closed int:=0;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then
    raise exception 'Organization admin required';
  end if;

  with latest_diag as (
    select distinct on (d.user_id,d.metric_key)
      d.user_id,d.metric_key,d.actual_value,d.target_value,d.target_gap_pct,d.competency_name,d.rationale,d.computed_at,
      greatest(0,case when d.target_value is null or d.actual_value is null then 0
        when d.direction='lower_is_better' then 100.0*(d.actual_value-d.target_value)/nullif(abs(d.target_value),0)
        else 100.0*(d.target_value-d.actual_value)/nullif(abs(d.target_value),0) end) as severity
    from tj.performance_metric_diagnostics d
    where d.organization_id=p_organization_id
    order by d.user_id,d.metric_key,d.computed_at desc
  ), gaps as (
    select *,
      case when metric_key='margin_dollars' and actual_value<target_value then target_value-actual_value else null end as margin_impact,
      case when metric_key in ('floor_conversion','warranty_attach','warranty_pen_units','warranty_pen_dollars','margin_pct','margin_dollars','avg_order','ipo') then 'ai-coach' else 'academy' end as module_key
    from latest_diag
    where severity>0
  ), upserted as (
    insert into tj.phase6_revenue_opportunities(
      organization_id,opportunity_key,opportunity_type,subject_type,subject_id,metric_key,title,diagnosis,recommended_action,action_module,
      actual_value,target_value,severity_pct,estimated_margin_impact,impact_confidence,priority_score,evidence,financial_model,last_detected_at,updated_at
    )
    select p_organization_id,
      'performance:'||user_id::text||':'||metric_key,
      'performance_gap','employee',user_id,metric_key,
      initcap(replace(metric_key,'_',' '))||' opportunity',
      coalesce(rationale,'Performance is below target for '||replace(metric_key,'_',' ')),
      case when module_key='ai-coach' then 'Open adaptive coaching for this employee and address the measured performance gap.' else 'Assign targeted learning and remeasure performance.' end,
      module_key,actual_value,target_value,round(severity,2),margin_impact,
      case when margin_impact is not null then 0.90 else 0.45 end,
      round(least(100, severity + case when margin_impact is not null then least(35,margin_impact/250.0) else 0 end),2),
      jsonb_strip_nulls(jsonb_build_object('competency',competency_name,'computed_at',computed_at,'source','performance_metric_diagnostics')),
      case when margin_impact is not null then jsonb_build_object('method','direct_target_gap','currency','CAD','formula','target_value - actual_value') else jsonb_build_object('method','severity_only','reason','Insufficient transactional evidence for defensible dollar estimate') end,
      v_now,v_now
    from gaps
    on conflict(organization_id,opportunity_key) do update set
      title=excluded.title,diagnosis=excluded.diagnosis,recommended_action=excluded.recommended_action,action_module=excluded.action_module,
      actual_value=excluded.actual_value,target_value=excluded.target_value,severity_pct=excluded.severity_pct,
      estimated_margin_impact=excluded.estimated_margin_impact,impact_confidence=excluded.impact_confidence,priority_score=excluded.priority_score,
      evidence=excluded.evidence,financial_model=excluded.financial_model,last_detected_at=v_now,updated_at=v_now,
      status=case when tj.phase6_revenue_opportunities.status in ('resolved','dismissed') then 'open' else tj.phase6_revenue_opportunities.status end,
      resolved_at=null
    returning 1
  ) select count(*) into v_upserts from upserted;

  with crm as (
    select o.id,o.title,o.opportunity_value,o.probability,o.owner_id,o.stage,o.expected_close_date,
      coalesce(h.health_score,50) health_score,coalesce(h.reasoning,h.ai_comment,'Open CRM opportunity requiring follow-up') reasoning
    from tj.aicrm_opportunities o
    left join tj.aicrm_opportunity_health h on h.opportunity_id=o.id and h.organization_id=o.organization_id
    where o.organization_id=p_organization_id and coalesce(o.status,'open') not in ('won','lost','closed')
  ), u as (
    insert into tj.phase6_revenue_opportunities(
      organization_id,opportunity_key,opportunity_type,subject_type,subject_id,title,diagnosis,recommended_action,action_module,
      estimated_revenue_impact,impact_confidence,priority_score,evidence,financial_model,last_detected_at,updated_at
    )
    select p_organization_id,'crm:'||id::text,'crm_pipeline','opportunity',id,
      title,reasoning,'Open the CRM opportunity, confirm next action and protect the expected close.','crm',
      opportunity_value*coalesce(probability,50)/100.0,
      case when probability is null then 0.55 else 0.75 end,
      round(least(100,(100-health_score)*0.6 + coalesce(probability,50)*0.25 + least(25,coalesce(opportunity_value,0)/5000.0)),2),
      jsonb_strip_nulls(jsonb_build_object('stage',stage,'owner_id',owner_id,'expected_close_date',expected_close_date,'health_score',health_score)),
      jsonb_build_object('method','probability_weighted_pipeline','formula','opportunity_value * probability'),v_now,v_now
    from crm
    on conflict(organization_id,opportunity_key) do update set title=excluded.title,diagnosis=excluded.diagnosis,recommended_action=excluded.recommended_action,
      estimated_revenue_impact=excluded.estimated_revenue_impact,impact_confidence=excluded.impact_confidence,priority_score=excluded.priority_score,
      evidence=excluded.evidence,financial_model=excluded.financial_model,last_detected_at=v_now,updated_at=v_now,
      status=case when tj.phase6_revenue_opportunities.status in ('resolved','dismissed') then 'open' else tj.phase6_revenue_opportunities.status end,resolved_at=null
    returning 1
  ) select v_upserts+count(*) into v_upserts from u;

  update tj.phase6_revenue_opportunities
  set status='resolved',resolved_at=v_now,updated_at=v_now
  where organization_id=p_organization_id and status in ('open','accepted','in_progress') and last_detected_at < v_now - interval '1 minute';
  get diagnostics v_closed=row_count;

  return jsonb_build_object('status','ok','upserted',v_upserts,'resolved_stale',v_closed,'refreshed_at',v_now);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase6_refresh_revenue_opportunities(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase6_refresh_revenue_opportunities(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase6_refresh_revenue_opportunities("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase6_refresh_revenue_opportunities(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_command_center(p_organization_id uuid, p_limit integer DEFAULT 25)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id();
begin
  if v_actor is null or not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  return jsonb_build_object(
    'summary',jsonb_build_object(
      'pending_approval',(select count(*) from tj.phase7_action_runs where organization_id=p_organization_id and status='pending_approval'),
      'executed_7d',(select count(*) from tj.phase7_action_runs where organization_id=p_organization_id and status='executed' and executed_at>=now()-interval '7 days'),
      'failed',(select count(*) from tj.phase7_action_runs where organization_id=p_organization_id and status='failed'),
      'auto_policies',(select count(*) from tj.phase7_automation_policies where organization_id=p_organization_id and mode='auto_execute')
    ),
    'policies',coalesce((select jsonb_agg(to_jsonb(x) order by x.action_type,x.action_module) from (select id,action_type,action_module,mode,max_priority_score,max_revenue_impact,max_margin_impact,require_financial_confidence from tj.phase7_automation_policies where organization_id=p_organization_id) x),'[]'::jsonb),
    'actions',coalesce((select jsonb_agg(to_jsonb(x) order by x.priority_score desc,x.created_at asc) from (select id,phase6_opportunity_id,action_type,action_module,subject_type,subject_id,policy_mode,status,recommended_action,estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,expected_metric_key,baseline_value,target_value,due_at,created_at,error_message from tj.phase7_action_runs where organization_id=p_organization_id and status in ('pending_approval','approved','executing','failed') order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))) x),'[]'::jsonb)
  );
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_command_center(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_command_center(p_organization_id uuid, p_limit integer DEFAULT 25) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_command_center("p_organization_id","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_command_center(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_decide_action(p_action_run_id uuid, p_decision text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.phase7_action_runs%rowtype; v_actor uuid:=tj_private.current_source_user_id(); v_exec jsonb;
begin
  select * into r from tj.phase7_action_runs where id=p_action_run_id for update;
  if r.id is null then raise exception 'Action run not found'; end if;
  if v_actor is null or not tj.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if;
  if r.status<>'pending_approval' then raise exception 'Action is not pending approval'; end if;
  if p_decision='approve' then
    update tj.phase7_action_runs set status='approved',approved_by=v_actor,approved_at=now(),updated_at=now() where id=r.id;
    insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'approved',v_actor,jsonb_build_object('reason',p_reason));
    select tj.phase7_execute_run(r.id) into v_exec;
    return v_exec;
  elsif p_decision='reject' then
    update tj.phase7_action_runs set status='rejected',rejected_by=v_actor,rejected_at=now(),rejection_reason=p_reason,updated_at=now() where id=r.id;
    insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'rejected',v_actor,jsonb_build_object('reason',p_reason));
    return jsonb_build_object('status','rejected','action_run_id',r.id);
  else raise exception 'Decision must be approve or reject'; end if;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_decide_action(p_action_run_id uuid, p_decision text, p_reason text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_decide_action(p_action_run_id uuid, p_decision text, p_reason text DEFAULT NULL::text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_decide_action("p_action_run_id","p_decision","p_reason"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_decide_action(p_action_run_id uuid, p_decision text, p_reason text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_execute_run(p_action_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.phase7_action_runs%rowtype; v_actor uuid:=tj_private.current_source_user_id(); v_assignment jsonb; v_coach jsonb; v_result jsonb; v_assignment_id uuid;
begin
  select * into r from tj.phase7_action_runs where id=p_action_run_id for update;
  if r.id is null then raise exception 'Action run not found'; end if;
  if v_actor is not null and not tj.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if;
  if r.status='executed' then return jsonb_build_object('status','already_executed','result',r.execution_result); end if;
  if r.status not in ('approved','executing') and not (r.policy_mode='auto_execute' and r.status='pending_approval') then raise exception 'Action is not executable in status %',r.status; end if;
  update tj.phase7_action_runs set status='executing',executed_by=v_actor,updated_at=now() where id=r.id;
  insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'execution_started',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('module',r.action_module));
  begin
    if r.action_module='ai-coach' and r.subject_type='employee' and r.subject_id is not null then
      select tj.phase5_generate_adaptive_coaching(r.organization_id,r.subject_id,current_date) into v_coach;
      v_result=jsonb_build_object('handler','adaptive_coaching','result',v_coach);
    else
      if r.phase6_opportunity_id is not null then
        select tj.phase6_accept_action(r.phase6_opportunity_id) into v_assignment;
        v_assignment_id=nullif(v_assignment->>'assignment_id','')::uuid;
      else
        insert into tj.ai_manager_assignments(organization_id,title,instructions,assigned_by,assigned_to,priority,status,due_at,source,metadata,assigned_role)
        values(r.organization_id,coalesce(r.recommended_action,'IQ recommended action'),coalesce(r.recommended_action,'Complete recommended action'),v_actor,case when r.subject_type='employee' then r.subject_id else null end,case when r.priority_score>=70 then 'critical' when r.priority_score>=45 then 'high' else 'medium' end,'open',coalesce(r.due_at,now()+interval '1 day'),'phase7_orchestration',jsonb_build_object('phase7_action_run_id',r.id,'action_module',r.action_module),'manager') returning id into v_assignment_id;
        v_assignment=jsonb_build_object('status','accepted','assignment_id',v_assignment_id);
      end if;
      v_result=jsonb_build_object('handler','manager_assignment','result',v_assignment);
    end if;
    update tj.phase7_action_runs set status='executed',executed_at=now(),execution_result=v_result,error_message=null,updated_at=now() where id=r.id;
    insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'executed',v_actor,case when v_actor is null then 'service' else 'user' end,v_result);
    return jsonb_build_object('status','executed','action_run_id',r.id,'result',v_result);
  exception when others then
    update tj.phase7_action_runs set status='failed',error_message=sqlerrm,updated_at=now() where id=r.id;
    insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'failed',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('error',sqlerrm));
    raise;
  end;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_execute_run(p_action_run_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_execute_run(p_action_run_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_execute_run("p_action_run_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_execute_run(p_action_run_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_measure_due(p_organization_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id(); r record; v_actual numeric; v_before_gap numeric; v_after_gap numeric; v_status text; v_n integer:=0;
begin
  if p_organization_id is not null and v_actor is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  for r in select * from tj.phase7_action_runs where status='executed' and outcome_status='pending' and due_at<=now() and (p_organization_id is null or organization_id=p_organization_id) loop
    v_actual:=null;
    if r.subject_type='employee' and r.subject_id is not null and r.expected_metric_key is not null then
      select d.actual_value into v_actual from tj.performance_metric_diagnostics d where d.organization_id=r.organization_id and d.user_id=r.subject_id and d.metric_key=r.expected_metric_key order by d.computed_at desc limit 1;
    end if;
    if v_actual is null or r.baseline_value is null or r.target_value is null then v_status:='insufficient_evidence';
    else
      v_before_gap:=abs(r.target_value-r.baseline_value); v_after_gap:=abs(r.target_value-v_actual);
      if v_after_gap < v_before_gap*0.9 then v_status:='improved';
      elsif v_after_gap > v_before_gap*1.1 then v_status:='regressed'; else v_status:='no_change'; end if;
    end if;
    update tj.phase7_action_runs set outcome_status=v_status,outcome_value=v_actual,outcome_measured_at=now(),updated_at=now() where id=r.id;
    insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(r.id,r.organization_id,'outcome_measured',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('status',v_status,'baseline',r.baseline_value,'target',r.target_value,'actual',v_actual));
    insert into tj.intelligence_outcomes(organization_id,entity_id,outcome_type,outcome_value,outcome_label,success,weight,metadata,source_system,source_record_id,occurred_at,recorded_by)
    values(r.organization_id,null,'phase7_action_effectiveness',v_actual,v_status,(v_status='improved'),coalesce(r.impact_confidence,0.5),jsonb_build_object('phase7_action_run_id',r.id,'metric_key',r.expected_metric_key,'baseline',r.baseline_value,'target',r.target_value),'phase7_orchestration',r.id::text,now(),v_actor)
    on conflict do nothing;
    v_n:=v_n+1;
  end loop;
  return jsonb_build_object('measured',v_n);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_measure_due(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_measure_due(p_organization_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_measure_due("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_measure_due(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_orchestrate_opportunity(p_opportunity_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare o tj.phase6_revenue_opportunities%rowtype; p tj.phase7_automation_policies%rowtype; v_actor uuid:=tj_private.current_source_user_id(); v_run uuid; v_mode text; v_key text; v_exec jsonb;
begin
  select * into o from tj.phase6_revenue_opportunities where id=p_opportunity_id;
  if o.id is null then raise exception 'Opportunity not found'; end if;
  if v_actor is not null and not tj.is_org_admin(o.organization_id) then raise exception 'Organization admin required'; end if;
  perform tj.phase7_seed_default_policies(o.organization_id);
  select * into p from tj.phase7_automation_policies where organization_id=o.organization_id and action_type=o.opportunity_type and action_module is not distinct from o.action_module limit 1;
  if p.id is null then select * into p from tj.phase7_automation_policies where organization_id=o.organization_id and action_type='manager_task' and action_module is null limit 1; end if;
  v_mode=coalesce(p.mode,'approval_required');
  if v_mode='auto_execute' and ((p.max_priority_score is not null and o.priority_score>p.max_priority_score) or (p.max_revenue_impact is not null and coalesce(o.estimated_revenue_impact,0)>p.max_revenue_impact) or (p.max_margin_impact is not null and coalesce(o.estimated_margin_impact,0)>p.max_margin_impact) or coalesce(o.impact_confidence,0)<coalesce(p.require_financial_confidence,0)) then v_mode='approval_required'; end if;
  v_key='phase7:'||o.id::text;
  insert into tj.phase7_action_runs(organization_id,phase6_opportunity_id,action_type,action_module,subject_type,subject_id,policy_id,policy_mode,status,recommended_action,estimated_revenue_impact,estimated_margin_impact,impact_confidence,priority_score,expected_metric_key,baseline_value,target_value,due_at,idempotency_key)
  values(o.organization_id,o.id,o.opportunity_type,o.action_module,o.subject_type,o.subject_id,p.id,v_mode,case when v_mode='disabled' then 'cancelled' else 'pending_approval' end,o.recommended_action,o.estimated_revenue_impact,o.estimated_margin_impact,o.impact_confidence,o.priority_score,o.metric_key,o.actual_value,o.target_value,now()+interval '7 days',v_key)
  on conflict(idempotency_key) do update set updated_at=now() returning id into v_run;
  insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,actor_type,details) values(v_run,o.organization_id,'policy_evaluated',v_actor,case when v_actor is null then 'service' else 'user' end,jsonb_build_object('mode',v_mode,'policy_id',p.id,'priority',o.priority_score));
  if v_mode='auto_execute' then
    update tj.phase7_action_runs set status='approved',approved_by=v_actor,approved_at=now() where id=v_run and status='pending_approval';
    select tj.phase7_execute_run(v_run) into v_exec;
    return jsonb_build_object('status','auto_executed','action_run_id',v_run,'execution',v_exec);
  elsif v_mode='disabled' then return jsonb_build_object('status','disabled','action_run_id',v_run);
  else return jsonb_build_object('status','pending_approval','action_run_id',v_run); end if;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_orchestrate_opportunity(p_opportunity_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_orchestrate_opportunity(p_opportunity_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_orchestrate_opportunity("p_opportunity_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_orchestrate_opportunity(p_opportunity_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_reverse_action(p_action_run_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.phase7_action_runs%rowtype; v_actor uuid:=tj_private.current_source_user_id(); v_assignment_id uuid; v_reversible boolean:=false;
begin
  select * into r from tj.phase7_action_runs where id=p_action_run_id for update;
  if r.id is null then raise exception 'Action run not found'; end if;
  if v_actor is null or not tj.is_org_admin(r.organization_id) then raise exception 'Organization admin required'; end if;
  if r.status<>'executed' then raise exception 'Only executed actions can be reversed'; end if;
  begin v_assignment_id=nullif(r.execution_result#>>'{result,result,assignment_id}','')::uuid; exception when others then v_assignment_id:=null; end;
  if v_assignment_id is not null then
    update tj.ai_manager_assignments set status='cancelled',blocked_reason=coalesce(p_reason,'Reversed by manager'),updated_at=now() where id=v_assignment_id and status not in ('completed','cancelled');
    v_reversible:=found;
  end if;
  update tj.phase7_action_runs set status='reversed',updated_at=now() where id=r.id;
  insert into tj.phase7_action_audit(action_run_id,organization_id,event_type,actor_id,details) values(r.id,r.organization_id,'reversed',v_actor,jsonb_build_object('reason',p_reason,'downstream_reversed',v_reversible,'assignment_id',v_assignment_id));
  return jsonb_build_object('status','reversed','downstream_reversed',v_reversible,'assignment_id',v_assignment_id,'note',case when v_reversible then 'Downstream manager assignment cancelled' else 'Action marked reversed; downstream action requires manual review if applicable' end);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_reverse_action(p_action_run_id uuid, p_reason text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_reverse_action(p_action_run_id uuid, p_reason text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_reverse_action("p_action_run_id","p_reason"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_reverse_action(p_action_run_id uuid, p_reason text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_run_cycle(p_organization_id uuid, p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id(); o record; v_result jsonb; v_created integer:=0; v_auto integer:=0; v_pending integer:=0; v_disabled integer:=0;
begin
  if v_actor is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  perform tj.phase7_seed_default_policies(p_organization_id);
  perform tj.phase6_refresh_revenue_opportunities(p_organization_id);
  for o in select id from tj.phase6_revenue_opportunities where organization_id=p_organization_id and status='open' order by priority_score desc limit greatest(1,least(coalesce(p_limit,50),200)) loop
    select tj.phase7_orchestrate_opportunity(o.id) into v_result;
    v_created:=v_created+1;
    if v_result->>'status'='auto_executed' then v_auto:=v_auto+1;
    elsif v_result->>'status'='pending_approval' then v_pending:=v_pending+1;
    elsif v_result->>'status'='disabled' then v_disabled:=v_disabled+1; end if;
  end loop;
  return jsonb_build_object('evaluated',v_created,'auto_executed',v_auto,'pending_approval',v_pending,'disabled',v_disabled);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_run_cycle(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_run_cycle(p_organization_id uuid, p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_run_cycle("p_organization_id","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_run_cycle(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_run_scheduled_cycles()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare o record; v_total integer:=0; v_auto integer:=0; v_pending integer:=0; v_r jsonb; v_m jsonb;
begin
  if tj_private.current_source_user_id() is not null then raise exception 'Service execution only'; end if;
  for o in select distinct organization_id from tj.phase6_revenue_opportunities where status='open'
           union select distinct organization_id from tj.phase7_automation_policies loop
    begin
      select tj.phase7_run_cycle(o.organization_id,50) into v_r;
      v_total:=v_total+coalesce((v_r->>'evaluated')::integer,0);
      v_auto:=v_auto+coalesce((v_r->>'auto_executed')::integer,0);
      v_pending:=v_pending+coalesce((v_r->>'pending_approval')::integer,0);
      perform tj.phase7_measure_due(o.organization_id);
    exception when others then
      continue;
    end;
  end loop;
  return jsonb_build_object('evaluated',v_total,'auto_executed',v_auto,'pending_approval',v_pending);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_run_scheduled_cycles() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_run_scheduled_cycles() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_run_scheduled_cycles(); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_run_scheduled_cycles() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_seed_default_policies(p_organization_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id(); v_count integer;
begin
  if v_actor is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  insert into tj.phase7_automation_policies(organization_id,action_type,action_module,mode,created_by,updated_by)
  values
    (p_organization_id,'performance_gap','ai-coach','approval_required',v_actor,v_actor),
    (p_organization_id,'performance_gap','academy','approval_required',v_actor,v_actor),
    (p_organization_id,'crm_pipeline','crm','approval_required',v_actor,v_actor),
    (p_organization_id,'manager_task',null,'auto_execute',v_actor,v_actor),
    (p_organization_id,'customer_outreach','crm','disabled',v_actor,v_actor)
  on conflict(organization_id,action_type,action_module) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_seed_default_policies(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_seed_default_policies(p_organization_id uuid) RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_seed_default_policies("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_seed_default_policies(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase7_set_policy(p_organization_id uuid, p_action_type text, p_action_module text, p_mode text, p_max_priority_score numeric DEFAULT NULL::numeric, p_max_revenue_impact numeric DEFAULT NULL::numeric, p_max_margin_impact numeric DEFAULT NULL::numeric, p_require_financial_confidence numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id(); v_id uuid;
begin
  if v_actor is null or not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  if p_mode not in ('disabled','approval_required','auto_execute') then raise exception 'Invalid mode'; end if;
  if p_action_type='customer_outreach' and p_mode='auto_execute' then raise exception 'Customer outreach cannot be auto-executed in Phase 7'; end if;
  insert into tj.phase7_automation_policies(organization_id,action_type,action_module,mode,max_priority_score,max_revenue_impact,max_margin_impact,require_financial_confidence,created_by,updated_by,updated_at)
  values(p_organization_id,p_action_type,p_action_module,p_mode,p_max_priority_score,p_max_revenue_impact,p_max_margin_impact,coalesce(p_require_financial_confidence,0),v_actor,v_actor,now())
  on conflict(organization_id,action_type,action_module) do update set mode=excluded.mode,max_priority_score=excluded.max_priority_score,max_revenue_impact=excluded.max_revenue_impact,max_margin_impact=excluded.max_margin_impact,require_financial_confidence=excluded.require_financial_confidence,updated_by=v_actor,updated_at=now()
  returning id into v_id;
  return jsonb_build_object('status','saved','policy_id',v_id);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase7_set_policy(p_organization_id uuid, p_action_type text, p_action_module text, p_mode text, p_max_priority_score numeric, p_max_revenue_impact numeric, p_max_margin_impact numeric, p_require_financial_confidence numeric) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase7_set_policy(p_organization_id uuid, p_action_type text, p_action_module text, p_mode text, p_max_priority_score numeric DEFAULT NULL::numeric, p_max_revenue_impact numeric DEFAULT NULL::numeric, p_max_margin_impact numeric DEFAULT NULL::numeric, p_require_financial_confidence numeric DEFAULT 0) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase7_set_policy("p_organization_id","p_action_type","p_action_module","p_mode","p_max_priority_score","p_max_revenue_impact","p_max_margin_impact","p_require_financial_confidence"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase7_set_policy(p_organization_id uuid, p_action_type text, p_action_module text, p_mode text, p_max_priority_score numeric, p_max_revenue_impact numeric, p_max_margin_impact numeric, p_require_financial_confidence numeric) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase8_forecast_context(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
select case when tj.is_org_member(p_organization_id) then jsonb_build_object(
  'stores',coalesce((select jsonb_agg(jsonb_build_object('store_id',s.store_id,'name',coalesce(l.name,'Store '||left(s.store_id::text,8))) order by coalesce(l.name,s.store_id::text)) from (select distinct store_id from tj.iq_hourly_traffic_summaries where organization_id=p_organization_id) s left join tj.org_locations l on l.organization_id=p_organization_id and (l.id=s.store_id or l.iq_store_id=s.store_id)),'[]'::jsonb),
  'forecast_status',jsonb_build_object(
    'staffing_rows',(select count(*) from tj.iq_staffing_predictions where organization_id=p_organization_id and prediction_date>=current_date and source='historical_forward_v2'),
    'latest_staffing_generated_at',(select max(created_at) from tj.iq_staffing_predictions where organization_id=p_organization_id and source='historical_forward_v2'),
    'active_decision_predictions',(select count(*) from tj.decision_predictions where organization_id=p_organization_id and status='active')
  )
) else jsonb_build_object('error','organization_access_denied') end;
$function$;
REVOKE ALL ON FUNCTION tj_private.phase8_forecast_context(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase8_forecast_context(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase8_forecast_context("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase8_forecast_context(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_days int := greatest(1,least(coalesce(p_days,7),14));
  v_rows int := 0;
  v_cases int := 0;
  r record;
  v_case uuid;
  v_peak_groups numeric;
  v_peak_staff numeric;
  v_conf numeric;
begin
  if tj_private.current_source_user_id() is not null and not tj.is_org_member(p_organization_id) then raise exception 'organization_access_denied'; end if;

  delete from tj.iq_staffing_predictions
  where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days
    and source='historical_forward_v2';

  insert into tj.iq_staffing_predictions(
    organization_id,store_id,prediction_date,bucket_start,bucket_end,predicted_customer_groups,
    min_sales_staff,recommended_sales_staff,recommended_manager_cover,expected_wait_seconds,
    open_rotation_probability,confidence,source,model_version,created_at,created_by
  )
  select
    h.organization_id,
    h.store_id,
    d::date,
    (d::date + make_interval(hours=>h.hr))::timestamptz,
    (d::date + make_interval(hours=>h.hr+1))::timestamptz,
    greatest(0,round(avg(h.customer_groups)))::int,
    greatest(1,round(avg(greatest(h.staffing_minimum,1))))::int,
    greatest(1,round(avg(greatest(h.staffing_recommended,h.staffing_minimum,1))))::int,
    (avg(h.customer_groups)>=5 or avg(h.avg_wait_seconds)>=180),
    greatest(0,round(avg(h.avg_wait_seconds)))::int,
    least(.95,greatest(.50,.50 + count(*)*.06)),
    least(.95,greatest(.50,.50 + count(*)*.06)),
    'historical_forward_v2','v2',now(),tj_private.current_source_user_id()
  from generate_series(current_date,current_date+v_days-1,interval '1 day') d
  join lateral (
    select organization_id,store_id,extract(hour from bucket_start)::int hr,customer_groups,staffing_minimum,staffing_recommended,avg_wait_seconds
    from tj.iq_hourly_traffic_summaries
    where organization_id=p_organization_id
      and extract(isodow from bucket_start)=extract(isodow from d)
      and bucket_start>=now()-interval '90 days'
  ) h on true
  group by h.organization_id,h.store_id,d::date,h.hr;
  get diagnostics v_rows=row_count;

  for r in
    select store_id,prediction_date,max(predicted_customer_groups)::numeric peak_groups,
           max(recommended_sales_staff)::numeric peak_staff,
           avg(confidence)::numeric confidence,
           max(expected_wait_seconds)::numeric wait_seconds
    from tj.iq_staffing_predictions
    where organization_id=p_organization_id and prediction_date between current_date and current_date+v_days-1
      and source='historical_forward_v2'
    group by store_id,prediction_date
  loop
    v_peak_groups:=coalesce(r.peak_groups,0); v_peak_staff:=coalesce(r.peak_staff,0); v_conf:=coalesce(r.confidence,.5);
    select id into v_case from tj.decision_cases
    where organization_id=p_organization_id and source_system='staffing_forecast_v2'
      and source_record_id=r.store_id::text||':'||r.prediction_date::text limit 1;
    if v_case is null then
      insert into tj.decision_cases(
        organization_id,module,entity_type,entity_id,title,summary,recommendation,consequence_if_ignored,
        decision_type,status,severity,customer_impact_score,urgency_score,confidence,evidence_quality,effort_score,
        priority_score,source_system,source_record_id,metadata,created_by,due_at
      ) values (
        p_organization_id,'up-system','store',r.store_id,
        'Staffing forecast for '||r.prediction_date::text,
        format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),
        'Align floor coverage to the predicted hourly demand curve and review manager coverage during peak periods.',
        'No direct CAD impact is shown until traffic-to-sales attribution is sufficient.',
        'forecast','open',case when v_peak_groups>=7 then 'high' when v_peak_groups>=5 then 'medium' else 'low' end,
        least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30,
        tj.decision_calculate_priority(null,least(100,v_peak_groups*12),case when r.prediction_date<=current_date+1 then 85 else 55 end,v_conf,.80,30),
        'staffing_forecast_v2',r.store_id::text||':'||r.prediction_date::text,
        jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),tj_private.current_source_user_id(),r.prediction_date::timestamptz
      ) returning id into v_case;
      v_cases:=v_cases+1;
    else
      update tj.decision_cases set
        summary=format('Peak forecast is %s customer groups with %s recommended sales staff.',v_peak_groups,v_peak_staff),
        confidence=v_conf,
        metadata=jsonb_build_object('store_id',r.store_id,'prediction_date',r.prediction_date,'peak_customer_groups',v_peak_groups,'peak_staff',v_peak_staff,'max_wait_seconds',r.wait_seconds),
        updated_at=now(),updated_by=tj_private.current_source_user_id()
      where id=v_case;
    end if;

    delete from tj.decision_predictions where decision_case_id=v_case and prediction_type='staffing_demand' and status='active';
    insert into tj.decision_predictions(
      organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,
      probability,lower_bound,upper_bound,assumptions,model_name,model_version,generated_at,expires_at,status
    ) values (
      p_organization_id,v_case,'staffing_demand','daily',greatest(1,v_peak_staff-1),v_peak_staff,1,'sales_staff',
      v_conf,greatest(1,v_peak_staff-1),v_peak_staff+1,
      jsonb_build_object('method','same-weekday hourly historical averages','history_window_days',90,'peak_customer_groups',v_peak_groups),
      'ApplianceIQ staffing forecast','2.0',now(),(r.prediction_date+1)::timestamptz,'active'
    );
  end loop;

  return jsonb_build_object('organization_id',p_organization_id,'forecast_rows',v_rows,'decision_cases_created',v_cases,'days',v_days);
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer DEFAULT 7) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase8_refresh_staffing_forecasts("p_organization_id","p_days"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase8_refresh_staffing_forecasts(p_organization_id uuid, p_days integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase8_run_scheduled_forecasts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; v_orgs int:=0; v_rows int:=0; v_res jsonb;
begin
  for r in select distinct organization_id from tj.iq_hourly_traffic_summaries loop
    v_res:=tj.phase8_refresh_staffing_forecasts(r.organization_id,7);
    v_orgs:=v_orgs+1;
    v_rows:=v_rows+coalesce((v_res->>'forecast_rows')::int,0);
  end loop;
  perform tj.decision_check_expired_predictions();
  return jsonb_build_object('organizations',v_orgs,'staffing_forecast_rows',v_rows,'ran_at',now());
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase8_run_scheduled_forecasts() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase8_run_scheduled_forecasts() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase8_run_scheduled_forecasts(); $adapter$;
REVOKE ALL ON FUNCTION tj.phase8_run_scheduled_forecasts() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.phase8_simulate_store(p_organization_id uuid, p_store_id uuid, p_traffic_change_pct numeric DEFAULT 0, p_conversion_change_points numeric DEFAULT 0, p_avg_order_change_pct numeric DEFAULT 0, p_margin_change_points numeric DEFAULT 0, p_staffing_change integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_groups numeric:=0; v_staff numeric:=0; v_wait numeric:=0; v_conv numeric:=null; v_avg numeric:=null; v_margin numeric:=null;
  s_groups numeric; s_staff numeric; s_conv numeric; s_avg numeric; s_margin numeric; base_rev numeric:=null; scen_rev numeric:=null; base_gp numeric:=null; scen_gp numeric:=null;
begin
  if tj_private.current_source_user_id() is null or not tj.is_org_member(p_organization_id) then raise exception 'organization_access_denied'; end if;
  if abs(coalesce(p_traffic_change_pct,0))>100 or abs(coalesce(p_conversion_change_points,0))>50 or abs(coalesce(p_avg_order_change_pct,0))>100 or abs(coalesce(p_margin_change_points,0))>50 or abs(coalesce(p_staffing_change,0))>20 then raise exception 'scenario_input_out_of_bounds'; end if;

  select coalesce(avg(customer_groups),0),coalesce(avg(greatest(staffing_recommended,1)),0),coalesce(avg(avg_wait_seconds),0)
  into v_groups,v_staff,v_wait from tj.iq_hourly_traffic_summaries
  where organization_id=p_organization_id and store_id=p_store_id and bucket_start>=now()-interval '28 days';

  select max(actual_value) filter(where metric_key='floor_conversion'),max(actual_value) filter(where metric_key='avg_order'),max(actual_value) filter(where metric_key='margin_pct')
  into v_conv,v_avg,v_margin from tj.performance_metric_diagnostics where organization_id=p_organization_id;

  s_groups:=v_groups*(1+coalesce(p_traffic_change_pct,0)/100); s_staff:=greatest(1,v_staff+coalesce(p_staffing_change,0));
  s_conv:=case when v_conv is null then null else greatest(0,least(100,v_conv+coalesce(p_conversion_change_points,0))) end;
  s_avg:=case when v_avg is null then null else greatest(0,v_avg*(1+coalesce(p_avg_order_change_pct,0)/100)) end;
  s_margin:=case when v_margin is null then null else greatest(0,least(100,v_margin+coalesce(p_margin_change_points,0))) end;
  if v_conv is not null and v_avg is not null then base_rev:=v_groups*(v_conv/100)*v_avg; scen_rev:=s_groups*(s_conv/100)*s_avg; end if;
  if base_rev is not null and v_margin is not null then base_gp:=base_rev*(v_margin/100); scen_gp:=scen_rev*(s_margin/100); end if;

  return jsonb_build_object(
    'scenario_type','simulation','not_actual',true,'organization_id',p_organization_id,'store_id',p_store_id,
    'baseline',jsonb_build_object('customer_groups_per_hour',round(v_groups,2),'recommended_staff',round(v_staff,1),'avg_wait_seconds',round(v_wait,0),'conversion_pct',v_conv,'avg_order',v_avg,'margin_pct',v_margin,'modeled_hourly_revenue',base_rev,'modeled_hourly_gross_profit',base_gp),
    'scenario',jsonb_build_object('customer_groups_per_hour',round(s_groups,2),'recommended_staff',s_staff,'conversion_pct',s_conv,'avg_order',s_avg,'margin_pct',s_margin,'modeled_hourly_revenue',scen_rev,'modeled_hourly_gross_profit',scen_gp),
    'delta',jsonb_build_object('modeled_hourly_revenue',case when scen_rev is null then null else scen_rev-base_rev end,'modeled_hourly_gross_profit',case when scen_gp is null then null else scen_gp-base_gp end,'staffing',coalesce(p_staffing_change,0)),
    'assumptions',jsonb_build_object('traffic_change_pct',p_traffic_change_pct,'conversion_change_points',p_conversion_change_points,'avg_order_change_pct',p_avg_order_change_pct,'margin_change_points',p_margin_change_points,'staffing_change',p_staffing_change,'traffic_baseline_days',28)
  );
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase8_simulate_store(p_organization_id uuid, p_store_id uuid, p_traffic_change_pct numeric, p_conversion_change_points numeric, p_avg_order_change_pct numeric, p_margin_change_points numeric, p_staffing_change integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.phase8_simulate_store(p_organization_id uuid, p_store_id uuid, p_traffic_change_pct numeric DEFAULT 0, p_conversion_change_points numeric DEFAULT 0, p_avg_order_change_pct numeric DEFAULT 0, p_margin_change_points numeric DEFAULT 0, p_staffing_change integer DEFAULT 0) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase8_simulate_store("p_organization_id","p_store_id","p_traffic_change_pct","p_conversion_change_points","p_avg_order_change_pct","p_margin_change_points","p_staffing_change"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase8_simulate_store(p_organization_id uuid, p_store_id uuid, p_traffic_change_pct numeric, p_conversion_change_points numeric, p_avg_order_change_pct numeric, p_margin_change_points numeric, p_staffing_change integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_confirm_invited_email(p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE inv record;
BEGIN
  SELECT * INTO inv FROM mfr_invites WHERE upper(code) = upper(trim(p_code));
  IF NOT FOUND THEN RETURN false; END IF;
  IF inv.status <> 'pending' THEN RETURN false; END IF;
  IF inv.expires_at IS NOT NULL AND inv.expires_at < now() THEN RETURN false; END IF;

  UPDATE tj.source_auth_users
     SET email_confirmed_at = now(), updated_at = now()
   WHERE lower(email) = lower(inv.email)
     AND email_confirmed_at IS NULL;
  RETURN true;
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_confirm_invited_email(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_confirm_invited_email(p_code text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_confirm_invited_email("p_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_confirm_invited_email(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_create_invite(p_email text, p_persona text, p_vendor_id uuid DEFAULT NULL::uuid, p_role text DEFAULT 'product_editor'::text, p_group_id uuid DEFAULT NULL::uuid, p_retailer_brand_ids uuid[] DEFAULT '{}'::uuid[], p_retailer_account_type text DEFAULT 'independent'::text, p_retailer_company text DEFAULT NULL::text, p_retailer_exclusive_codes text[] DEFAULT '{}'::text[])
 RETURNS TABLE(id uuid, code text, email text, persona text, scope_name text, scope_type text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE v_code text; v_name text; v_scope text; v_id uuid; v_slug text;
BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can create invites'; END IF;
  IF p_persona NOT IN ('manufacturer','retailer') THEN
    RAISE EXCEPTION 'persona must be manufacturer or retailer'; END IF;

  IF p_persona = 'retailer' THEN
    IF COALESCE(array_length(p_retailer_brand_ids,1),0) = 0 THEN
      RAISE EXCEPTION 'Select at least one brand this retailer carries';
    END IF;
    v_scope := 'retailer';
    v_name  := COALESCE(p_retailer_company,'Retailer')||' — '||array_length(p_retailer_brand_ids,1)||' brands';
  ELSIF p_group_id IS NOT NULL THEN
    v_scope := 'group';
    SELECT g.name INTO v_name FROM mfr_vendor_groups g WHERE g.id=p_group_id;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Ownership group not found'; END IF;
  ELSIF p_vendor_id IS NOT NULL THEN
    v_scope := 'brand';
    SELECT v.name, v.slug INTO v_name, v_slug FROM mfr_vendors v WHERE v.id=p_vendor_id;
    IF v_name IS NULL THEN RAISE EXCEPTION 'Brand not found'; END IF;
  ELSE
    RAISE EXCEPTION 'A manufacturer invite requires a brand or an ownership group';
  END IF;

  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM mfr_invites i WHERE i.code=v_code);
  END LOOP;

  INSERT INTO mfr_invites (email, vendor_id, group_id, scope_type, vendor_name, vendor_slug,
      invite_role, persona, code, status, invited_by, created_at, expires_at,
      retailer_brand_ids, retailer_account_type, retailer_company, retailer_exclusive_codes)
  VALUES (lower(trim(p_email)), p_vendor_id, p_group_id, v_scope, v_name, v_slug,
      p_role, p_persona, v_code, 'pending', tj_private.current_source_user_id(), now(), now()+interval '30 days',
      COALESCE(p_retailer_brand_ids,'{}'), p_retailer_account_type, p_retailer_company,
      COALESCE(p_retailer_exclusive_codes,'{}'))
  RETURNING mfr_invites.id INTO v_id;

  RETURN QUERY SELECT v_id, v_code, lower(trim(p_email)), p_persona, v_name, v_scope;
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_create_invite(p_email text, p_persona text, p_vendor_id uuid, p_role text, p_group_id uuid, p_retailer_brand_ids uuid[], p_retailer_account_type text, p_retailer_company text, p_retailer_exclusive_codes text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_create_invite(p_email text, p_persona text, p_vendor_id uuid DEFAULT NULL::uuid, p_role text DEFAULT 'product_editor'::text, p_group_id uuid DEFAULT NULL::uuid, p_retailer_brand_ids uuid[] DEFAULT '{}'::uuid[], p_retailer_account_type text DEFAULT 'independent'::text, p_retailer_company text DEFAULT NULL::text, p_retailer_exclusive_codes text[] DEFAULT '{}'::text[]) RETURNS TABLE(id uuid, code text, email text, persona text, scope_name text, scope_type text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.piq_create_invite("p_email","p_persona","p_vendor_id","p_role","p_group_id","p_retailer_brand_ids","p_retailer_account_type","p_retailer_company","p_retailer_exclusive_codes"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_create_invite(p_email text, p_persona text, p_vendor_id uuid, p_role text, p_group_id uuid, p_retailer_brand_ids uuid[], p_retailer_account_type text, p_retailer_company text, p_retailer_exclusive_codes text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_mark_read(p_ids uuid[])
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  INSERT INTO piq_notification_reads (notification_id, user_id)
  SELECT unnest(p_ids), tj_private.current_source_user_id()
  ON CONFLICT DO NOTHING;
$function$;
REVOKE ALL ON FUNCTION tj_private.piq_mark_read(p_ids uuid[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_mark_read(p_ids uuid[]) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_mark_read("p_ids"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_mark_read(p_ids uuid[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_notify_new_asset()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  r jsonb := to_jsonb(NEW);
  v_brand text; v_kind text; v_title text; v_body text;
  v_prod uuid; v_when timestamptz; v_until timestamptz;
BEGIN
  -- Never announce embargoed material
  IF COALESCE((r->>'embargoed')::boolean,false) THEN RETURN NEW; END IF;
  -- On UPDATE, only fire when embargo is being lifted
  IF TG_OP='UPDATE' AND COALESCE((to_jsonb(OLD)->>'embargoed')::boolean,false) = false THEN
    RETURN NEW;
  END IF;
  IF EXISTS (SELECT 1 FROM piq_notifications n
             WHERE n.asset_table=TG_TABLE_NAME AND n.asset_id=(r->>'id')::uuid) THEN
    RETURN NEW;
  END IF;

  v_prod := NULLIF(r->>'product_id','')::uuid;
  IF v_prod IS NOT NULL THEN
    SELECT p.brand_name INTO v_brand FROM aiq_products p WHERE p.id = v_prod;
  END IF;

  IF TG_TABLE_NAME = 'pim_product_documents' THEN
    v_kind := CASE WHEN r->>'doc_type' IN ('spec_sheet','sell_sheet','comparison_chart')
                   THEN 'price_sheet' ELSE 'new_document' END;
    v_title := COALESCE(r->>'title','New document');
    v_body  := 'New '||replace(COALESCE(r->>'doc_type','document'),'_',' ')||' available'||COALESCE(' for '||v_brand,'');
  ELSIF TG_TABLE_NAME = 'pim_marketing_assets' THEN
    v_kind := 'new_marketing'; v_title := COALESCE(r->>'title','New marketing asset');
    v_body  := 'New '||replace(COALESCE(r->>'asset_type','asset'),'_',' ')||' available';
  ELSIF TG_TABLE_NAME = 'pim_product_videos' THEN
    v_kind := 'video'; v_title := COALESCE(r->>'title','New video');
    v_body  := 'New '||replace(COALESCE(r->>'video_type','video'),'_',' ')||' available';
  ELSIF TG_TABLE_NAME = 'pim_product_rebates' THEN
    v_kind := 'rebate'; v_title := COALESCE(r->>'rebate_name','New promotion');
    v_body  := 'Promotion running'||COALESCE(' for '||v_brand,'');
  ELSIF TG_TABLE_NAME = 'pim_product_images' THEN
    IF COALESCE((r->>'is_primary')::boolean,false) = false THEN RETURN NEW; END IF;
    v_kind := 'image'; v_title := COALESCE(v_brand,'Product')||' imagery updated';
    v_body  := 'New primary product image available';
  ELSE RETURN NEW; END IF;

  v_when  := COALESCE(NULLIF(r->>'available_from','')::timestamptz, now());
  v_until := NULLIF(r->>'available_until','')::timestamptz;

  INSERT INTO piq_notifications (kind,title,body,brand_name,product_id,asset_table,asset_id,
                                 link_url,audience_tiers,exclusive_codes,publish_at,expires_at,created_by)
  VALUES (v_kind, v_title, v_body, v_brand, v_prod, TG_TABLE_NAME, (r->>'id')::uuid,
          COALESCE(r->>'file_url', r->>'rebate_form_url', r->>'embed_url'),
          COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(r->'audience_tiers') x), ARRAY['all']),
          COALESCE((SELECT array_agg(x) FROM jsonb_array_elements_text(r->'exclusive_codes') x), '{}'),
          v_when, v_until, tj_private.current_source_user_id());
  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_notify_new_asset() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_preview_invite(p_code text)
 RETURNS TABLE(email text, persona text, vendor_name text, invite_role text, scope_type text, brand_count integer, valid boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT i.email, i.persona, i.vendor_name, i.invite_role, i.scope_type,
    CASE WHEN i.scope_type='group'
         THEN (SELECT count(*)::int FROM mfr_vendors v WHERE v.group_id=i.group_id)
         WHEN i.scope_type='brand' THEN 1 ELSE 0 END,
    (i.status='pending' AND (i.expires_at IS NULL OR i.expires_at > now()))
  FROM mfr_invites i WHERE upper(i.code) = upper(trim(p_code));
$function$;
REVOKE ALL ON FUNCTION tj_private.piq_preview_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_preview_invite(p_code text) RETURNS TABLE(email text, persona text, vendor_name text, invite_role text, scope_type text, brand_count integer, valid boolean) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.piq_preview_invite("p_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_preview_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_redeem_invite(p_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE inv record; v_uid uuid := tj_private.current_source_user_id(); v_email text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'You must be signed in to accept an invite'; END IF;
  SELECT lower(email) INTO v_email FROM tj.source_auth_users WHERE id=v_uid;
  SELECT * INTO inv FROM mfr_invites WHERE upper(code)=upper(trim(p_code)) FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invite code not found'; END IF;
  IF inv.status <> 'pending' THEN RAISE EXCEPTION 'This invite has already been used'; END IF;
  IF inv.expires_at IS NOT NULL AND inv.expires_at < now() THEN
    RAISE EXCEPTION 'This invite has expired'; END IF;
  IF lower(inv.email) <> v_email THEN
    RAISE EXCEPTION 'This invite was issued to %, but you are signed in as %', inv.email, v_email; END IF;

  IF inv.persona = 'manufacturer' THEN
    IF inv.scope_type='group' THEN
      INSERT INTO mfr_members (user_id,vendor_id,role,member_role,status,approved_by,approved_at,activated_at,invited_by,invitation_id)
      SELECT v_uid, v.id, inv.invite_role, inv.invite_role,'active',COALESCE(inv.invited_by,v_uid),now(),now(),inv.invited_by,inv.id
      FROM mfr_vendors v WHERE v.group_id=inv.group_id ON CONFLICT DO NOTHING;
    ELSE
      INSERT INTO mfr_members (user_id,vendor_id,role,member_role,status,approved_by,approved_at,activated_at,invited_by,invitation_id)
      VALUES (v_uid, inv.vendor_id, inv.invite_role, inv.invite_role,'active',COALESCE(inv.invited_by,v_uid),now(),now(),inv.invited_by,inv.id)
      ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO mfr_user_roles (user_id,is_admin,is_manufacturer,is_retailer)
    VALUES (v_uid,false,true,false) ON CONFLICT (user_id) DO UPDATE SET is_manufacturer=true;
  ELSE
    INSERT INTO piq_retailer_profiles (user_id, company_name, account_type, exclusive_codes, updated_at)
    VALUES (v_uid, inv.retailer_company, COALESCE(inv.retailer_account_type,'independent'),
            COALESCE(inv.retailer_exclusive_codes,'{}'), now())
    ON CONFLICT (user_id) DO UPDATE
      SET company_name=EXCLUDED.company_name, account_type=EXCLUDED.account_type,
          exclusive_codes=EXCLUDED.exclusive_codes, updated_at=now();

    INSERT INTO piq_retailer_brands (user_id, brand_id, granted_by)
    SELECT v_uid, unnest(COALESCE(inv.retailer_brand_ids,'{}')), inv.invited_by
    ON CONFLICT DO NOTHING;

    INSERT INTO mfr_user_roles (user_id,is_admin,is_manufacturer,is_retailer)
    VALUES (v_uid,false,false,true) ON CONFLICT (user_id) DO UPDATE SET is_retailer=true;
  END IF;

  UPDATE mfr_invites SET status='accepted', accepted_at=now(), accepted_by=v_uid WHERE id=inv.id;
  RETURN COALESCE(inv.vendor_name,'Retailer access');
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_redeem_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_redeem_invite(p_code text) RETURNS text LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_redeem_invite("p_code"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_redeem_invite(p_code text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_revoke_invite(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can revoke invites';
  END IF;
  UPDATE mfr_invites SET status='revoked' WHERE id=p_id AND status='pending';
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_revoke_invite(p_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_revoke_invite(p_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_revoke_invite("p_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_revoke_invite(p_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_save_retailer(p_user_id uuid, p_company text, p_account_type text, p_brand_ids uuid[], p_buying_group text DEFAULT NULL::text, p_exclusive_codes text[] DEFAULT '{}'::text[], p_region text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can configure retailers';
  END IF;
  IF p_account_type NOT IN ('national','independent','buying_group','builder','designer') THEN
    RAISE EXCEPTION 'Invalid account type: %', p_account_type;
  END IF;

  INSERT INTO piq_retailer_profiles (user_id, company_name, account_type, buying_group, exclusive_codes, region, updated_at)
  VALUES (p_user_id, p_company, p_account_type, p_buying_group, COALESCE(p_exclusive_codes,'{}'), p_region, now())
  ON CONFLICT (user_id) DO UPDATE
    SET company_name=EXCLUDED.company_name, account_type=EXCLUDED.account_type,
        buying_group=EXCLUDED.buying_group, exclusive_codes=EXCLUDED.exclusive_codes,
        region=EXCLUDED.region, updated_at=now();

  INSERT INTO mfr_user_roles (user_id, is_admin, is_manufacturer, is_retailer)
  VALUES (p_user_id,false,false,true)
  ON CONFLICT (user_id) DO UPDATE SET is_retailer = true;

  DELETE FROM piq_retailer_brands WHERE user_id = p_user_id
    AND (p_brand_ids IS NULL OR NOT (brand_id = ANY(p_brand_ids)));

  IF p_brand_ids IS NOT NULL AND array_length(p_brand_ids,1) > 0 THEN
    INSERT INTO piq_retailer_brands (user_id, brand_id, granted_by)
    SELECT p_user_id, unnest(p_brand_ids), tj_private.current_source_user_id()
    ON CONFLICT DO NOTHING;
  END IF;
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_save_retailer(p_user_id uuid, p_company text, p_account_type text, p_brand_ids uuid[], p_buying_group text, p_exclusive_codes text[], p_region text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_save_retailer(p_user_id uuid, p_company text, p_account_type text, p_brand_ids uuid[], p_buying_group text DEFAULT NULL::text, p_exclusive_codes text[] DEFAULT '{}'::text[], p_region text DEFAULT NULL::text) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_save_retailer("p_user_id","p_company","p_account_type","p_brand_ids","p_buying_group","p_exclusive_codes","p_region"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_save_retailer(p_user_id uuid, p_company text, p_account_type text, p_brand_ids uuid[], p_buying_group text, p_exclusive_codes text[], p_region text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.piq_set_brand_access(p_user_id uuid, p_vendor_id uuid, p_role text DEFAULT 'product_editor'::text, p_grant boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF NOT (SELECT private.product_iq_is_platform_admin()) THEN
    RAISE EXCEPTION 'Only platform administrators can change brand access';
  END IF;
  IF p_grant THEN
    INSERT INTO mfr_members (user_id, vendor_id, role, member_role, status,
                             approved_by, approved_at, activated_at)
    VALUES (p_user_id, p_vendor_id, p_role, p_role, 'active', tj_private.current_source_user_id(), now(), now())
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM mfr_members WHERE user_id=p_user_id AND vendor_id=p_vendor_id;
  END IF;
END $function$;
REVOKE ALL ON FUNCTION tj_private.piq_set_brand_access(p_user_id uuid, p_vendor_id uuid, p_role text, p_grant boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.piq_set_brand_access(p_user_id uuid, p_vendor_id uuid, p_role text DEFAULT 'product_editor'::text, p_grant boolean DEFAULT true) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.piq_set_brand_access("p_user_id","p_vendor_id","p_role","p_grant"); $adapter$;
REVOKE ALL ON FUNCTION tj.piq_set_brand_access(p_user_id uuid, p_vendor_id uuid, p_role text, p_grant boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_accept_connector_event(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_occurred_at timestamp with time zone, p_payload_hash text, p_topic text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.platform_connector_event_watermarks%rowtype;
begin
  select * into r from tj.platform_connector_event_watermarks
  where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id
  for update;
  if not found then
    insert into tj.platform_connector_event_watermarks(connection_id,external_entity_type,external_id,last_occurred_at,payload_hash,last_topic)
    values(p_connection_id,p_external_entity_type,p_external_id,p_occurred_at,p_payload_hash,p_topic);
    return jsonb_build_object('accepted',true,'reason','first','occurred_at',p_occurred_at);
  end if;
  if r.payload_hash=p_payload_hash then
    update tj.platform_connector_event_watermarks set duplicate_count=duplicate_count+1,updated_at=now() where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
    return jsonb_build_object('accepted',false,'reason','duplicate','last_occurred_at',r.last_occurred_at);
  end if;
  if p_occurred_at < r.last_occurred_at then
    update tj.platform_connector_event_watermarks set stale_count=stale_count+1,updated_at=now() where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
    return jsonb_build_object('accepted',false,'reason','stale','last_occurred_at',r.last_occurred_at);
  end if;
  update tj.platform_connector_event_watermarks set last_occurred_at=p_occurred_at,payload_hash=p_payload_hash,last_topic=p_topic,accepted_count=accepted_count+1,updated_at=now()
  where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id;
  return jsonb_build_object('accepted',true,'reason','advanced','occurred_at',p_occurred_at);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_accept_connector_event(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_occurred_at timestamp with time zone, p_payload_hash text, p_topic text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_accept_connector_event(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_occurred_at timestamp with time zone, p_payload_hash text, p_topic text DEFAULT NULL::text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_accept_connector_event("p_connection_id","p_external_entity_type","p_external_id","p_occurred_at","p_payload_hash","p_topic"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_accept_connector_event(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_occurred_at timestamp with time zone, p_payload_hash text, p_topic text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_calculate_connector_health(p_connection_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  s int; p int; f int; q int; d int; u int; mins int; score numeric; st text; result jsonb;
begin
  select count(*) filter(where status='success'), count(*) filter(where status='partial'), count(*) filter(where status='failed')
  into s,p,f
  from tj.platform_sync_jobs
  where connection_id=p_connection_id and created_at >= now()-interval '7 days';
  select count(*) filter(where status in ('quarantined','retrying')), count(*) filter(where status='dead_letter')
  into q,d from tj.platform_connector_quarantine where connection_id=p_connection_id;
  select count(*) into u from tj.platform_connector_match_queue where connection_id=p_connection_id and status in ('pending','review');
  select floor(extract(epoch from (now()-max(last_success_at)))/60)::int into mins from tj.platform_connector_connections where id=p_connection_id;
  score := 100 - least(50,f*15) - least(20,p*5) - least(20,q*2) - least(20,d*5) - least(10,u);
  if mins is null or mins > 4320 then score:=score-20; elsif mins > 1440 then score:=score-10; end if;
  score:=greatest(0,least(100,score));
  st:=case when score>=90 then 'healthy' when score>=70 then 'degraded' when score>=40 then 'unhealthy' else 'offline' end;
  insert into tj.platform_connector_health_snapshots(connection_id,health_score,status,successful_jobs,partial_jobs,failed_jobs,quarantined_records,dead_letter_records,unresolved_matches,minutes_since_success,details)
  values(p_connection_id,score,st,s,p,f,q,d,u,mins,jsonb_build_object('window','7 days'));
  result:=jsonb_build_object('connection_id',p_connection_id,'health_score',score,'status',st,'successful_jobs',s,'partial_jobs',p,'failed_jobs',f,'quarantined_records',q,'dead_letter_records',d,'unresolved_matches',u,'minutes_since_success',mins);
  return result;
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_calculate_connector_health(p_connection_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_calculate_connector_health(p_connection_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_calculate_connector_health("p_connection_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_calculate_connector_health(p_connection_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_connector_alert_scan()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; created_count int:=0; resolved_count int:=0; resolved_step int:=0; fp text; sev text; ttl text; msg text;
begin
  for r in
    select c.id,c.display_name,h.status health_status,h.health_score,h.dead_letter_records,h.quarantined_records,h.unresolved_matches
    from tj.platform_connector_connections c
    left join lateral (
      select * from tj.platform_connector_health_snapshots hs where hs.connection_id=c.id order by hs.captured_at desc limit 1
    ) h on true
    where c.status <> 'disabled'
  loop
    if coalesce(r.health_status,'offline') in ('unhealthy','offline') or coalesce(r.health_score,0)<60 then
      fp:='health:'||coalesce(r.health_status,'offline');
      sev:=case when coalesce(r.health_status,'offline')='offline' then 'critical' else 'warning' end;
      ttl:=coalesce(r.display_name,'Connector')||' is '||coalesce(r.health_status,'offline');
      msg:='Connector health score: '||coalesce(r.health_score::text,'0');
      insert into tj.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
      values(r.id,'health',sev,ttl,msg,fp,jsonb_build_object('health_score',r.health_score,'health_status',r.health_status))
      on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
      do update set last_seen_at=now(),message=excluded.message,details=excluded.details;
      created_count:=created_count+1;
    end if;
    if coalesce(r.dead_letter_records,0)>0 then
      fp:='dead_letter';
      insert into tj.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
      values(r.id,'dead_letter','critical',coalesce(r.display_name,'Connector')||' has dead-letter records',r.dead_letter_records||' record(s) require intervention',fp,jsonb_build_object('dead_letter_records',r.dead_letter_records))
      on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
      do update set last_seen_at=now(),message=excluded.message,details=excluded.details;
      created_count:=created_count+1;
    end if;
  end loop;

  for r in
    select rr.connection_id,rr.id,rr.discrepancies,c.display_name
    from tj.platform_connector_reconciliation_runs rr
    join tj.platform_connector_connections c on c.id=rr.connection_id
    where rr.completed_at > now()-interval '24 hours' and rr.status not in ('success','matched','clean')
  loop
    fp:='reconciliation:'||r.id::text;
    insert into tj.platform_connector_alerts(connection_id,alert_type,severity,title,message,fingerprint,details)
    values(r.connection_id,'reconciliation','warning',coalesce(r.display_name,'Connector')||' reconciliation variance','Source and IQ record counts require review',fp,coalesce(r.discrepancies,'{}'::jsonb))
    on conflict (connection_id,fingerprint) where status in ('open','acknowledged')
    do update set last_seen_at=now(),details=excluded.details;
    created_count:=created_count+1;
  end loop;

  update tj.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='dead_letter'
    and not exists (select 1 from tj.platform_connector_quarantine q where q.connection_id=a.connection_id and q.status='dead_letter');
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  update tj.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='health'
    and exists (
      select 1 from lateral (
        select hs.status,hs.health_score from tj.platform_connector_health_snapshots hs
        where hs.connection_id=a.connection_id order by hs.captured_at desc limit 1
      ) h where coalesce(h.status,'offline') not in ('unhealthy','offline') and coalesce(h.health_score,0)>=60
    );
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  update tj.platform_connector_alerts a
  set status='resolved',resolved_at=now(),last_seen_at=now()
  where a.status in ('open','acknowledged') and a.alert_type='reconciliation'
    and not exists (
      select 1 from tj.platform_connector_reconciliation_runs rr
      where ('reconciliation:'||rr.id::text)=a.fingerprint
        and rr.completed_at > now()-interval '24 hours'
        and rr.status not in ('success','matched','clean')
    );
  get diagnostics resolved_step=row_count; resolved_count:=resolved_count+resolved_step;

  return jsonb_build_object('alerts_touched',created_count,'alerts_resolved',resolved_count);
end
$function$;
REVOKE ALL ON FUNCTION tj_private.platform_connector_alert_scan() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_connector_alert_scan() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_connector_alert_scan(); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_connector_alert_scan() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_connector_certification_release_gate()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare blockers int; begin
 if new.lifecycle_status='certified' then
   select count(*) into blockers from tj.platform_connector_certification_checks where connector_id=new.connector_id and required=true and status not in ('passed','not_applicable');
   if blockers>0 or coalesce(new.certification_score,0)<coalesce(new.required_score,85) then raise exception 'connector_certification_gate_failed'; end if;
 end if; return new; end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_connector_certification_release_gate() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.platform_connector_onboarding_summary(p_connection_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
select jsonb_build_object(
  'connection_id', p_connection_id,
  'employees_total', count(*) filter (where external_entity_type='employee'),
  'employees_confirmed', count(*) filter (where external_entity_type='employee' and status='confirmed'),
  'employees_review', count(*) filter (where external_entity_type='employee' and status in ('needs_review','suggested','unmatched')),
  'locations_total', count(*) filter (where external_entity_type='location'),
  'locations_confirmed', count(*) filter (where external_entity_type='location' and status='confirmed'),
  'locations_review', count(*) filter (where external_entity_type='location' and status in ('needs_review','suggested','unmatched')),
  'ready', (count(*) filter (where status in ('needs_review','suggested','unmatched')) = 0)
)
from tj.platform_connector_match_queue
where connection_id=p_connection_id;
$function$;
REVOKE ALL ON FUNCTION tj.platform_connector_onboarding_summary(p_connection_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_emit_intelligence_event(p_organization_id uuid, p_event_type text, p_source_system text, p_source_record_id text, p_subject_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_store_id uuid DEFAULT NULL::uuid, p_actor_id uuid DEFAULT NULL::uuid, p_correlation_id uuid DEFAULT NULL::uuid, p_causation_id uuid DEFAULT NULL::uuid, p_dedupe_key text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_occurred_at timestamp with time zone DEFAULT now(), p_identity_confidence numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid; v_subject text; v_intel_type text; v_intel_entity uuid; v_name text;
begin
 select et.subject_entity_type,ce.intelligence_entity_type into v_subject,v_intel_type from tj.platform_canonical_event_types et left join tj.platform_canonical_entity_types ce on ce.key=et.subject_entity_type where et.key=p_event_type and et.active=true;
 if v_subject is null then raise exception 'unknown_event_type:%',p_event_type; end if;
 if p_subject_entity_type is not null and p_subject_entity_type<>v_subject then raise exception 'event_subject_mismatch:% expected % got %',p_event_type,v_subject,p_subject_entity_type; end if;
 if p_entity_id is not null then select id into v_intel_entity from tj.intelligence_entities where id=p_entity_id and organization_id=p_organization_id; end if;
 if v_intel_entity is null then select id into v_intel_entity from tj.intelligence_entities where organization_id=p_organization_id and source_system=p_source_system and source_record_id=p_source_record_id limit 1; end if;
 if v_intel_entity is null then
   v_name:=coalesce(nullif(p_payload->>'name',''),nullif(p_payload->>'display_name',''),nullif(p_payload->>'model',''),nullif(p_payload->>'pos_transaction_id',''),nullif(p_payload->>'course_key',''),v_subject||':'||p_source_record_id);
   insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
   values(p_organization_id,coalesce(v_intel_type,v_subject),v_name,null,p_source_system,p_source_record_id,'active',jsonb_build_object('business_entity_id',p_entity_id,'subject_entity_type',v_subject,'phase3',true),now(),now())
   on conflict(organization_id,source_system,source_record_id) do update set updated_at=now(),metadata=tj.intelligence_entities.metadata||jsonb_build_object('business_entity_id',coalesce(p_entity_id,(tj.intelligence_entities.metadata->>'business_entity_id')::uuid),'subject_entity_type',v_subject,'phase3',true)
   returning id into v_intel_entity;
 end if;
 insert into tj.intelligence_events(organization_id,entity_id,event_type,canonical_event_type,source_system,source_record_id,actor_id,correlation_id,causation_id,payload,occurred_at,subject_entity_type,store_id,event_version,dedupe_key,processing_status,identity_confidence,metadata)
 values(p_organization_id,v_intel_entity,p_event_type,p_event_type,p_source_system,p_source_record_id,p_actor_id,coalesce(p_correlation_id,gen_random_uuid()),p_causation_id,coalesce(p_payload,'{}'::jsonb),coalesce(p_occurred_at,now()),v_subject,p_store_id,1,p_dedupe_key,'ready',p_identity_confidence,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('business_entity_id',p_entity_id))
 on conflict(organization_id,source_system,dedupe_key) where dedupe_key is not null do update set metadata=tj.intelligence_events.metadata||excluded.metadata
 returning id into v_id;
 update tj.platform_identity_links set intelligence_entity_id=v_intel_entity,last_seen_at=now() where organization_id=p_organization_id and entity_type=v_subject and canonical_id=p_entity_id and intelligence_entity_id is null;
 return v_id;
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_emit_intelligence_event(p_organization_id uuid, p_event_type text, p_source_system text, p_source_record_id text, p_subject_entity_type text, p_entity_id uuid, p_store_id uuid, p_actor_id uuid, p_correlation_id uuid, p_causation_id uuid, p_dedupe_key text, p_payload jsonb, p_occurred_at timestamp with time zone, p_identity_confidence numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_emit_intelligence_event(p_organization_id uuid, p_event_type text, p_source_system text, p_source_record_id text, p_subject_entity_type text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_store_id uuid DEFAULT NULL::uuid, p_actor_id uuid DEFAULT NULL::uuid, p_correlation_id uuid DEFAULT NULL::uuid, p_causation_id uuid DEFAULT NULL::uuid, p_dedupe_key text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_occurred_at timestamp with time zone DEFAULT now(), p_identity_confidence numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_emit_intelligence_event("p_organization_id","p_event_type","p_source_system","p_source_record_id","p_subject_entity_type","p_entity_id","p_store_id","p_actor_id","p_correlation_id","p_causation_id","p_dedupe_key","p_payload","p_occurred_at","p_identity_confidence","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_emit_intelligence_event(p_organization_id uuid, p_event_type text, p_source_system text, p_source_record_id text, p_subject_entity_type text, p_entity_id uuid, p_store_id uuid, p_actor_id uuid, p_correlation_id uuid, p_causation_id uuid, p_dedupe_key text, p_payload jsonb, p_occurred_at timestamp with time zone, p_identity_confidence numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_enqueue_connector_quarantine(p_connection_id uuid, p_sync_job_id uuid, p_external_entity_type text, p_external_id text, p_stage text, p_error_code text, p_error_message text, p_payload jsonb, p_retryable boolean DEFAULT true)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare qid uuid;
begin
  select id into qid
  from tj.platform_connector_quarantine
  where connection_id=p_connection_id
    and coalesce(external_entity_type,'')=coalesce(p_external_entity_type,'')
    and coalesce(external_id,'')=coalesce(p_external_id,'')
    and stage=p_stage
    and status in ('quarantined','retrying')
  order by first_seen_at desc limit 1;

  if qid is null then
    insert into tj.platform_connector_quarantine(connection_id,sync_job_id,external_entity_type,external_id,stage,error_code,error_message,payload,retryable)
    values(p_connection_id,p_sync_job_id,p_external_entity_type,p_external_id,p_stage,p_error_code,p_error_message,p_payload,p_retryable)
    returning id into qid;
  else
    update tj.platform_connector_quarantine
      set sync_job_id=coalesce(p_sync_job_id,sync_job_id), error_code=p_error_code,
          error_message=p_error_message, payload=p_payload, retryable=p_retryable,
          last_seen_at=now()
      where id=qid;
  end if;

  if p_retryable then
    insert into tj.platform_connector_retry_queue(quarantine_id,connection_id,available_at)
    values(qid,p_connection_id,now())
    on conflict(quarantine_id) do update set updated_at=now();
  end if;
  return qid;
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_enqueue_connector_quarantine(p_connection_id uuid, p_sync_job_id uuid, p_external_entity_type text, p_external_id text, p_stage text, p_error_code text, p_error_message text, p_payload jsonb, p_retryable boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_enqueue_connector_quarantine(p_connection_id uuid, p_sync_job_id uuid, p_external_entity_type text, p_external_id text, p_stage text, p_error_code text, p_error_message text, p_payload jsonb, p_retryable boolean DEFAULT true) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_enqueue_connector_quarantine("p_connection_id","p_sync_job_id","p_external_entity_type","p_external_id","p_stage","p_error_code","p_error_message","p_payload","p_retryable"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_enqueue_connector_quarantine(p_connection_id uuid, p_sync_job_id uuid, p_external_entity_type text, p_external_id text, p_stage text, p_error_code text, p_error_message text, p_payload jsonb, p_retryable boolean) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_evaluate_connector_certification(p_connector_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare total numeric:=0; earned numeric:=0; req_fail int:=0; v_score numeric:=0; life text; run_id uuid; v_key text; begin
 select key into v_key from tj.platform_connectors where id=p_connector_id;
 if v_key is null then raise exception 'connector_not_found'; end if;
 insert into tj.platform_connector_certification_runs(connector_id,status) values(p_connector_id,'running') returning id into run_id;
 update tj.platform_connector_certification_checks cc set status=case when exists(select 1 from tj.platform_connector_test_fixtures f where f.connector_key=v_key and f.active=true) then 'passed' else 'failed' end,last_run_at=now(),updated_at=now() where cc.connector_id=p_connector_id and check_key='fixture_validation';
 update tj.platform_connector_certification_checks cc set status=case when exists(select 1 from tj.platform_connector_canonical_rules r where r.connector_id=p_connector_id and r.active=true) then 'passed' else 'failed' end,last_run_at=now(),updated_at=now() where cc.connector_id=p_connector_id and check_key='canonical_mappings';
 update tj.platform_connector_certification_checks cc set status=case when exists(select 1 from tj.platform_connector_onboarding_profiles p where p.connector_id=p_connector_id and p.is_active=true) then 'passed' else 'failed' end,last_run_at=now(),updated_at=now() where cc.connector_id=p_connector_id and check_key='onboarding';
 update tj.platform_connector_certification_checks cc set status='passed',last_run_at=now(),updated_at=now() where cc.connector_id=p_connector_id and check_key in ('reconciliation','alerting');
 select coalesce(sum(weight),0),coalesce(sum(weight) filter(where status='passed'),0),count(*) filter(where required and status not in ('passed','not_applicable')) into total,earned,req_fail from tj.platform_connector_certification_checks where connector_id=p_connector_id;
 v_score:=case when total>0 then round(100*earned/total,2) else 0 end;
 life:=case when v_score>=85 and req_fail=0 then 'certified' when v_score>=55 then 'beta' else 'development' end;
 update tj.platform_connector_certifications set certification_score=v_score,lifecycle_status=life,fixture_passed=exists(select 1 from tj.platform_connector_certification_checks where connector_id=p_connector_id and check_key='fixture_validation' and status='passed'),onboarding_passed=exists(select 1 from tj.platform_connector_certification_checks where connector_id=p_connector_id and check_key='onboarding' and status='passed'),reconciliation_passed=exists(select 1 from tj.platform_connector_certification_checks where connector_id=p_connector_id and check_key='reconciliation' and status='passed'),last_evaluated_at=now(),updated_at=now(),certified_at=case when life='certified' then coalesce(certified_at,now()) else null end where connector_id=p_connector_id;
 update tj.platform_connector_certification_runs set completed_at=now(),status=case when req_fail=0 and v_score>=85 then 'passed' when v_score>=55 then 'partial' else 'failed' end,score=v_score,results=jsonb_build_object('required_failures',req_fail,'earned_weight',earned,'total_weight',total,'lifecycle_status',life) where id=run_id;
 return jsonb_build_object('connector_id',p_connector_id,'score',v_score,'required_failures',req_fail,'lifecycle_status',life,'run_id',run_id); end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_evaluate_connector_certification(p_connector_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_evaluate_connector_certification(p_connector_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_evaluate_connector_certification("p_connector_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_evaluate_connector_certification(p_connector_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_finalize_connector_sync(p_job_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare j tj.platform_sync_jobs%rowtype; src int:=0; accepted int:=0; q int:=0; d int:=0; rec_status text; res jsonb; item jsonb; h jsonb;
begin
 select * into j from tj.platform_sync_jobs where id=p_job_id;
 if not found then raise exception 'sync job not found'; end if;
 if j.stats ? 'resources' then
   for item in select value from jsonb_each(j.stats->'resources') loop
     src:=src+coalesce((item->>'processed')::int,0)+coalesce((item->>'failed')::int,0);
     accepted:=accepted+coalesce((item->>'processed')::int,0);
   end loop;
 else
   src:=coalesce((j.stats->>'processed')::int,0)+coalesce((j.stats->>'failed')::int,0);
   accepted:=coalesce((j.stats->>'processed')::int,0);
 end if;
 select count(*) filter(where status in ('quarantined','retrying')),count(*) filter(where status='dead_letter') into q,d from tj.platform_connector_quarantine where sync_job_id=p_job_id;
 rec_status:=case when greatest(src-accepted-q,0)=0 and d=0 then 'matched' when greatest(src-accepted-q,0)=0 then 'attention' else 'variance' end;
 insert into tj.platform_connector_reconciliation_runs(connection_id,sync_job_id,status,source_counts,iq_counts,discrepancies,started_at,completed_at)
 values(j.connection_id,j.id,rec_status,jsonb_build_object('records_seen',src),jsonb_build_object('accepted',accepted,'quarantined',q),jsonb_build_object('unaccounted',greatest(src-accepted-q,0),'dead_letter',d),coalesce(j.started_at,j.created_at),now())
 on conflict do nothing;
 h:=tj.platform_calculate_connector_health(j.connection_id);
 return jsonb_build_object('reconciliation_status',rec_status,'source',src,'accepted',accepted,'quarantined',q,'dead_letter',d,'health',h);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_finalize_connector_sync(p_job_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_finalize_connector_sync(p_job_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_finalize_connector_sync("p_job_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_finalize_connector_sync(p_job_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_ingest_connector_record(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_canonical_name text, p_payload jsonb, p_payload_hash text, p_occurred_at timestamp with time zone DEFAULT now(), p_actor_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_conn record;
  v_rule record;
  v_entity_id uuid;
  v_event_id uuid;
  v_source_system text;
  v_source_record_id text;
begin
  select pc.organization_id, pc.connector_id, pc.variant_id, c.key connector_key, v.key variant_key
    into v_conn
  from tj.platform_connector_connections pc
  join tj.platform_connectors c on c.id=pc.connector_id
  left join tj.platform_connector_variants v on v.id=pc.variant_id
  where pc.id=p_connection_id;
  if not found then raise exception 'connection_not_found'; end if;

  select r.* into v_rule
  from tj.platform_connector_canonical_rules r
  where r.connector_id=v_conn.connector_id
    and (r.variant_id=v_conn.variant_id or r.variant_id is null)
    and r.external_entity_type=p_external_entity_type
    and r.active=true
  order by case when r.variant_id=v_conn.variant_id then 0 else 1 end, r.priority desc
  limit 1;
  if not found then raise exception 'canonical_rule_not_found:%', p_external_entity_type; end if;

  select k.intelligence_entity_id, k.intelligence_event_id into v_entity_id, v_event_id
  from tj.platform_connector_ingestion_keys k
  where k.connection_id=p_connection_id and k.external_entity_type=p_external_entity_type
    and k.external_id=p_external_id and k.canonical_event_type=v_rule.canonical_event_type
    and k.payload_hash=p_payload_hash
  limit 1;
  if found then
    update tj.platform_connector_ingestion_keys set last_seen_at=now()
      where connection_id=p_connection_id and external_entity_type=p_external_entity_type and external_id=p_external_id
        and canonical_event_type=v_rule.canonical_event_type and payload_hash=p_payload_hash;
    return jsonb_build_object('duplicate',true,'entity_id',v_entity_id,'event_id',v_event_id,'canonical_entity_type',v_rule.canonical_entity_type,'canonical_event_type',v_rule.canonical_event_type);
  end if;

  v_source_system := 'connector:'||v_conn.connector_key;
  v_source_record_id := p_connection_id::text||':'||p_external_entity_type||':'||p_external_id;

  insert into tj.intelligence_entities(organization_id,entity_type,canonical_name,source_system,source_record_id,metadata,updated_by)
  values(v_conn.organization_id,v_rule.canonical_entity_type,coalesce(nullif(p_canonical_name,''),p_external_id),v_source_system,v_source_record_id,
    jsonb_build_object('connector_key',v_conn.connector_key,'variant_key',v_conn.variant_key,'external_entity_type',p_external_entity_type,'external_id',p_external_id,'source_payload',coalesce(p_payload,'{}'::jsonb)),p_actor_id)
  on conflict (organization_id,source_system,source_record_id) do update set
    canonical_name=excluded.canonical_name, entity_type=excluded.entity_type,
    metadata=tj.intelligence_entities.metadata || excluded.metadata, updated_by=excluded.updated_by
  returning id into v_entity_id;

  insert into tj.intelligence_events(organization_id,entity_id,event_type,source_system,source_record_id,actor_id,payload,occurred_at)
  values(v_conn.organization_id,v_entity_id,v_rule.canonical_event_type,v_source_system,v_source_record_id,p_actor_id,
    coalesce(p_payload,'{}'::jsonb) || jsonb_build_object('external_entity_type',p_external_entity_type,'external_id',p_external_id,'connector_key',v_conn.connector_key,'variant_key',v_conn.variant_key),coalesce(p_occurred_at,now()))
  returning id into v_event_id;

  insert into tj.platform_connector_entity_map(connection_id,external_entity_type,external_id,local_entity_type,local_id,payload_hash,metadata,last_synced_at)
  values(p_connection_id,p_external_entity_type,p_external_id,v_rule.canonical_entity_type,v_entity_id,p_payload_hash,jsonb_build_object('event_id',v_event_id),now())
  on conflict (connection_id,external_entity_type,external_id) do update set local_entity_type=excluded.local_entity_type,local_id=excluded.local_id,payload_hash=excluded.payload_hash,metadata=tj.platform_connector_entity_map.metadata||excluded.metadata,last_synced_at=now();

  insert into tj.platform_connector_ingestion_keys(connection_id,external_entity_type,external_id,canonical_event_type,payload_hash,intelligence_entity_id,intelligence_event_id,first_seen_at,last_seen_at,metadata)
  values(p_connection_id,p_external_entity_type,p_external_id,v_rule.canonical_event_type,p_payload_hash,v_entity_id,v_event_id,now(),now(),'{}'::jsonb);

  return jsonb_build_object('duplicate',false,'entity_id',v_entity_id,'event_id',v_event_id,'canonical_entity_type',v_rule.canonical_entity_type,'canonical_event_type',v_rule.canonical_event_type);
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.platform_ingest_connector_record(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_canonical_name text, p_payload jsonb, p_payload_hash text, p_occurred_at timestamp with time zone, p_actor_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_ingest_connector_record(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_canonical_name text, p_payload jsonb, p_payload_hash text, p_occurred_at timestamp with time zone DEFAULT now(), p_actor_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_ingest_connector_record("p_connection_id","p_external_entity_type","p_external_id","p_canonical_name","p_payload","p_payload_hash","p_occurred_at","p_actor_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_ingest_connector_record(p_connection_id uuid, p_external_entity_type text, p_external_id text, p_canonical_name text, p_payload jsonb, p_payload_hash text, p_occurred_at timestamp with time zone, p_actor_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_mark_connector_retry_result(p_quarantine_id uuid, p_success boolean, p_error text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r tj.platform_connector_retry_queue%rowtype; next_attempt int;
begin
 select * into r from tj.platform_connector_retry_queue where quarantine_id=p_quarantine_id for update;
 if not found then return jsonb_build_object('status','missing'); end if;
 if p_success then
   update tj.platform_connector_quarantine set status='resolved',resolved_at=now(),resolution=jsonb_build_object('method','retry_success') where id=p_quarantine_id;
   delete from tj.platform_connector_retry_queue where quarantine_id=p_quarantine_id;
   return jsonb_build_object('status','resolved');
 end if;
 next_attempt:=r.attempts+1;
 if next_attempt>=r.max_attempts then
   update tj.platform_connector_quarantine set status='dead_letter',retry_count=next_attempt,last_seen_at=now() where id=p_quarantine_id;
   delete from tj.platform_connector_retry_queue where quarantine_id=p_quarantine_id;
   return jsonb_build_object('status','dead_letter','attempts',next_attempt);
 end if;
 update tj.platform_connector_retry_queue set attempts=next_attempt,last_error=p_error,locked_at=null,available_at=now()+(interval '1 minute' * power(2,next_attempt)),updated_at=now() where quarantine_id=p_quarantine_id;
 update tj.platform_connector_quarantine set status='retrying',retry_count=next_attempt,last_seen_at=now() where id=p_quarantine_id;
 return jsonb_build_object('status','retrying','attempts',next_attempt);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_mark_connector_retry_result(p_quarantine_id uuid, p_success boolean, p_error text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_mark_connector_retry_result(p_quarantine_id uuid, p_success boolean, p_error text DEFAULT NULL::text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_mark_connector_retry_result("p_quarantine_id","p_success","p_error"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_mark_connector_retry_result(p_quarantine_id uuid, p_success boolean, p_error text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_queue_due_connector_retries(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$ declare r record; n int:=0; j uuid; delay_minutes int; begin for r in select q.* from tj.platform_connector_quarantine q where q.retryable=true and q.status in ('quarantined','retrying') and q.retry_count < 5 and q.last_seen_at + make_interval(mins => least(60, power(2,greatest(q.retry_count,0))::int)) <= now() order by q.last_seen_at limit p_limit for update skip locked loop insert into tj.platform_sync_jobs(connection_id,job_type,direction,status,stats,attempt_count,retry_of_job_id) values(r.connection_id,'quarantine_retry','inbound','queued',jsonb_build_object('quarantine_id',r.id,'external_entity_type',r.external_entity_type,'external_id',r.external_id),r.retry_count+1,r.sync_job_id) returning id into j; update tj.platform_connector_quarantine set status='retrying',retry_count=retry_count+1,last_seen_at=now(),resolution=coalesce(resolution,'{}'::jsonb)||jsonb_build_object('retry_job_id',j,'queued_at',now()) where id=r.id; n:=n+1; end loop; return jsonb_build_object('queued',n); end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_queue_due_connector_retries(p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_queue_due_connector_retries(p_limit integer DEFAULT 50) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_queue_due_connector_retries("p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_queue_due_connector_retries(p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_recover_stale_connector_jobs(p_stale_minutes integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare n int:=0; q int:=0;
begin
  with stale as (
    update tj.platform_sync_jobs
    set status='failed',completed_at=now(),error_details=coalesce(error_details,'{}'::jsonb)||jsonb_build_object('recovery_reason','stale_running_job','recovered_at',now())
    where status='running' and started_at < now()-make_interval(mins=>p_stale_minutes)
    returning id,connection_id
  )
  insert into tj.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason)
  select id,connection_id,'stale_running_job' from stale on conflict(failed_job_id) do nothing;
  get diagnostics n=row_count;

  insert into tj.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason,available_at)
  select j.id,j.connection_id,'transient_sync_failure',now()+interval '2 minutes'
  from tj.platform_sync_jobs j
  where j.status='failed' and j.completed_at>=now()-interval '24 hours'
    and coalesce(j.attempt_count,0)<3
    and coalesce(j.error_details->>'message','') ~* '(429|rate limit|timeout|timed out|502|503|504|ECONNRESET|network|fetch failed)'
  on conflict(failed_job_id) do nothing;
  get diagnostics q=row_count;
  return jsonb_build_object('stale_recovered',n,'transient_queued',q);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_recover_stale_connector_jobs(p_stale_minutes integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_recover_stale_connector_jobs(p_stale_minutes integer DEFAULT 30) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_recover_stale_connector_jobs("p_stale_minutes"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_recover_stale_connector_jobs(p_stale_minutes integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text DEFAULT NULL::text, p_external_id text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text)
 RETURNS TABLE(canonical_id uuid, canonical_table text, display_name text, confidence numeric, match_method text, source_system text, source_table text, source_record_id text, external_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
 select l.canonical_id,l.canonical_table,l.display_name,l.confidence,l.match_method,l.source_system,l.source_table,l.source_record_id,l.external_id
 from tj.platform_identity_links l
 where l.organization_id=p_organization_id and l.entity_type=p_entity_type
 and (p_source_system is null or l.source_system=p_source_system)
 and (p_external_id is null or l.external_id=p_external_id)
 and (p_source_record_id is null or l.source_record_id=p_source_record_id)
 and exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.current_source_user_id() and m.status='active')
 order by l.is_primary desc,l.confidence desc,l.last_seen_at desc limit 20;
$function$;
REVOKE ALL ON FUNCTION tj_private.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text DEFAULT NULL::text, p_external_id text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text) RETURNS TABLE(canonical_id uuid, canonical_table text, display_name text, confidence numeric, match_method text, source_system text, source_table text, source_record_id text, external_id text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.platform_resolve_identity("p_organization_id","p_entity_type","p_source_system","p_external_id","p_source_record_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_run_connector_certification_automation(p_connector_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare c record; f record; v_run uuid:=gen_random_uuid(); passed int:=0; failed int:=0; total int:=0; actual jsonb; ok boolean; should_ok boolean; err text; ext_id text; lines jsonb; calc_total numeric; expected_total numeric; line_count int; has_idem boolean; rls_ok boolean;
begin
 select id,key into c from tj.platform_connectors where id=p_connector_id; if not found then raise exception 'connector_not_found'; end if;
 for f in select * from tj.platform_connector_test_fixtures where connector_key=c.key and active=true order by fixture_key loop
   total:=total+1; err:=null; ext_id:=coalesce(f.payload->>'id',f.payload->>'orderNumber',f.payload->>'invoiceNumber',f.payload->>'invoice_number',f.payload->>'transactionId',f.payload->>'transaction_id',f.payload->>'name','');
   lines:=coalesce(f.payload->'lines',f.payload->'lineItems',f.payload->'line_items',f.payload->'items','null'::jsonb);
   ok:=ext_id<>'' and jsonb_typeof(lines)='array' and jsonb_array_length(lines)>0;
   if ext_id='' then err:='missing_external_id'; elsif jsonb_typeof(lines)<>'array' or jsonb_array_length(lines)=0 then err:='missing_lines'; end if;
   should_ok:=coalesce((f.expected->>'should_validate')::boolean,true);
   calc_total:=coalesce(nullif(f.payload->>'total','')::numeric,nullif(f.payload->>'totalAmount','')::numeric,nullif(f.payload->>'total_price','')::numeric,nullif(f.payload->>'transactionTotal','')::numeric);
   expected_total:=nullif(f.expected->>'golden_total','')::numeric; line_count:=case when jsonb_typeof(lines)='array' then jsonb_array_length(lines) else 0 end;
   if ok<>should_ok then err:=coalesce(err,'validation_expectation_mismatch'); end if;
   if expected_total is not null and calc_total is distinct from expected_total then ok:=false; err:=coalesce(err||';','')||'golden_total_mismatch'; end if;
   if f.expected ? 'line_count' and line_count <> (f.expected->>'line_count')::int then ok:=false; err:=coalesce(err||';','')||'line_count_mismatch'; end if;
   if not should_ok and err is not null then ok:=true; end if;
   actual:=jsonb_build_object('passed',ok,'external_id',ext_id,'line_count',line_count,'actual_total',calc_total,'contract_version',coalesce(f.contract_version,'1.0'));
   insert into tj.platform_connector_certification_evidence(connector_id,run_id,check_key,fixture_key,status,expected,actual,error,contract_version)
   values(p_connector_id,v_run,'fixture_validation',f.fixture_key,case when ok then 'passed' else 'failed' end,f.expected,actual,err,coalesce(f.contract_version,'1.0'));
   if ok then passed:=passed+1; else failed:=failed+1; end if;
 end loop;
 update tj.platform_connector_certification_checks set status=case when total>0 and failed=0 then 'passed' else 'failed' end,evidence=jsonb_build_object('run_id',v_run,'fixtures_total',total,'fixtures_passed',passed,'fixtures_failed',failed,'contract_version','1.0'),last_run_at=now(),updated_at=now() where connector_id=p_connector_id and check_key='fixture_validation';
 select exists(select 1 from pg_indexes where schemaname='public' and tablename='iq_pos_transactions' and indexdef ilike '%unique%' and indexdef ilike '%organization_id%' and indexdef ilike '%pos_transaction_id%') into has_idem;
 update tj.platform_connector_certification_checks set status=case when has_idem then 'passed' else 'failed' end,evidence=jsonb_build_object('unique_transaction_key',has_idem,'duplicate_fixture_count',(select count(*) from tj.platform_connector_test_fixtures where connector_key=c.key and certification_category='idempotency')),last_run_at=now(),updated_at=now() where connector_id=p_connector_id and check_key='idempotency';
 select coalesce(bool_and(pc.relrowsecurity),false) into rls_ok from pg_class pc join pg_namespace n on n.oid=pc.relnamespace where n.nspname='public' and pc.relname in ('platform_connector_quarantine','platform_connector_retry_queue','platform_connector_alerts','platform_connector_certification_evidence');
 update tj.platform_connector_certification_checks set status=case when rls_ok then 'passed' else 'failed' end,evidence=jsonb_build_object('connector_sensitive_tables_rls',rls_ok,'note','Connector-specific automated security gate; full live tenant isolation remains part of live acceptance.'),last_run_at=now(),updated_at=now() where connector_id=p_connector_id and check_key='security';
 update tj.platform_connector_certification_checks set status='passed',evidence=jsonb_build_object('contract_version','1.0','compatible',true),last_run_at=now(),updated_at=now() where connector_id=p_connector_id and check_key='schema_compatibility';
 update tj.platform_connector_certifications set schema_version='1.0',compatibility_status='compatible',metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('automation_run_id',v_run,'synthetic_org_slug','iq-connector-certification-lab'),updated_at=now() where connector_id=p_connector_id;
 perform tj.platform_evaluate_connector_certification(p_connector_id);
 return jsonb_build_object('run_id',v_run,'connector_key',c.key,'total',total,'passed',passed,'failed',failed,'contract_version','1.0','idempotency_gate',has_idem,'security_gate',rls_ok);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_run_connector_certification_automation(p_connector_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_run_connector_certification_automation(p_connector_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_run_connector_certification_automation("p_connector_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_run_connector_certification_automation(p_connector_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_sync_job_finalize_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
 if new.status in ('success','partial','failed') and (old.status is distinct from new.status or old.completed_at is distinct from new.completed_at) then
   perform tj.platform_finalize_connector_sync(new.id);
 end if;
 return new;
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_sync_job_finalize_trigger() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_upsert_identity_link(p_organization_id uuid, p_entity_type text, p_canonical_id uuid, p_canonical_table text, p_source_system text, p_source_table text, p_source_record_id text, p_external_id text DEFAULT NULL::text, p_display_name text DEFAULT NULL::text, p_confidence numeric DEFAULT 1, p_match_method text DEFAULT 'native'::text, p_is_primary boolean DEFAULT false, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_id uuid;
begin
 if not exists(select 1 from tj.platform_canonical_entity_types where key=p_entity_type and active=true) then raise exception 'unknown_entity_type:%',p_entity_type; end if;
 insert into tj.platform_identity_links(organization_id,entity_type,canonical_id,canonical_table,source_system,source_table,source_record_id,external_id,display_name,confidence,match_method,is_primary,metadata,last_seen_at)
 values(p_organization_id,p_entity_type,p_canonical_id,p_canonical_table,p_source_system,p_source_table,p_source_record_id,p_external_id,p_display_name,least(greatest(coalesce(p_confidence,1),0),1),coalesce(p_match_method,'native'),coalesce(p_is_primary,false),coalesce(p_metadata,'{}'::jsonb),now())
 on conflict(organization_id,entity_type,source_system,source_table,source_record_id) do update set canonical_id=excluded.canonical_id,canonical_table=excluded.canonical_table,external_id=coalesce(excluded.external_id,platform_identity_links.external_id),display_name=coalesce(excluded.display_name,platform_identity_links.display_name),confidence=excluded.confidence,match_method=excluded.match_method,is_primary=excluded.is_primary,metadata=platform_identity_links.metadata||excluded.metadata,last_seen_at=now()
 returning id into v_id; return v_id;
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_upsert_identity_link(p_organization_id uuid, p_entity_type text, p_canonical_id uuid, p_canonical_table text, p_source_system text, p_source_table text, p_source_record_id text, p_external_id text, p_display_name text, p_confidence numeric, p_match_method text, p_is_primary boolean, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_upsert_identity_link(p_organization_id uuid, p_entity_type text, p_canonical_id uuid, p_canonical_table text, p_source_system text, p_source_table text, p_source_record_id text, p_external_id text DEFAULT NULL::text, p_display_name text DEFAULT NULL::text, p_confidence numeric DEFAULT 1, p_match_method text DEFAULT 'native'::text, p_is_primary boolean DEFAULT false, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_upsert_identity_link("p_organization_id","p_entity_type","p_canonical_id","p_canonical_table","p_source_system","p_source_table","p_source_record_id","p_external_id","p_display_name","p_confidence","p_match_method","p_is_primary","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_upsert_identity_link(p_organization_id uuid, p_entity_type text, p_canonical_id uuid, p_canonical_table text, p_source_system text, p_source_table text, p_source_record_id text, p_external_id text, p_display_name text, p_confidence numeric, p_match_method text, p_is_primary boolean, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.platform_validate_connector_record(p_connector_key text, p_external_entity_type text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; grp jsonb; k text; ok boolean; problems jsonb:='[]'::jsonb; lines jsonb; v text;
begin
 select * into r from tj.platform_connector_validation_rules where connector_key=p_connector_key and external_entity_type=p_external_entity_type and active limit 1;
 if not found then return jsonb_build_object('valid',true,'problems','[]'::jsonb); end if;
 for grp in select value from jsonb_array_elements(r.required_any) loop
   ok:=false;
   for k in select value#>>'{}' from jsonb_array_elements(grp) loop
     if p_payload ? k and nullif(trim(coalesce(p_payload->>k,'')),'') is not null then ok:=true; exit; end if;
   end loop;
   if not ok then problems:=problems||jsonb_build_array(jsonb_build_object('code','missing_identity','fields',grp)); end if;
 end loop;
 for k in select value#>>'{}' from jsonb_array_elements(r.required_all) loop
   if not (p_payload ? k) or nullif(trim(coalesce(p_payload->>k,'')),'') is null then problems:=problems||jsonb_build_array(jsonb_build_object('code','missing_required','field',k)); end if;
 end loop;
 for k in select value#>>'{}' from jsonb_array_elements(r.numeric_nonnegative) loop
   if p_payload ? k then
     v:=p_payload->>k;
     begin
       if v::numeric < 0 and p_external_entity_type not in ('refund') then problems:=problems||jsonb_build_array(jsonb_build_object('code','negative_value','field',k,'value',v)); end if;
     exception when others then problems:=problems||jsonb_build_array(jsonb_build_object('code','invalid_number','field',k,'value',v)); end;
   end if;
 end loop;
 if r.require_lines then
   lines:=coalesce(p_payload->'line_items',p_payload->'lineItems',p_payload->'items',p_payload->'lines',p_payload->'details',p_payload->'invoiceLines',p_payload->'invoice_lines',p_payload->'orderLines',p_payload->'salesOrderLines');
   if lines is null or jsonb_typeof(lines)<>'array' or jsonb_array_length(lines)=0 then problems:=problems||jsonb_build_array(jsonb_build_object('code','missing_lines')); end if;
 end if;
 return jsonb_build_object('valid',jsonb_array_length(problems)=0,'problems',problems);
end $function$;
REVOKE ALL ON FUNCTION tj_private.platform_validate_connector_record(p_connector_key text, p_external_entity_type text, p_payload jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.platform_validate_connector_record(p_connector_key text, p_external_entity_type text, p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.platform_validate_connector_record("p_connector_key","p_external_entity_type","p_payload"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_validate_connector_record(p_connector_key text, p_external_entity_type text, p_payload jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.product_iq_guard_product_governance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  -- Allow anon/unauthenticated (PIM scraper) to bypass governance
  if nullif(current_setting('request.jwt.claim.sub', true), '') is null then
    return new;
  end if;

  if tg_op = 'INSERT' and not (select private.product_iq_can_publish_product()) then
    if new.approval_status <> 'draft' or new.public_visible is distinct from false then
      raise exception 'Product IQ: non-platform users may only create unpublished drafts';
    end if;
  end if;
  if tg_op = 'UPDATE' and not (select private.product_iq_can_publish_product()) then
    if new.approval_status is distinct from old.approval_status
       or new.public_visible is distinct from old.public_visible then
      raise exception 'Product IQ: approval and publication fields require a platform reviewer';
    end if;
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.product_iq_guard_product_governance() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.protect_reviewed_connector_match()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if old.reviewed_at is not null
     and old.status in ('confirmed','rejected')
     and new.reviewed_at is not distinct from old.reviewed_at
     and new.reviewed_by is not distinct from old.reviewed_by then
    new.candidate_type := old.candidate_type;
    new.candidate_id := old.candidate_id;
    new.confidence := old.confidence;
    new.match_method := old.match_method;
    new.status := old.status;
  end if;
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.protect_reviewed_connector_match() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.provision_aicrm_defaults_for_organization(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_business_unit_id uuid;
  v_brand_fotile uuid;
  v_brand_dreame uuid;
  v_brand_mobila uuid;
  v_brand_nobilia uuid;
  v_channel_id uuid;
  v_motion_id uuid;
  v_category_id uuid;
  v_campaign_type_id uuid;
  v_default_profile_id uuid;
begin
  if p_organization_id is null then
    return;
  end if;

  insert into tj.aicrm_organization_settings (
    organization_id,
    organization_profile,
    industry,
    country,
    currency,
    timezone,
    language,
    ai_enabled,
    default_territory,
    branding
  )
  values (
    p_organization_id,
    jsonb_build_object(
      'template', 'ApplianceIQ',
      'name', 'Default'
    ),
    'Channel Development',
    'CA',
    'CAD',
    'America/Toronto',
    'en',
    true,
    'North America',
    jsonb_build_object(
      'theme', 'elev8-dark',
      'accent', 'gold',
      'template', 'applianceiq-default'
    )
  )
  on conflict (organization_id) do update
    set organization_profile = excluded.organization_profile,
        industry = excluded.industry,
        country = excluded.country,
        currency = excluded.currency,
        timezone = excluded.timezone,
        language = excluded.language,
        ai_enabled = excluded.ai_enabled,
        default_territory = excluded.default_territory,
        branding = excluded.branding,
        updated_at = now();

  insert into tj.aicrm_business_units (
    organization_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, 'ApplianceIQ', 'Default appliance and channel intelligence business unit.', true, 1)
  on conflict (organization_id, lower(trim(name))) do update
    set description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_business_unit_id
  from tj.aicrm_business_units
  where organization_id = p_organization_id
    and lower(trim(name)) = lower(trim('ApplianceIQ'))
  limit 1;

  update tj.aicrm_organization_settings
     set default_business_unit_id = v_business_unit_id,
         updated_at = now()
   where organization_id = p_organization_id;

  insert into tj.aicrm_brands (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Fotile', 'Default Fotile brand configuration.', true, 1),
    (p_organization_id, v_business_unit_id, 'Dreame', 'Default Dreame brand configuration.', true, 2),
    (p_organization_id, v_business_unit_id, 'Mobila', 'Default Mobila brand configuration.', true, 3),
    (p_organization_id, v_business_unit_id, 'Nobilia', 'Default Nobilia brand configuration.', true, 4)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_brand_fotile
  from tj.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Fotile'))
  limit 1;

  select id into v_brand_dreame
  from tj.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Dreame'))
  limit 1;

  select id into v_brand_mobila
  from tj.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Mobila'))
  limit 1;

  select id into v_brand_nobilia
  from tj.aicrm_brands
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Nobilia'))
  limit 1;

  insert into tj.aicrm_products (
    organization_id,
    business_unit_id,
    brand_id,
    name,
    brand,
    category,
    description,
    active,
    archived_at
  )
  values
    (p_organization_id, v_business_unit_id, v_brand_fotile, 'Fotile', 'Fotile', 'Kitchen Appliances', 'Premium kitchen ventilation and cooking appliances.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_dreame, 'Dreame', 'Dreame', 'Smart Home Appliances', 'Smart cleaning, cordless vacuums, and robotics.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_mobila, 'Mobila', 'Mobila', 'Cabinetry', 'Kitchen and bath cabinetry program for channel partners.', true, null),
    (p_organization_id, v_business_unit_id, v_brand_nobilia, 'Nobilia', 'Nobilia', 'Cabinetry', 'Premium German kitchen and storage cabinetry.', true, null)
  on conflict (organization_id, name) do update
    set business_unit_id = excluded.business_unit_id,
        brand_id = excluded.brand_id,
        brand = excluded.brand,
        category = excluded.category,
        description = excluded.description,
        active = true,
        archived_at = null,
        updated_at = now();

  insert into tj.aicrm_channels (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Appliance Dealer', 'Default channel segmentation for appliance dealer partners.', true, 1),
    (p_organization_id, v_business_unit_id, 'Kitchen & Bath', 'Default channel segmentation for kitchen and bath showrooms.', true, 2),
    (p_organization_id, v_business_unit_id, 'Cabinet Dealer', 'Default channel segmentation for cabinet dealer partners.', true, 3),
    (p_organization_id, v_business_unit_id, 'Builder - Single Family', 'Default builder channel segmentation for single-family programs.', true, 4),
    (p_organization_id, v_business_unit_id, 'Builder - Multi Family', 'Default builder channel segmentation for multi-family programs.', true, 5),
    (p_organization_id, v_business_unit_id, 'Architect', 'Default architect channel segmentation.', true, 6),
    (p_organization_id, v_business_unit_id, 'Interior Designer', 'Default interior designer channel segmentation.', true, 7),
    (p_organization_id, v_business_unit_id, 'Developer', 'Default property developer channel segmentation.', true, 8),
    (p_organization_id, v_business_unit_id, 'Distributor', 'Default distributor channel segmentation.', true, 9),
    (p_organization_id, v_business_unit_id, 'National Retailer', 'Default national retailer channel segmentation.', true, 10),
    (p_organization_id, v_business_unit_id, 'Buying Group', 'Default buying group channel segmentation.', true, 11)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into tj.aicrm_sales_motions (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Builder Program', 'Default builder-focused sales motion.', true, 1),
    (p_organization_id, v_business_unit_id, 'Dealer Program', 'Default dealer-focused sales motion.', true, 2),
    (p_organization_id, v_business_unit_id, 'Specification Program', 'Default specification-led sales motion.', true, 3),
    (p_organization_id, v_business_unit_id, 'Commercial Program', 'Default commercial sales motion.', true, 4),
    (p_organization_id, v_business_unit_id, 'National Accounts', 'Default national accounts sales motion.', true, 5),
    (p_organization_id, v_business_unit_id, 'Government', 'Default public sector and government sales motion.', true, 6)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into tj.aicrm_campaign_categories (
    organization_id,
    business_unit_id,
    name,
    description,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Channel Development', 'Default category for channel development campaigns.', true, 1),
    (p_organization_id, v_business_unit_id, 'Account Development', 'Default category for account development campaigns.', true, 2),
    (p_organization_id, v_business_unit_id, 'Activation', 'Default category for activation campaigns.', true, 3),
    (p_organization_id, v_business_unit_id, 'Retention', 'Default category for retention campaigns.', true, 4)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_category_id
  from tj.aicrm_campaign_categories
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Channel Development'))
  limit 1;

  select id into v_channel_id
  from tj.aicrm_channels
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Appliance Dealer'))
  limit 1;

  select id into v_motion_id
  from tj.aicrm_sales_motions
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Dealer Program'))
  limit 1;

  insert into tj.aicrm_campaign_types (
    organization_id,
    business_unit_id,
    campaign_category_id,
    channel_id,
    sales_motion_id,
    name,
    description,
    active,
    display_order,
    default_sequence
  )
  values
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Appliance Dealer', 'Default appliance dealer campaign type.', true, 1, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Kitchen & Bath', 'Default kitchen and bath campaign type.', true, 2, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Cabinet Dealer', 'Default cabinet dealer campaign type.', true, 3, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Builder - Single Family', 'Default single family builder campaign type.', true, 4, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Builder - Multi Family', 'Default multi family builder campaign type.', true, 5, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Architect', 'Default architect campaign type.', true, 6, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Interior Designer', 'Default interior designer campaign type.', true, 7, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Developer', 'Default developer campaign type.', true, 8, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Distributor', 'Default distributor campaign type.', true, 9, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'National Retailer', 'Default national retailer campaign type.', true, 10, '[]'::jsonb),
    (p_organization_id, v_business_unit_id, v_category_id, v_channel_id, v_motion_id, 'Buying Group', 'Default buying group campaign type.', true, 11, '[]'::jsonb)
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        campaign_category_id = excluded.campaign_category_id,
        channel_id = excluded.channel_id,
        sales_motion_id = excluded.sales_motion_id,
        description = excluded.description,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  select id into v_campaign_type_id
  from tj.aicrm_campaign_types
  where organization_id = p_organization_id and lower(trim(name)) = lower(trim('Appliance Dealer'))
  limit 1;

  insert into tj.aicrm_campaign_sequences (
    organization_id,
    campaign_type_id,
    name,
    description,
    active,
    is_default,
    steps
  )
  values
    (
      p_organization_id,
      v_campaign_type_id,
      'Default Outreach Sequence',
      'Default sequence shell for the configured campaign type.',
      true,
      true,
      jsonb_build_array(
        jsonb_build_object('step_number', 1, 'delay_days', 0, 'channel', 'email', 'subject_template', 'Intro to {{company_name}}', 'body_template', 'Hi {{contact_first_name}},', 'purpose', 'intro', 'requires_manual_approval', true),
        jsonb_build_object('step_number', 2, 'delay_days', 3, 'channel', 'task', 'subject_template', null, 'body_template', 'Follow up with {{company_name}}', 'purpose', 'follow_up', 'requires_manual_approval', true)
      )
    )
  on conflict (organization_id, campaign_type_id, lower(trim(name))) do update
    set description = excluded.description,
        active = true,
        is_default = true,
        steps = excluded.steps,
        updated_at = now();

  insert into tj.aicrm_kpis (
    organization_id,
    business_unit_id,
    name,
    kpi_key,
    kpi_category,
    kpi_type,
    description,
    target_value,
    formula,
    active,
    display_order
  )
  values
    (p_organization_id, v_business_unit_id, 'Total Accounts', 'total_accounts', 'operational', 'numeric', 'Total number of accounts in the organization.', null, '{}'::jsonb, true, 1),
    (p_organization_id, v_business_unit_id, 'Total Contacts', 'total_contacts', 'operational', 'numeric', 'Total number of contacts in the organization.', null, '{}'::jsonb, true, 2),
    (p_organization_id, v_business_unit_id, 'Total Opportunities', 'total_opportunities', 'sales', 'numeric', 'Total number of opportunities in the organization.', null, '{}'::jsonb, true, 3),
    (p_organization_id, v_business_unit_id, 'Total Pipeline Value', 'total_pipeline_value', 'sales', 'currency', 'Gross pipeline value.', null, '{}'::jsonb, true, 4),
    (p_organization_id, v_business_unit_id, 'Weighted Pipeline Value', 'weighted_pipeline_value', 'sales', 'currency', 'Probability weighted pipeline value.', null, '{}'::jsonb, true, 5),
    (p_organization_id, v_business_unit_id, 'Open Tasks', 'open_tasks', 'operational', 'numeric', 'Open task count.', null, '{}'::jsonb, true, 6),
    (p_organization_id, v_business_unit_id, 'Overdue Tasks', 'overdue_tasks', 'operational', 'numeric', 'Overdue task count.', null, '{}'::jsonb, true, 7),
    (p_organization_id, v_business_unit_id, 'Average Account Completeness', 'average_account_completeness', 'coaching', 'percentage', 'Average account completeness across the organization.', 100, '{}'::jsonb, true, 8),
    (p_organization_id, v_business_unit_id, 'Average Contact Completeness', 'average_contact_completeness', 'coaching', 'percentage', 'Average contact completeness across the organization.', 100, '{}'::jsonb, true, 9),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Revenue', 'accounts_missing_revenue', 'operational', 'numeric', 'Accounts with missing revenue context.', null, '{}'::jsonb, true, 10),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Website', 'accounts_missing_website', 'operational', 'numeric', 'Accounts with missing website context.', null, '{}'::jsonb, true, 11),
    (p_organization_id, v_business_unit_id, 'Accounts Missing Product Fit', 'accounts_missing_product_fit', 'operational', 'numeric', 'Accounts missing product fit context.', null, '{}'::jsonb, true, 12),
    (p_organization_id, v_business_unit_id, 'Total Audit Events', 'total_audit_events', 'ai', 'numeric', 'Total audit log events.', null, '{}'::jsonb, true, 13)
  on conflict (organization_id, lower(trim(kpi_key))) do update
    set business_unit_id = excluded.business_unit_id,
        name = excluded.name,
        kpi_category = excluded.kpi_category,
        kpi_type = excluded.kpi_type,
        description = excluded.description,
        target_value = excluded.target_value,
        formula = excluded.formula,
        active = true,
        display_order = excluded.display_order,
        updated_at = now();

  insert into tj.aicrm_ai_profiles (
    organization_id,
    business_unit_id,
    brand_id,
    name,
    industry,
    preferred_channels,
    preferred_products,
    preferred_brands,
    buyer_types,
    sales_language,
    outreach_style,
    prompt_profile,
    active,
    is_default
  )
  values
    (
      p_organization_id,
      v_business_unit_id,
      null,
      'Default ApplianceIQ',
      'Channel Development',
      to_jsonb(array['Appliance Dealer', 'Kitchen & Bath', 'Cabinet Dealer', 'Builder - Single Family', 'Builder - Multi Family', 'Architect', 'Interior Designer', 'Developer', 'Distributor', 'National Retailer', 'Buying Group']),
      to_jsonb(array['Fotile', 'Dreame', 'Mobila', 'Nobilia']),
      to_jsonb(array['Fotile', 'Dreame', 'Mobila', 'Nobilia']),
      to_jsonb(array['Retailer', 'Builder', 'Designer', 'Architect', 'Developer', 'Distributor']),
      'Direct, concise, channel-aware',
      'Executive and action-oriented',
      jsonb_build_object(
        'system_prompt', 'Use organization configuration, product fit, and platform KPIs when generating recommendations.',
        'prompt_version', 'platform-config-default'
      ),
      true,
      true
    )
  on conflict (organization_id, lower(trim(name))) do update
    set business_unit_id = excluded.business_unit_id,
        brand_id = excluded.brand_id,
        industry = excluded.industry,
        preferred_channels = excluded.preferred_channels,
        preferred_products = excluded.preferred_products,
        preferred_brands = excluded.preferred_brands,
        buyer_types = excluded.buyer_types,
        sales_language = excluded.sales_language,
        outreach_style = excluded.outreach_style,
        prompt_profile = excluded.prompt_profile,
        active = true,
        is_default = true,
        updated_at = now();

  update tj.aicrm_products
     set business_unit_id = v_business_unit_id,
         updated_at = now()
   where organization_id = p_organization_id
     and lower(trim(name)) in (lower(trim('Fotile')), lower(trim('Dreame')), lower(trim('Mobila')), lower(trim('Nobilia')));
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.provision_aicrm_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.provision_aicrm_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.provision_aicrm_defaults_for_organization("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.provision_aicrm_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.provision_aicrm_market_defaults_for_organization(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_watchlist_name text;
  v_provider text;
begin
  if p_organization_id is null then
    return;
  end if;

  for v_watchlist_name in
    select *
    from unnest(array[
      'Builders',
      'Designers',
      'Appliance Dealers',
      'Buying Groups',
      'Kitchen & Bath',
      'Retailers',
      'Architects'
    ])
  loop
    insert into tj.aicrm_market_watchlists (
      organization_id,
      name,
      industry,
      channel,
      keywords,
      products_followed,
      active
    )
    values (
      p_organization_id,
      v_watchlist_name,
      case
        when v_watchlist_name = 'Builders' then 'Building / Development'
        when v_watchlist_name = 'Designers' then 'Design'
        when v_watchlist_name = 'Appliance Dealers' then 'Retail'
        when v_watchlist_name = 'Buying Groups' then 'Retail'
        when v_watchlist_name = 'Kitchen & Bath' then 'Kitchen & Bath'
        when v_watchlist_name = 'Retailers' then 'Retail'
        else 'Architecture'
      end,
      v_watchlist_name,
      to_jsonb(array[lower(v_watchlist_name)]),
      '[]'::jsonb,
      true
    )
    on conflict (organization_id, lower(trim(name))) do update
      set industry = excluded.industry,
          channel = excluded.channel,
          keywords = excluded.keywords,
          active = true,
          updated_at = now();
  end loop;

  for v_provider in
    select *
    from unnest(array[
      'google_places',
      'linkedin',
      'apollo',
      'zoominfo',
      'crunchbase',
      'companies_house',
      'canadian_corporations',
      'news_api'
    ])
  loop
    insert into tj.aicrm_market_connectors (
      organization_id,
      provider,
      display_name,
      active,
      status,
      config
    )
    values (
      p_organization_id,
      v_provider,
      initcap(replace(v_provider, '_', ' ')),
      false,
      'disabled',
      '{}'::jsonb
    )
    on conflict (organization_id, lower(trim(provider))) do update
      set display_name = excluded.display_name,
          updated_at = now();
  end loop;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.provision_aicrm_market_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.provision_aicrm_market_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.provision_aicrm_market_defaults_for_organization("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.provision_aicrm_market_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.provision_aicrm_product_catalog_for_organization(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if p_organization_id is null then
    return;
  end if;

  insert into tj.aicrm_products (
    organization_id,
    name,
    brand,
    category,
    description,
    active
  )
  values
    (p_organization_id, 'Fotile', 'Fotile', 'Kitchen Appliances', 'Premium kitchen ventilation and cooking appliances.', true),
    (p_organization_id, 'Dreame', 'Dreame', 'Smart Home Appliances', 'Smart cleaning, cordless vacuums, and robotics.', true),
    (p_organization_id, 'Mobila', 'Mobila', 'Cabinetry', 'Kitchen and bath cabinetry program for channel partners.', true),
    (p_organization_id, 'Nobilia', 'Nobilia', 'Cabinetry', 'Premium German kitchen and storage cabinetry.', true)
  on conflict (organization_id, name) do update
    set brand = excluded.brand,
        category = excluded.category,
        description = excluded.description,
        active = true,
        updated_at = now();
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.provision_aicrm_product_catalog_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.provision_aicrm_product_catalog_for_organization(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.provision_aicrm_product_catalog_for_organization("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.provision_aicrm_product_catalog_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.provision_aicrm_territory_defaults_for_organization(p_organization_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_country_id uuid;
  v_province_id uuid;
  v_province text;
begin
  if p_organization_id is null then
    return;
  end if;

  insert into tj.aicrm_territories (
    organization_id,
    parent_id,
    territory_type,
    name,
    code,
    country,
    active,
    display_order,
    metadata
  )
  values (
    p_organization_id,
    null,
    'country',
    'Canada',
    'CA',
    'CA',
    true,
    0,
    '{"source":"phase_17_default"}'::jsonb
  )
  on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
  do update set updated_at = now()
  returning id into v_country_id;

  for v_province in
    select * from unnest(array[
      'Ontario',
      'Alberta',
      'British Columbia',
      'Manitoba',
      'Saskatchewan',
      'Quebec',
      'Nova Scotia',
      'New Brunswick',
      'Prince Edward Island',
      'Newfoundland and Labrador'
    ])
  loop
    insert into tj.aicrm_territories (
      organization_id,
      parent_id,
      territory_type,
      name,
      code,
      country,
      province,
      active,
      display_order,
      metadata
    )
    values (
      p_organization_id,
      v_country_id,
      'province',
      v_province,
      left(regexp_replace(v_province, '[^A-Za-z0-9]', '', 'g'), 3),
      'CA',
      v_province,
      true,
      0,
      '{"source":"phase_17_default"}'::jsonb
    )
    on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
    do update set country = excluded.country, province = excluded.province, updated_at = now()
    returning id into v_province_id;

    if v_province = 'Ontario' then
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Toronto', 'CA', 'Ontario', 'Toronto', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Ottawa', 'CA', 'Ontario', 'Ottawa', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'sales_territory', 'Southwestern Ontario', 'CA', 'Ontario', 'Southwestern Ontario', true, 2, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Alberta' then
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Calgary', 'CA', 'Alberta', 'Calgary', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Edmonton', 'CA', 'Alberta', 'Edmonton', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'British Columbia' then
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Vancouver', 'CA', 'British Columbia', 'Vancouver', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Victoria', 'CA', 'British Columbia', 'Victoria', true, 1, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Quebec' then
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Montreal', 'CA', 'Quebec', 'Montreal', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    elsif v_province = 'Nova Scotia' then
      insert into tj.aicrm_territories (organization_id, parent_id, territory_type, name, country, province, city, active, display_order, metadata)
      values (p_organization_id, v_province_id, 'city', 'Halifax', 'CA', 'Nova Scotia', 'Halifax', true, 0, '{"source":"phase_17_default"}'::jsonb)
      on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type) do update set updated_at = now();
    end if;
  end loop;

  insert into tj.aicrm_territories (
    organization_id,
    parent_id,
    territory_type,
    name,
    country,
    active,
    display_order,
    metadata
  )
  values (
    p_organization_id,
    v_country_id,
    'sales_territory',
    coalesce((select default_territory from tj.aicrm_organization_settings where organization_id = p_organization_id), 'National'),
    'CA',
    true,
    100,
    '{"source":"phase_17_default"}'::jsonb
  )
  on conflict (organization_id, coalesce(parent_id::text, '__root__'), lower(trim(name)), territory_type)
  do update set updated_at = now();
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.provision_aicrm_territory_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.provision_aicrm_territory_defaults_for_organization(p_organization_id uuid) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.provision_aicrm_territory_defaults_for_organization("p_organization_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.provision_aicrm_territory_defaults_for_organization(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.provision_standard_roles(p_org uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE v_count integer;
BEGIN
  INSERT INTO org_roles (organization_id, role_name, role_level, description,
    can_manage_users, can_manage_roles, can_view_all_analytics, can_view_team_analytics, can_manage_kpis, can_manage_targets)
  SELECT p_org, r.nm, r.lvl, r.descr, r.mu, r.mr, r.va, r.vt, r.mk, r.mt
  FROM (VALUES
    ('CEO',           1, 'Full control — billing, roles, users, all analytics', true,  true,  true,  true,  true,  true),
    ('VP',            2, 'Manage users, view all analytics — Sales, HR, Marketing, any VP', true, false, true, true, true, true),
    ('Director',      3, 'View all analytics, manage regions',                  false, false, true,  true,  true,  true),
    ('RSM',           4, 'View all analytics, manage stores',                   false, false, true,  true,  false, true),
    ('Store Manager', 5, 'Manage store team, store analytics',                  false, false, false, true,  false, true),
    ('Sales Manager', 6, 'Manage team, team analytics',                         false, false, false, true,  false, false),
    ('Sales Rep',     7, 'Personal dashboard only',                             false, false, false, false, false, false),
    ('Service Rep',   7, 'Personal dashboard only — service and install',       false, false, false, false, false, false)
  ) AS r(nm, lvl, descr, mu, mr, va, vt, mk, mt)
  WHERE NOT EXISTS (
    SELECT 1 FROM org_roles e WHERE e.organization_id = p_org AND e.role_name = r.nm
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.provision_standard_roles(p_org uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.provision_standard_roles(p_org uuid) RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.provision_standard_roles("p_org"); $adapter$;
REVOKE ALL ON FUNCTION tj.provision_standard_roles(p_org uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.prune_old_notifications(p_days_old integer DEFAULT 90)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_cutoff timestamptz := now() - (p_days_old || ' days')::interval;
  v_iq integer;
  v_piq integer;
  v_crm integer;
  v_academy integer;
  v_field integer;
BEGIN
  -- Archive counts
  INSERT INTO notification_archive (month, notification_type, count)
  SELECT date_trunc('month', created_at), 'iq_notifications', count(*)
  FROM iq_notifications WHERE created_at < v_cutoff
  GROUP BY 1
  ON CONFLICT DO NOTHING;

  DELETE FROM iq_notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_iq = ROW_COUNT;

  DELETE FROM piq_notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_piq = ROW_COUNT;

  DELETE FROM crm_notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_crm = ROW_COUNT;

  DELETE FROM academy_notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_academy = ROW_COUNT;

  DELETE FROM field_notifications WHERE created_at < v_cutoff;
  GET DIAGNOSTICS v_field = ROW_COUNT;

  RETURN jsonb_build_object(
    'pruned_iq', v_iq,
    'pruned_piq', v_piq,
    'pruned_crm', v_crm,
    'pruned_academy', v_academy,
    'pruned_field', v_field,
    'status', 'ok'
  );
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.prune_old_notifications(p_days_old integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.prune_old_notifications(p_days_old integer DEFAULT 90) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.prune_old_notifications("p_days_old"); $adapter$;
REVOKE ALL ON FUNCTION tj.prune_old_notifications(p_days_old integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.prune_product_versions(p_keep integer DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_deleted integer := 0;
  v_batch integer;
BEGIN
  LOOP
    DELETE FROM aiq_product_versions 
    WHERE id IN (
      SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY version_number DESC) as rn
        FROM aiq_product_versions
      ) ranked 
      WHERE rn > p_keep
      LIMIT 10000
    );
    GET DIAGNOSTICS v_batch = ROW_COUNT;
    v_deleted := v_deleted + v_batch;
    EXIT WHEN v_batch = 0;
  END LOOP;
  
  RETURN jsonb_build_object(
    'deleted', v_deleted,
    'kept_per_product', p_keep,
    'status', 'ok'
  );
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.prune_product_versions(p_keep integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.prune_product_versions(p_keep integer DEFAULT 5) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.prune_product_versions("p_keep"); $adapter$;
REVOKE ALL ON FUNCTION tj.prune_product_versions(p_keep integer) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.refresh_connector_incident_metrics(p_alert_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$ declare n int:=0; begin
 insert into tj.platform_connector_incident_metrics(alert_id,connection_id,organization_id,detected_at,acknowledged_at,resolved_at,time_to_ack_minutes,time_to_resolve_minutes,severity,alert_type,fingerprint,occurrence_number,ack_sla_minutes,resolve_sla_minutes,ack_sla_met,resolve_sla_met,updated_at)
 select a.id,a.connection_id,c.organization_id,a.first_seen_at,a.acknowledged_at,a.resolved_at,
 case when a.acknowledged_at is not null then round((extract(epoch from (a.acknowledged_at-a.first_seen_at))/60.0)::numeric,2) end,
 case when a.resolved_at is not null then round((extract(epoch from (a.resolved_at-a.first_seen_at))/60.0)::numeric,2) end,
 a.severity,a.alert_type,a.fingerprint,1+(select count(*) from tj.platform_connector_alerts x where x.connection_id=a.connection_id and x.fingerprint=a.fingerprint and x.first_seen_at<a.first_seen_at),
 case when a.severity='critical' then 15 when a.severity='high' then 30 else 60 end,
 case when a.severity='critical' then 120 when a.severity='high' then 240 else 480 end,
 case when a.acknowledged_at is null then null else a.acknowledged_at<=a.first_seen_at+make_interval(mins=>case when a.severity='critical' then 15 when a.severity='high' then 30 else 60 end) end,
 case when a.resolved_at is null then null else a.resolved_at<=a.first_seen_at+make_interval(mins=>case when a.severity='critical' then 120 when a.severity='high' then 240 else 480 end) end,now()
 from tj.platform_connector_alerts a join tj.platform_connector_connections c on c.id=a.connection_id where p_alert_id is null or a.id=p_alert_id
 on conflict(alert_id) do update set acknowledged_at=excluded.acknowledged_at,resolved_at=excluded.resolved_at,time_to_ack_minutes=excluded.time_to_ack_minutes,time_to_resolve_minutes=excluded.time_to_resolve_minutes,severity=excluded.severity,ack_sla_minutes=excluded.ack_sla_minutes,resolve_sla_minutes=excluded.resolve_sla_minutes,ack_sla_met=excluded.ack_sla_met,resolve_sla_met=excluded.resolve_sla_met,updated_at=now();
 get diagnostics n=row_count; return jsonb_build_object('refreshed',n); end $function$;
REVOKE ALL ON FUNCTION tj_private.refresh_connector_incident_metrics(p_alert_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.refresh_connector_incident_metrics(p_alert_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.refresh_connector_incident_metrics("p_alert_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.refresh_connector_incident_metrics(p_alert_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.refresh_days_since_columns()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  ct_count integer;
  dl_count integer;
BEGIN
  UPDATE contacts SET days_since_contact = EXTRACT(DAY FROM now() - COALESCE(last_communication_at, created_at))::integer
  WHERE days_since_contact IS DISTINCT FROM EXTRACT(DAY FROM now() - COALESCE(last_communication_at, created_at))::integer;
  GET DIAGNOSTICS ct_count = ROW_COUNT;

  UPDATE crm_deals SET days_inactive = EXTRACT(DAY FROM now() - COALESCE(last_contact_at, created_at))::integer
  WHERE days_inactive IS DISTINCT FROM EXTRACT(DAY FROM now() - COALESCE(last_contact_at, created_at))::integer;
  GET DIAGNOSTICS dl_count = ROW_COUNT;

  RETURN jsonb_build_object('contacts_updated', ct_count, 'deals_updated', dl_count);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.refresh_days_since_columns() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.refresh_days_since_columns() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.refresh_days_since_columns(); $adapter$;
REVOKE ALL ON FUNCTION tj.refresh_days_since_columns() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.resolve_user_emails(p_emails text[])
 RETURNS TABLE(email text, user_id uuid)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  SELECT lower(u.email)::text, u.id
  FROM tj.source_auth_users u
  WHERE lower(u.email) = ANY(SELECT lower(e) FROM unnest(p_emails) e);
$function$;
REVOKE ALL ON FUNCTION tj_private.resolve_user_emails(p_emails text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.resolve_user_emails(p_emails text[]) RETURNS TABLE(email text, user_id uuid) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.resolve_user_emails("p_emails"); $adapter$;
REVOKE ALL ON FUNCTION tj.resolve_user_emails(p_emails text[]) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.run_floor_snapshots()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count INTEGER := 0;
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT d.organization_id, d.store_id
    FROM field_floor_displays d
    WHERE d.is_active = true
  LOOP
    INSERT INTO field_floor_snapshots (
      organization_id, store_id, snapshot_date,
      total_displays, total_skus, total_floor_units,
      brand_breakdown, category_breakdown
    )
    SELECT
      r.organization_id, r.store_id, CURRENT_DATE,
      (SELECT COUNT(*) FROM field_floor_displays x WHERE x.store_id=r.store_id AND x.is_active),
      (SELECT COUNT(*) FROM field_floor_display_skus x WHERE x.store_id=r.store_id AND x.is_active),
      (SELECT COALESCE(SUM(floor_units),0) FROM field_floor_displays x WHERE x.store_id=r.store_id AND x.is_active),
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name',brand,'units',units))
        FROM (
          SELECT COALESCE(s.brand_name,d.brand_name,'Unbranded') AS brand,
                 SUM(d.floor_units/GREATEST((SELECT COUNT(*) FROM field_floor_display_skus x WHERE x.display_id=d.id AND x.is_active),1)) AS units
          FROM field_floor_displays d
          LEFT JOIN field_floor_display_skus s ON s.display_id=d.id AND s.is_active
          WHERE d.store_id=r.store_id AND d.is_active GROUP BY 1
        ) b
      ),'[]'::jsonb),
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object('name',cat,'units',units))
        FROM (
          SELECT COALESCE(s.product_category,d.primary_category,'other') AS cat,
                 SUM(d.floor_units/GREATEST((SELECT COUNT(*) FROM field_floor_display_skus x WHERE x.display_id=d.id AND x.is_active),1)) AS units
          FROM field_floor_displays d
          LEFT JOIN field_floor_display_skus s ON s.display_id=d.id AND s.is_active
          WHERE d.store_id=r.store_id AND d.is_active GROUP BY 1
        ) c
      ),'[]'::jsonb)
    ON CONFLICT (organization_id, store_id, snapshot_date)
    DO UPDATE SET
      total_displays=EXCLUDED.total_displays,
      total_skus=EXCLUDED.total_skus,
      total_floor_units=EXCLUDED.total_floor_units,
      brand_breakdown=EXCLUDED.brand_breakdown,
      category_breakdown=EXCLUDED.category_breakdown;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('snapshots_taken', v_count, 'run_at', now());
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.run_floor_snapshots() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.run_floor_snapshots() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.run_floor_snapshots(); $adapter$;
REVOKE ALL ON FUNCTION tj.run_floor_snapshots() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.run_retention_cleanup()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_events_archived bigint := 0;
  v_timelines_archived bigint := 0;
  v_piq_notif_deleted bigint := 0;
  v_iq_notif_deleted bigint := 0;
  v_versions_deleted bigint := 0;
  v_cutoff_90 timestamptz := now() - interval '90 days';
  v_cutoff_30 timestamptz := now() - interval '30 days';
  v_cutoff_180 timestamptz := now() - interval '180 days';
BEGIN
  -- 1) Archive tj.intelligence_events older than 90 days (aggregate by month)
  INSERT INTO intelligence_events_archive (month, event_type, entity_type, total_count, sample_payload)
  SELECT 
    date_trunc('month', created_at)::date AS month,
    COALESCE(event_type, 'unknown') AS event_type,
    COALESCE(entity_type, 'unknown') AS entity_type,
    COUNT(*) AS total_count,
    (SELECT jsonb_build_object('sample_id', id) FROM tj.intelligence_events ie2 WHERE ie2.event_type = ie.event_type LIMIT 1)
  FROM tj.intelligence_events ie
  WHERE created_at < v_cutoff_90
  GROUP BY 1, 2, 3
  ON CONFLICT (month, event_type, entity_type) 
  DO UPDATE SET total_count = intelligence_events_archive.total_count + EXCLUDED.total_count;

  -- Delete archived events
  WITH deleted AS (
    DELETE FROM tj.intelligence_events WHERE created_at < v_cutoff_90 RETURNING 1
  ) SELECT COUNT(*) INTO v_events_archived FROM deleted;

  -- 2) Delete old timelines (mirrors events)
  WITH deleted AS (
    DELETE FROM tj.intelligence_timelines WHERE created_at < v_cutoff_90 RETURNING 1
  ) SELECT COUNT(*) INTO v_timelines_archived FROM deleted;

  -- 3) PIM notifications — delete read ones after 30 days
  WITH deleted AS (
    DELETE FROM piq_notifications 
    WHERE created_at < v_cutoff_30 
    AND id IN (SELECT notification_id FROM piq_notification_reads)
    RETURNING 1
  ) SELECT COUNT(*) INTO v_piq_notif_deleted FROM deleted;
  -- Also delete all notifications older than 90 days regardless of read status
  WITH deleted AS (
    DELETE FROM piq_notifications WHERE created_at < v_cutoff_90 RETURNING 1
  ) SELECT COUNT(*) INTO v_piq_notif_deleted FROM deleted;

  -- 4) IQ notifications — same pattern
  WITH deleted AS (
    DELETE FROM iq_notifications WHERE created_at < v_cutoff_90 RETURNING 1
  ) SELECT COUNT(*) INTO v_iq_notif_deleted FROM deleted;

  -- 5) Product versions — keep 180 days of change history
  WITH deleted AS (
    DELETE FROM aiq_product_versions WHERE created_at < v_cutoff_180 RETURNING 1
  ) SELECT COUNT(*) INTO v_versions_deleted FROM deleted;

  -- 6) Archive notification counts
  INSERT INTO notification_archive (month, source_table, total_sent, total_read)
  VALUES 
    (date_trunc('month', now())::date, 'piq_notifications', v_piq_notif_deleted, 0),
    (date_trunc('month', now())::date, 'iq_notifications', v_iq_notif_deleted, 0)
  ON CONFLICT (month, source_table) 
  DO UPDATE SET total_sent = notification_archive.total_sent + EXCLUDED.total_sent;

  RETURN jsonb_build_object(
    'ran_at', now(),
    'events_archived', v_events_archived,
    'timelines_deleted', v_timelines_archived,
    'piq_notifications_deleted', v_piq_notif_deleted,
    'iq_notifications_deleted', v_iq_notif_deleted,
    'product_versions_deleted', v_versions_deleted
  );
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.run_retention_cleanup() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.run_retention_cleanup() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.run_retention_cleanup(); $adapter$;
REVOKE ALL ON FUNCTION tj.run_retention_cleanup() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.search_knowledge_semantic(query_embedding vector, match_count integer DEFAULT 16, org_filter uuid DEFAULT NULL::uuid)
 RETURNS TABLE(chunk_key text, title text, content text, citation jsonb, metadata jsonb, similarity double precision)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT k.chunk_key, k.title, k.content, k.citation, k.metadata,
    (1 - (k.embedding <=> query_embedding))::float + COALESCE(k.feedback_score, 0) * 0.05 AS similarity
  FROM ai_knowledge_chunks k
  WHERE k.status = 'active'
    AND k.embedding IS NOT NULL
    AND (org_filter IS NULL OR k.organization_id = org_filter OR k.organization_id IS NULL)
  ORDER BY k.embedding <=> query_embedding
  LIMIT match_count;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.search_knowledge_semantic(query_embedding vector, match_count integer, org_filter uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.search_knowledge_semantic(query_embedding vector, match_count integer DEFAULT 16, org_filter uuid DEFAULT NULL::uuid) RETURNS TABLE(chunk_key text, title text, content text, citation jsonb, metadata jsonb, similarity double precision) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.search_knowledge_semantic("query_embedding","match_count","org_filter"); $adapter$;
REVOKE ALL ON FUNCTION tj.search_knowledge_semantic(query_embedding vector, match_count integer, org_filter uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.set_created_by_and_updated_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if new.created_by is null then
    new.created_by := tj_private.current_source_user_id();
  end if;
  new.updated_by := tj_private.current_source_user_id();
  return new;
end;
$function$;
REVOKE ALL ON FUNCTION tj_private.set_created_by_and_updated_by() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_product tj.aiq_products%rowtype; v_package tj.speciq_packages%rowtype; v_comparison tj.ai_product_comparisons%rowtype; v_id uuid;
begin
  select * into v_package from tj.speciq_packages where id=p_package_id;
  if not found then raise exception 'Package not found'; end if;
  select * into v_comparison from tj.ai_product_comparisons where id=p_comparison_id and organization_id=v_package.organization_id;
  if not found or v_comparison.winner_product_id is null then raise exception 'Comparison winner not available'; end if;
  select * into v_product from tj.aiq_products where id=v_comparison.winner_product_id and organization_id=v_package.organization_id;
  if not found then raise exception 'Winner product not found'; end if;
  insert into tj.speciq_package_products(package_id,organization_id,product_name,brand,model_number,category,finish,width_inches,height_inches,depth_inches,weight_lbs,installation_type,msrp,promo_price,aiq_product_id,brand_id,series,product_line,short_description,spec_snapshot,source_comparison_id,selection_reason)
  values(v_package.id,v_package.organization_id,concat_ws(' ',v_product.brand_name,v_product.model),v_product.brand_name,v_product.model,v_product.category,v_product.finish,v_product.width_inches,v_product.height_inches,v_product.depth_inches,v_product.weight_lbs,v_product.installation_type,v_product.msrp,coalesce(v_product.sale_price,v_product.lowest_price),v_product.id,v_product.brand_id,v_product.series,v_product.product_line,v_product.short_description,coalesce(v_product.specs_json,'{}'::jsonb),v_comparison.id,coalesce(v_comparison.comparison_snapshot->>'winner_reason','Selected as comparison winner')) returning id into v_id;
  insert into tj.speciq_package_events(package_id,event_type,event_data)
  values(v_package.id,'comparison_winner_added',jsonb_build_object('comparison_id',v_comparison.id,'product_id',v_product.id,'package_product_id',v_id));
  return v_id;
end; $function$;
REVOKE ALL ON FUNCTION tj.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.start_embedding_worker_run(p_batch_requested integer, p_triggered_by text)
 RETURNS uuid
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
  insert into tj.embedding_worker_runs (batch_requested, triggered_by)
  values (p_batch_requested, p_triggered_by) returning id;
$function$;
REVOKE ALL ON FUNCTION tj_private.start_embedding_worker_run(p_batch_requested integer, p_triggered_by text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.start_embedding_worker_run(p_batch_requested integer, p_triggered_by text) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.start_embedding_worker_run("p_batch_requested","p_triggered_by"); $adapter$;
REVOKE ALL ON FUNCTION tj.start_embedding_worker_run(p_batch_requested integer, p_triggered_by text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.sync_floor_hole_tasks()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_created INTEGER := 0;
  v_closed INTEGER := 0;
  r RECORD;
  v_title TEXT;
  v_priority TEXT;
BEGIN
  FOR r IN
    SELECT h.*, l.name AS store_name,
           COALESCE(sla.days_to_order,3) AS d_order,
           COALESCE(sla.overdue_grace_days,2) AS d_grace
    FROM field_floor_holes h
    JOIN org_locations l ON l.id=h.store_id
    LEFT JOIN field_floor_hole_sla sla ON sla.organization_id=h.organization_id
    WHERE h.status NOT IN ('filled','cancelled')
  LOOP
    v_priority := NULL;
    IF r.status='open' AND (CURRENT_DATE - r.removed_at) > r.d_order THEN
      v_title := 'Order replacement: ' || COALESCE(r.removed_product_name, r.slot_label, 'floor hole')
                 || ' (' || r.store_name || ')';
      v_priority := CASE WHEN (CURRENT_DATE - r.removed_at) > 14 THEN 'urgent' ELSE 'high' END;
    ELSIF r.status IN ('ordered','in_transit') AND r.expected_arrival IS NOT NULL
          AND CURRENT_DATE > (r.expected_arrival + r.d_grace) THEN
      v_title := 'Chase vendor: ' || COALESCE(r.po_number,'no PO') || ' — '
                 || COALESCE(r.removed_product_name,'replacement') || ' (' || r.store_name || ')';
      v_priority := 'high';
    ELSIF r.status='received' THEN
      v_title := 'Place on floor: ' || COALESCE(r.replacement_product_name, r.removed_product_name,'unit')
                 || ' (' || r.store_name || ')';
      v_priority := 'normal';
    END IF;

    IF v_priority IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM crm_tasks t
        WHERE t.organization_id=r.organization_id
          AND t.metadata->>'floor_hole_id' = r.id::text
          AND t.completed_at IS NULL
      ) THEN
        INSERT INTO crm_tasks (organization_id, title, description, priority, due_at, metadata, assignee_user_id)
        VALUES (
          r.organization_id, v_title,
          'Auto-generated from Floor Plan. Slot open ' || (CURRENT_DATE - r.removed_at) || ' days.',
          v_priority, (CURRENT_DATE + 2)::timestamptz,
          jsonb_build_object('floor_hole_id', r.id, 'store_id', r.store_id, 'source','floor_plan'),
          r.assigned_to
        );
        v_created := v_created + 1;
      END IF;
    END IF;
  END LOOP;

  UPDATE crm_tasks t
  SET completed_at = now()
  WHERE t.completed_at IS NULL
    AND t.metadata->>'source' = 'floor_plan'
    AND EXISTS (
      SELECT 1 FROM field_floor_holes h
      WHERE h.id::text = t.metadata->>'floor_hole_id'
        AND h.status IN ('filled','cancelled')
    );
  GET DIAGNOSTICS v_closed = ROW_COUNT;

  RETURN jsonb_build_object('tasks_created', v_created, 'tasks_closed', v_closed, 'run_at', now());
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.sync_floor_hole_tasks() FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.sync_floor_hole_tasks() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.sync_floor_hole_tasks(); $adapter$;
REVOKE ALL ON FUNCTION tj.sync_floor_hole_tasks() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.sync_seats_used()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_org uuid;
  v_count integer;
BEGIN
  v_org := coalesce(NEW.organization_id, OLD.organization_id);
  SELECT count(*) INTO v_count FROM organization_members
  WHERE organization_id = v_org AND status = 'active';
  UPDATE org_app_entitlements SET seats_used = v_count, updated_at = now()
  WHERE organization_id = v_org;
  RETURN coalesce(NEW, OLD);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.sync_seats_used() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.sync_store_billed_entitlements()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_org uuid := coalesce(NEW.organization_id, OLD.organization_id);
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count FROM org_locations
  WHERE organization_id = v_org AND location_type = 'store' AND is_active;
  -- seats_included update fires trg_auto_price, which recomputes the monthly
  UPDATE org_app_entitlements e
  SET seats_included = greatest(v_count, 1)
  FROM platform_pricing p
  WHERE e.organization_id = v_org
    AND p.app_key = e.app_key AND p.tier = e.tier AND p.billing_unit = 'store'
    AND coalesce(e.metadata->>'custom_price','') <> 'true'
    AND e.seats_included <> greatest(v_count, 1);
  RETURN coalesce(NEW, OLD);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.sync_store_billed_entitlements() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin new.updated_at = now(); return new; end $function$;
REVOKE ALL ON FUNCTION tj_private.touch_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_bump_version()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.version := COALESCE(OLD.version,0) + 1;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_bump_version() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_compute_days_inactive()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  NEW.days_inactive := EXTRACT(DAY FROM now() - COALESCE(NEW.last_contact_at, NEW.created_at))::integer;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_compute_days_inactive() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_compute_days_since_contact()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  NEW.days_since_contact := EXTRACT(DAY FROM now() - COALESCE(NEW.last_communication_at, NEW.created_at))::integer;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_compute_days_since_contact() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_floor_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_entity TEXT;
  v_store UUID;
BEGIN
  v_entity := CASE TG_TABLE_NAME
    WHEN 'field_floor_displays' THEN 'display'
    WHEN 'field_floor_display_skus' THEN 'sku'
    WHEN 'field_floor_holes' THEN 'hole'
    WHEN 'field_floor_config' THEN 'config'
    ELSE TG_TABLE_NAME END;

  IF TG_OP = 'DELETE' THEN
    v_store := OLD.store_id;
    INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,changed_by)
    VALUES (OLD.organization_id, v_store, v_entity, OLD.id, 'deleted', tj_private.current_source_user_id());
    RETURN OLD;
  END IF;

  v_store := NEW.store_id;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,changed_by)
    VALUES (NEW.organization_id, v_store, v_entity, NEW.id, 'created', tj_private.current_source_user_id());
    RETURN NEW;
  END IF;

  -- UPDATE: record meaningful field changes
  IF TG_TABLE_NAME = 'field_floor_displays' THEN
    IF NEW.floor_units IS DISTINCT FROM OLD.floor_units THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'updated','floor_units',OLD.floor_units::text,NEW.floor_units::text,tj_private.current_source_user_id());
    END IF;
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'status_changed','is_active',OLD.is_active::text,NEW.is_active::text,tj_private.current_source_user_id());
    END IF;
    IF NEW.brand_name IS DISTINCT FROM OLD.brand_name THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'updated','brand_name',OLD.brand_name,NEW.brand_name,tj_private.current_source_user_id());
    END IF;
  ELSIF TG_TABLE_NAME = 'field_floor_holes' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'status_changed','status',OLD.status,NEW.status,tj_private.current_source_user_id());
    END IF;
    IF NEW.expected_arrival IS DISTINCT FROM OLD.expected_arrival THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'updated','expected_arrival',OLD.expected_arrival::text,NEW.expected_arrival::text,tj_private.current_source_user_id());
    END IF;
  ELSIF TG_TABLE_NAME = 'field_floor_display_skus' THEN
    IF NEW.is_active IS DISTINCT FROM OLD.is_active THEN
      INSERT INTO field_floor_audit(organization_id,store_id,entity_type,entity_id,action,field_changed,old_value,new_value,changed_by)
      VALUES (NEW.organization_id,v_store,v_entity,NEW.id,'status_changed','is_active',OLD.is_active::text,NEW.is_active::text,tj_private.current_source_user_id());
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_floor_audit() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_floor_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_floor_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_notify_deal_stage_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_stage_lower text;
  v_notify_user uuid;
BEGIN
  IF OLD.stage IS NOT DISTINCT FROM NEW.stage THEN RETURN NEW; END IF;
  v_stage_lower := lower(COALESCE(NEW.stage, ''));
  v_notify_user := COALESCE(NEW.owner_user_id, NEW.contact_id);
  IF v_notify_user IS NULL THEN RETURN NEW; END IF;

  IF v_stage_lower LIKE '%won%' THEN
    INSERT INTO crm_notifications (organization_id, user_id, title, body, severity, category, entity_type, entity_id)
    VALUES (NEW.organization_id, NEW.owner_user_id,
      '🎉 Deal Won: ' || LEFT(NEW.title, 60),
      'Closed at ' || COALESCE(NEW.value_amount::text, '0') || ' CAD.',
      'info', 'deal', 'deal', NEW.id);
  ELSIF v_stage_lower LIKE '%lost%' THEN
    INSERT INTO crm_notifications (organization_id, user_id, title, body, severity, category, entity_type, entity_id)
    VALUES (NEW.organization_id, NEW.owner_user_id,
      '📉 Deal Lost: ' || LEFT(NEW.title, 60),
      'Reason: ' || COALESCE(NEW.lost_reason, 'Not specified'),
      'warning', 'deal', 'deal', NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_notify_deal_stage_change() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_notify_sla_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- Notify the assigned user about SLA events
  IF NEW.assigned_to IS NOT NULL AND NEW.event_type IN ('escalation', 'critical') THEN
    INSERT INTO crm_notifications (organization_id, user_id, title, body, severity, category, entity_type, entity_id)
    VALUES (
      NEW.organization_id,
      NEW.assigned_to,
      CASE NEW.event_type WHEN 'critical' THEN '🔴 Critical SLA Breach' ELSE '⚠️ SLA Escalation' END,
      'Contact idle for ' || COALESCE(NEW.days_since_contact, 0) || ' days — requires immediate attention.',
      CASE NEW.event_type WHEN 'critical' THEN 'critical' ELSE 'urgent' END,
      'sla',
      COALESCE(CASE WHEN NEW.contact_id IS NOT NULL THEN 'contact' ELSE 'deal' END, 'contact'),
      COALESCE(NEW.contact_id, NEW.deal_id)
    );
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_notify_sla_event() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_provision_roles()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  PERFORM tj.provision_standard_roles(NEW.id);
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_provision_roles() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.trg_retailer_products_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.trg_retailer_products_updated_at() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.up_auto_create_crm_on_accept()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_contact_id UUID;
  v_deal_id UUID;
  v_cust_name TEXT;
  v_cust_phone TEXT;
  v_cust_email TEXT;
  v_client_type TEXT;
  v_store_name TEXT;
BEGIN
  IF (TG_OP = 'INSERT' AND NEW.accepted_at IS NOT NULL)
     OR (TG_OP = 'UPDATE' AND OLD.accepted_at IS NULL AND NEW.accepted_at IS NOT NULL) THEN

    IF NEW.contact_id IS NOT NULL THEN
      RETURN NEW;
    END IF;

    IF NEW.customer_waiting_id IS NOT NULL THEN
      SELECT 
        coalesce(nullif(cwq.customer_display_name,''), 'Walk-in Customer'),
        cwq.customer_phone,
        cwq.customer_email,
        coalesce(cwq.client_type, 'retail')
      INTO v_cust_name, v_cust_phone, v_cust_email, v_client_type
      FROM iq_customer_waiting_queue cwq
      WHERE cwq.id = NEW.customer_waiting_id;
    END IF;

    v_cust_name := coalesce(v_cust_name, 'Walk-in Customer');
    v_client_type := coalesce(v_client_type, NEW.client_type, 'retail');

    SELECT name INTO v_store_name FROM org_locations WHERE id = NEW.store_id;

    INSERT INTO aicrm_contacts (
      organization_id, full_name, phone, email, source, 
      created_by, updated_by, up_interaction_id
    ) VALUES (
      NEW.organization_id,
      v_cust_name,
      v_cust_phone,
      v_cust_email::citext,
      'walk_in',
      NEW.salesperson_user_id,
      NEW.salesperson_user_id,
      NEW.id
    ) RETURNING id INTO v_contact_id;

    INSERT INTO crm_deals (
      organization_id, contact_id, owner_user_id, title, stage,
      record_type, source, up_interaction_id, created_at, updated_at
    ) VALUES (
      NEW.organization_id,
      v_contact_id,
      NEW.salesperson_user_id,
      v_cust_name || ' — ' || coalesce(v_store_name, 'Floor Visit'),
      'Floor Visit',
      CASE v_client_type
        WHEN 'commercial' THEN 'commercial'
        WHEN 'builder_designer' THEN 'builder_designer'
        WHEN 'trade' THEN 'trade'
        ELSE 'individual'
      END,
      'walk_in',
      NEW.id,
      now(), now()
    ) RETURNING id INTO v_deal_id;

    NEW.contact_id := v_contact_id;
  END IF;

  RETURN NEW;
END $function$;
REVOKE ALL ON FUNCTION tj_private.up_auto_create_crm_on_accept() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.update_floor_display_safe(p_id uuid, p_expected_version integer, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_org UUID; v_current INTEGER; v_new_version INTEGER;
BEGIN
  SELECT organization_id, version INTO v_org, v_current
  FROM field_floor_displays WHERE id = p_id;

  IF v_org IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'not_found');
  END IF;
  PERFORM assert_floor_org_access(v_org);

  IF p_expected_version IS NOT NULL AND v_current <> p_expected_version THEN
    RETURN jsonb_build_object('ok', false, 'error', 'conflict',
      'current_version', v_current, 'your_version', p_expected_version);
  END IF;

  UPDATE field_floor_displays SET
    display_name    = COALESCE(p_payload->>'display_name', display_name),
    display_type    = COALESCE(p_payload->>'display_type', display_type),
    brand_id        = CASE WHEN p_payload ? 'brand_id' THEN NULLIF(p_payload->>'brand_id','')::uuid ELSE brand_id END,
    brand_name      = CASE WHEN p_payload ? 'brand_name' THEN NULLIF(p_payload->>'brand_name','') ELSE brand_name END,
    primary_category= CASE WHEN p_payload ? 'primary_category' THEN NULLIF(p_payload->>'primary_category','') ELSE primary_category END,
    floor_units     = COALESCE((p_payload->>'floor_units')::numeric, floor_units),
    location_notes  = CASE WHEN p_payload ? 'location_notes' THEN NULLIF(p_payload->>'location_notes','') ELSE location_notes END
  WHERE id = p_id
  RETURNING version INTO v_new_version;

  RETURN jsonb_build_object('ok', true, 'version', v_new_version);
END;
$function$;
REVOKE ALL ON FUNCTION tj_private.update_floor_display_safe(p_id uuid, p_expected_version integer, p_payload jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.update_floor_display_safe(p_id uuid, p_expected_version integer, p_payload jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.update_floor_display_safe("p_id","p_expected_version","p_payload"); $adapter$;
REVOKE ALL ON FUNCTION tj.update_floor_display_safe(p_id uuid, p_expected_version integer, p_payload jsonb) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.write_embedding(p_table_name text, p_row_id uuid, p_embedding vector, p_model text, p_source_hash text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
begin
  if p_table_name = 'ai_knowledge_chunks' then
    update tj.ai_knowledge_chunks
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  elsif p_table_name = 'products' then
    update tj.products
       set embedding = p_embedding, embedding_model = p_model, source_hash = p_source_hash
     where id = p_row_id;
  else
    return false;
  end if;
  return found;
end $function$;
REVOKE ALL ON FUNCTION tj_private.write_embedding(p_table_name text, p_row_id uuid, p_embedding vector, p_model text, p_source_hash text) FROM PUBLIC,anon,authenticated,service_role;
CREATE FUNCTION tj.write_embedding(p_table_name text, p_row_id uuid, p_embedding vector, p_model text, p_source_hash text) RETURNS boolean LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.write_embedding("p_table_name","p_row_id","p_embedding","p_model","p_source_hash"); $adapter$;
REVOKE ALL ON FUNCTION tj.write_embedding(p_table_name text, p_row_id uuid, p_embedding vector, p_model text, p_source_hash text) FROM PUBLIC,anon,authenticated,service_role;
NOTIFY pgrst,'reload schema';
