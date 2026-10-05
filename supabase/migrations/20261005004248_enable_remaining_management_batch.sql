-- Batch activation of guarded management, CRM, entitlement and Spec IQ workflows.
CREATE OR REPLACE FUNCTION tj_private.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text DEFAULT 'morning'::text, p_brief_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ai_manager_generate_executive_brief:'||p_organization_id::text,0));

  if not tj.is_org_member(p_organization_id) then
    raise exception 'organization_access_denied';
  end if;
  if p_brief_date IS NULL THEN RAISE EXCEPTION 'brief_date_required'; END IF;
  if p_brief_type IS NULL OR p_brief_type not in ('morning','end_of_day','weekly') then
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
  where organization_id=p_organization_id AND EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids approved WHERE approved.prediction_id=tj.decision_predictions.id);

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
REVOKE ALL ON FUNCTION tj_private.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text DEFAULT 'morning'::text, p_brief_date date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.ai_manager_generate_executive_brief(p_organization_id,p_brief_type,p_brief_date); $adapter$;
REVOKE ALL ON FUNCTION tj.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text DEFAULT 'morning'::text, p_brief_date date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.ai_manager_generate_executive_brief(p_organization_id,p_brief_type,p_brief_date); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_generate_executive_brief(p_organization_id uuid, p_brief_type text, p_brief_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.ai_manager_run_cycle(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('ai_manager_run_cycle:'||p_organization_id::text,0));

  if not tj.is_org_member(p_organization_id) then raise exception 'not_authorized'; end if;

  insert into tj.ai_manager_assignments(organization_id,decision_case_id,title,instructions,assigned_to,assigned_by,priority,status,due_at,metadata)
  select c.organization_id,c.id,c.title,
    coalesce(c.recommendation,'Review the evidence, choose an action, and record the result.'),
    CASE WHEN EXISTS(SELECT 1 FROM tj.organization_members m WHERE m.organization_id=p_organization_id AND m.user_id=c.owner_id AND m.status='active') THEN c.owner_id ELSE NULL END,tj_private.current_source_user_id(),
    case c.severity when 'critical' then 'critical' when 'high' then 'high' when 'medium' then 'medium' else 'low' end,
    'open',
    coalesce(c.due_at, now() + case c.severity when 'critical' then interval '4 hours' when 'high' then interval '1 day' when 'medium' then interval '3 days' else interval '7 days' end),
    jsonb_build_object('module',c.module,'priority_score',c.priority_score,'financial_impact_cad',c.financial_impact_cad,'source_system',c.source_system)
  from tj.decision_cases c
  where c.organization_id=p_organization_id and c.status in ('open','accepted','in_progress')
    and not exists(select 1 from tj.ai_manager_assignments a where a.decision_case_id=c.id and a.organization_id=p_organization_id and a.status in ('open','accepted','in_progress','blocked'))
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
  where a.organization_id=p_organization_id and a.escalation_level>0 and a.status not in ('completed','cancelled') AND NOT EXISTS(SELECT 1 FROM tj.ai_manager_escalations e WHERE e.assignment_id=a.id AND e.organization_id=p_organization_id AND e.level=a.escalation_level)
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
REVOKE ALL ON FUNCTION tj_private.ai_manager_run_cycle(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.ai_manager_run_cycle(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.ai_manager_run_cycle(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.ai_manager_run_cycle(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.ai_manager_run_cycle(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.ai_manager_run_cycle(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_ai_manager_run_cycle(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.ai_manager_run_cycle(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_ai_manager_run_cycle(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_ai_manager_run_cycle(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.decision_generate_operational_forecasts(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare
  v_revenue numeric:=0; v_avg_order numeric:=0; v_conv numeric:=0; v_conv_target numeric:=0; v_walkins numeric:=0;
  v_training numeric:=0; v_training_target numeric:=100; v_pipeline numeric:=0; v_weighted numeric:=0; v_stale_value numeric:=0;
  v_pred_id uuid; v_case uuid; v_created int:=0; v_prediction int:=0; v_gap numeric; v_impact numeric; v_prob numeric;
  v_critical int:=0;
begin
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('decision_generate_operational_forecasts:'||p_organization_id::text,0));

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
    delete from tj.decision_predictions p where p.organization_id=p_organization_id AND p.decision_case_id=v_case and p.prediction_type='revenue' AND p.status<>'measured' AND EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids approved WHERE approved.prediction_id=p.id);
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'revenue','30_days',v_pipeline,v_weighted,v_weighted-v_pipeline,'CAD',v_prob,v_weighted*.75,v_weighted*1.2,v_stale_value*.15,v_weighted,jsonb_build_object('method','probability-weighted opportunity value','stale_decay_rate',.15),'ApplianceIQ rules forecast','1.0',now()+interval '7 days') RETURNING id INTO v_pred_id;
    INSERT INTO tj_private.approved_prediction_ids(prediction_id,basis) VALUES(v_pred_id,'guarded_generation');
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
    delete from tj.decision_predictions p where p.organization_id=p_organization_id AND p.decision_case_id=v_case and p.prediction_type='conversion_revenue' AND p.status<>'measured' AND EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids approved WHERE approved.prediction_id=p.id);
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'conversion_revenue','30_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.78,v_revenue+v_impact*.5,v_revenue+v_impact,v_impact,v_impact,jsonb_build_object('formula','walk-ins × conversion gap × average order','conversion_gap_points',v_gap),'ApplianceIQ opportunity model','1.0',now()+interval '14 days') RETURNING id INTO v_pred_id;
    INSERT INTO tj_private.approved_prediction_ids(prediction_id,basis) VALUES(v_pred_id,'guarded_generation');
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
    delete from tj.decision_predictions p where p.organization_id=p_organization_id AND p.decision_case_id=v_case and p.prediction_type='training_revenue' AND p.status<>'measured' AND EXISTS(SELECT 1 FROM tj_private.approved_prediction_ids approved WHERE approved.prediction_id=p.id);
    insert into tj.decision_predictions(organization_id,decision_case_id,prediction_type,horizon,baseline_value,predicted_value,predicted_delta,unit,probability,lower_bound,upper_bound,cost_of_inaction_cad,financial_impact_cad,assumptions,model_name,model_version,expires_at)
    values(p_organization_id,v_case,'training_revenue','60_days',v_revenue,v_revenue+v_impact,v_impact,'CAD',.58,v_revenue,v_revenue+v_impact*1.5,v_impact,v_impact,jsonb_build_object('conservative_lift_rate',.03,'completion_gap_points',v_gap),'ApplianceIQ training impact proxy','1.0',now()+interval '30 days') RETURNING id INTO v_pred_id;
    INSERT INTO tj_private.approved_prediction_ids(prediction_id,basis) VALUES(v_pred_id,'guarded_generation');
    v_prediction:=v_prediction+1;
  end if;

  select count(*) into v_critical from tj.field_findings f join tj.field_clients c on c.id=f.client_id where c.organization_id=p_organization_id and lower(coalesce(f.severity,''))='critical' and lower(coalesce(f.status,'open')) not in ('resolved','closed');
  if v_critical>0 then
    update tj.decision_cases set consequence_if_ignored=format('%s critical field finding(s) remain exposed. No CAD estimate is shown until sales attribution exists.',v_critical),metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('critical_findings',v_critical,'financial_estimate_status','insufficient_attribution'),updated_at=now() where organization_id=p_organization_id and source_system='executive_intelligence' and module='field' and status not in ('completed','rejected');
  end if;

  return jsonb_build_object('organization_id',p_organization_id,'cases_created',v_created,'predictions_generated',v_prediction,'inputs',jsonb_build_object('revenue',v_revenue,'avg_order',v_avg_order,'conversion',v_conv,'conversion_target',v_conv_target,'walk_ins',v_walkins,'training_completion',v_training,'open_pipeline',v_pipeline,'weighted_pipeline',v_weighted,'stale_pipeline',v_stale_value,'critical_findings',v_critical));
end $function$;
REVOKE ALL ON FUNCTION tj_private.decision_generate_operational_forecasts(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_generate_operational_forecasts(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_generate_operational_forecasts(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_generate_operational_forecasts(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_generate_operational_forecasts(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_generate_operational_forecasts(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_decision_generate_operational_forecasts(p_organization_id uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_generate_operational_forecasts(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_generate_operational_forecasts(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_generate_operational_forecasts(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.decision_sync_executive_insights(p_organization_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare r record; v_count integer:=0; v_id uuid; v_conf numeric;
begin
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('decision_sync_executive_insights:'||p_organization_id::text,0));

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
REVOKE ALL ON FUNCTION tj_private.decision_sync_executive_insights(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.decision_sync_executive_insights(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.decision_sync_executive_insights(p_organization_id uuid) RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_sync_executive_insights(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.decision_sync_executive_insights(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.decision_sync_executive_insights(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_decision_sync_executive_insights(p_organization_id uuid) RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.decision_sync_executive_insights(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_decision_sync_executive_insights(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_decision_sync_executive_insights(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.executive_answer_question(p_organization_id uuid, p_question text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('executive_answer_question:'||p_organization_id::text,0));

  if tj_private.current_source_user_id() is not null and not exists (
    select 1 from organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.current_source_user_id() and coalesce(m.status,'active')='active'
  ) then raise exception 'Not authorized for organization'; end if;

  IF nullif(btrim(p_question),'') IS NULL OR length(p_question)>4000 THEN RAISE EXCEPTION 'invalid_question'; END IF;
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
    v_answer:=jsonb_build_object('headline','Field and store execution','field',v_snapshot.metrics->'field','related_insights',coalesce((select jsonb_agg(jsonb_build_object('title',title,'summary',summary,'severity',severity,'recommended_action',recommended_action) order by priority_score desc) from executive_intelligence_insights where snapshot_id=v_snapshot.id AND organization_id=p_organization_id and domain='field'),'[]'::jsonb));
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
REVOKE ALL ON FUNCTION tj_private.executive_answer_question(p_organization_id uuid, p_question text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.executive_answer_question(p_organization_id uuid, p_question text) TO authenticated;
CREATE OR REPLACE FUNCTION tj.executive_answer_question(p_organization_id uuid, p_question text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.executive_answer_question(p_organization_id,p_question); $adapter$;
REVOKE ALL ON FUNCTION tj.executive_answer_question(p_organization_id uuid, p_question text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.executive_answer_question(p_organization_id uuid, p_question text) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_executive_answer_question(p_organization_id uuid, p_question text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.executive_answer_question(p_organization_id,p_question); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_executive_answer_question(p_organization_id uuid, p_question text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_executive_answer_question(p_organization_id uuid, p_question text) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.executive_refresh_command_centre(p_organization_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  PERFORM tj_private.assert_runtime_org(p_organization_id);
  IF NOT tj.is_org_admin(p_organization_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('executive_refresh_command_centre:'||p_organization_id::text,0));

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
REVOKE ALL ON FUNCTION tj_private.executive_refresh_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.executive_refresh_command_centre(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.executive_refresh_command_centre(p_organization_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.executive_refresh_command_centre(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION tj.executive_refresh_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.executive_refresh_command_centre(p_organization_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_executive_refresh_command_centre(p_organization_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.executive_refresh_command_centre(p_organization_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_executive_refresh_command_centre(p_organization_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_executive_refresh_command_centre(p_organization_id uuid) TO authenticated;
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
  PERFORM tj_private.assert_runtime_org(p_org_id);
  IF NOT tj.is_org_admin(p_org_id) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('evaluate_sla_rules:'||p_org_id::text,0));

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
GRANT EXECUTE ON FUNCTION tj_private.evaluate_sla_rules(p_org_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.evaluate_sla_rules(p_org_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.evaluate_sla_rules(p_org_id); $adapter$;
REVOKE ALL ON FUNCTION tj.evaluate_sla_rules(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.evaluate_sla_rules(p_org_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_evaluate_sla_rules(p_org_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.evaluate_sla_rules(p_org_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_evaluate_sla_rules(p_org_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_evaluate_sla_rules(p_org_id uuid) TO authenticated;
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
  JOIN organizations o ON o.id = m.organization_id AND o.status = 'active' AND o.deleted_at IS NULL
  JOIN org_app_entitlements e ON e.organization_id = m.organization_id AND e.app_key = p_app
  LEFT JOIN org_roles r ON r.id = m.org_role_id AND r.organization_id=m.organization_id AND r.active
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
  JOIN org_locations l ON l.id = lm.location_id AND l.organization_id=lm.organization_id AND l.is_active
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
GRANT EXECUTE ON FUNCTION tj_private.check_app_access(p_app text) TO authenticated;
CREATE OR REPLACE FUNCTION tj.check_app_access(p_app text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.check_app_access(p_app); $adapter$;
REVOKE ALL ON FUNCTION tj.check_app_access(p_app text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.check_app_access(p_app text) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_check_app_access(p_app text) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.check_app_access(p_app); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_check_app_access(p_app text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_check_app_access(p_app text) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_product tj.aiq_products%rowtype; v_package tj.speciq_packages%rowtype; v_comparison tj.ai_product_comparisons%rowtype; v_id uuid;
begin
  select * into v_package from tj.speciq_packages where id=p_package_id FOR UPDATE;
  if not found then raise exception 'Package not found'; end if;
  PERFORM tj_private.assert_runtime_org(v_package.organization_id);
  IF v_package.deleted_at IS NOT NULL OR coalesce(v_package.locked,false) OR v_package.approval_status='approved' THEN RAISE EXCEPTION 'package_not_editable' USING ERRCODE='42501'; END IF;
  IF NOT tj.is_org_admin(v_package.organization_id) AND v_package.created_by IS DISTINCT FROM tj_private.current_source_user_id() THEN RAISE EXCEPTION 'package_owner_required' USING ERRCODE='42501'; END IF;
  select * into v_comparison from tj.ai_product_comparisons where id=p_comparison_id and organization_id=v_package.organization_id;
  IF NOT tj.is_org_admin(v_package.organization_id) AND v_comparison.user_id IS DISTINCT FROM tj_private.current_source_user_id() THEN RAISE EXCEPTION 'comparison_owner_required' USING ERRCODE='42501'; END IF;
  if not found or v_comparison.winner_product_id is null then raise exception 'Comparison winner not available'; end if;
  select * into v_product from tj.aiq_products where id=v_comparison.winner_product_id and organization_id=v_package.organization_id;
  if not found then raise exception 'Winner product not found'; end if;
  SELECT id INTO v_id FROM tj.speciq_package_products WHERE package_id=p_package_id AND organization_id=v_package.organization_id AND source_comparison_id=p_comparison_id AND aiq_product_id=v_product.id LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  insert into tj.speciq_package_products(package_id,organization_id,product_name,brand,model_number,category,finish,width_inches,height_inches,depth_inches,weight_lbs,installation_type,msrp,promo_price,aiq_product_id,brand_id,series,product_line,short_description,spec_snapshot,source_comparison_id,selection_reason)
  values(v_package.id,v_package.organization_id,concat_ws(' ',v_product.brand_name,v_product.model),v_product.brand_name,v_product.model,v_product.category,v_product.finish,v_product.width_inches,v_product.height_inches,v_product.depth_inches,v_product.weight_lbs,v_product.installation_type,v_product.msrp,coalesce(v_product.sale_price,v_product.lowest_price),v_product.id,v_product.brand_id,v_product.series,v_product.product_line,v_product.short_description,coalesce(v_product.specs_json,'{}'::jsonb),v_comparison.id,coalesce(v_comparison.comparison_snapshot->>'winner_reason','Selected as comparison winner')) returning id into v_id;
  insert into tj.speciq_package_events(package_id,event_type,event_data)
  values(v_package.id,'comparison_winner_added',jsonb_build_object('comparison_id',v_comparison.id,'product_id',v_product.id,'package_product_id',v_id));
  UPDATE tj.speciq_packages SET updated_at=now(),updated_by=tj_private.current_source_user_id() WHERE id=p_package_id;
  return v_id;
end; $function$;
REVOKE ALL ON FUNCTION tj_private.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.speciq_add_comparison_winner(p_package_id,p_comparison_id); $adapter$;
REVOKE ALL ON FUNCTION tj.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.tj_runtime_speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $adapter$ SELECT tj_private.speciq_add_comparison_winner(p_package_id,p_comparison_id); $adapter$;
REVOKE ALL ON FUNCTION public.tj_runtime_speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_runtime_speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
