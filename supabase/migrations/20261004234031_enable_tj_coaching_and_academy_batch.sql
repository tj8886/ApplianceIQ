-- Enable app entry points together. Supporting routines remain owner-only.
SET LOCAL search_path='tj','extensions','pg_temp';
CREATE OR REPLACE FUNCTION tj_private.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare v_intervention uuid;
begin
 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 p_user_id:=coalesce(p_user_id,tj_private.current_source_user_id());
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;
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
GRANT EXECUTE ON FUNCTION tj_private.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_generate_coaching("p_organization_id","p_user_id","p_focus_date"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase4_generate_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25)
 RETURNS TABLE(user_id uuid, intervention_id uuid)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare r record; v_id uuid;
begin
 if not tj.is_org_admin(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
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
GRANT EXECUTE ON FUNCTION tj_private.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase4_generate_org_coaching("p_organization_id","p_focus_date","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase4_generate_org_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer DEFAULT 100)
 RETURNS TABLE(intervention_id uuid, result jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare r record;
begin
 if not tj.is_org_admin(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
  if tj_private.current_source_user_id() is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  update tj.ai_intervention_evaluations set status='due',updated_at=now() where organization_id=p_organization_id and status='pending' and evaluation_due_at<=now();
  for r in select e.intervention_id from tj.ai_intervention_evaluations e join tj.ai_coaching_interventions i on i.id=e.intervention_id where e.organization_id=p_organization_id and e.status='due' and i.status='completed' order by e.evaluation_due_at limit greatest(1,least(coalesce(p_limit,100),500))
  loop intervention_id:=r.intervention_id; result:=tj.phase4_evaluate_intervention(r.intervention_id,false); return next; end loop;
  return;
end $function$;
REVOKE ALL ON FUNCTION tj_private.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer DEFAULT 100) RETURNS TABLE(intervention_id uuid, result jsonb) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase4_evaluate_due_org("p_organization_id","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase4_evaluate_due_org(p_organization_id uuid, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare
  v_i tj.ai_coaching_interventions%rowtype; v_e tj.ai_intervention_evaluations%rowtype;
  v_current numeric; v_current_at timestamptz; v_delta numeric; v_success boolean; v_outcome uuid; v_rec uuid; v_source text;
begin
 if tj_private.current_source_user_id() is null or not exists(select 1 from tj.ai_coaching_interventions i join tj.organizations o on o.id=i.organization_id and o.deleted_at is null where i.id=p_intervention_id and tj.is_org_member(i.organization_id) and (i.user_id=tj_private.current_source_user_id() or tj.is_org_admin(i.organization_id))) then raise exception 'access_denied' using errcode='42501'; end if;
 perform 1 from tj.ai_coaching_interventions where id=p_intervention_id for update;
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
GRANT EXECUTE ON FUNCTION tj_private.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean DEFAULT false) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_evaluate_intervention("p_intervention_id","p_force"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase4_evaluate_intervention(p_intervention_id uuid, p_force boolean) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid DEFAULT NULL::uuid, p_score numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare v_i tj.ai_coaching_interventions%rowtype; v_step tj.ai_intervention_steps%rowtype; v_remaining int; v_completed boolean;
begin
 if tj_private.current_source_user_id() is null or not exists(select 1 from tj.ai_coaching_interventions i join tj.organizations o on o.id=i.organization_id and o.deleted_at is null where i.id=p_intervention_id and tj.is_org_member(i.organization_id) and (i.user_id=tj_private.current_source_user_id() or tj.is_org_admin(i.organization_id))) then raise exception 'access_denied' using errcode='42501'; end if;
 perform 1 from tj.ai_coaching_interventions where id=p_intervention_id for update;
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
GRANT EXECUTE ON FUNCTION tj_private.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid DEFAULT NULL::uuid, p_score numeric DEFAULT NULL::numeric, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase4_complete_step("p_intervention_id","p_step_order","p_completion_ref","p_score","p_metadata"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase4_complete_step(p_intervention_id uuid, p_step_order integer, p_completion_ref uuid, p_score numeric, p_metadata jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare v_id uuid; v_choice jsonb;
begin
 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 p_user_id:=coalesce(p_user_id,tj_private.current_source_user_id());
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;
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
GRANT EXECUTE ON FUNCTION tj_private.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date DEFAULT CURRENT_DATE) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_generate_adaptive_coaching("p_organization_id","p_user_id","p_focus_date"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase5_generate_adaptive_coaching(p_organization_id uuid, p_user_id uuid, p_focus_date date) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25)
 RETURNS TABLE(user_id uuid, intervention_id uuid, adaptation jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare r record; v_result jsonb;
begin
 if not tj.is_org_admin(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
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
GRANT EXECUTE ON FUNCTION tj_private.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date DEFAULT CURRENT_DATE, p_limit integer DEFAULT 25) RETURNS TABLE(user_id uuid, intervention_id uuid, adaptation jsonb) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.phase5_generate_org_adaptive_coaching("p_organization_id","p_focus_date","p_limit"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase5_generate_org_adaptive_coaching(p_organization_id uuid, p_focus_date date, p_limit integer) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare v_profile tj.ai_adaptive_coaching_profiles%rowtype; v_best tj.ai_coaching_strategy_performance%rowtype; v_strategy text; v_level int; v_sequence jsonb; v_conf numeric; v_explore boolean:=false; v_target numeric;
begin
 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 p_user_id:=coalesce(p_user_id,tj_private.current_source_user_id());
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;
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
GRANT EXECUTE ON FUNCTION tj_private.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid DEFAULT NULL::uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT tj_private.phase5_select_strategy("p_organization_id","p_user_id","p_metric_key","p_skill_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.phase5_select_strategy(p_organization_id uuid, p_user_id uuid, p_metric_key text, p_skill_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid DEFAULT tj_private.current_source_user_id())
 RETURNS TABLE(scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, target_competency_name text, target_score numeric, reason text, persona text, context text, objectives jsonb, competency_weights jsonb, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare
  weak record;
  target_difficulty smallint;
begin
 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
 p_user_id:=coalesce(p_user_id,tj_private.current_source_user_id());
 if p_user_id is null or (p_user_id<>tj_private.current_source_user_id() and not tj.is_org_admin(p_organization_id)) then raise exception 'access_denied' using errcode='42501'; end if;
 if not exists(select 1 from tj.organization_members where organization_id=p_organization_id and user_id=p_user_id and status='active') then raise exception 'rep_not_active_in_organization'; end if;
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
REVOKE ALL ON FUNCTION tj_private.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid DEFAULT NULL::uuid) RETURNS TABLE(scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, target_competency_name text, target_score numeric, reason text, persona text, context text, objectives jsonb, competency_weights jsonb, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.performance_get_next_scenario("p_organization_id","p_user_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.performance_get_next_scenario(p_organization_id uuid, p_user_id uuid) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text DEFAULT 'you_sell'::text)
 RETURNS TABLE(roleplay_session_id uuid, scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, reason text, persona text, context text, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
declare
  rec record;
  v_session_id uuid;
  v_intervention_id uuid;
  v_mode text;
begin
 if not tj.is_org_member(p_organization_id) or not exists(select 1 from tj.organizations where id=p_organization_id and deleted_at is null) then raise exception 'access_denied' using errcode='42501'; end if;
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
REVOKE ALL ON FUNCTION tj_private.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) TO authenticated;
CREATE OR REPLACE FUNCTION tj.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text DEFAULT 'you_sell'::text) RETURNS TABLE(roleplay_session_id uuid, scenario_id uuid, scenario_code text, title text, difficulty smallint, target_competency_code text, reason text, persona text, context text, customer_profile jsonb, hidden_facts jsonb, objections jsonb, success_criteria jsonb, opening_line text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.performance_start_adaptive_roleplay("p_organization_id","p_mode"); $adapter$;
REVOKE ALL ON FUNCTION tj.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.performance_start_adaptive_roleplay(p_organization_id uuid, p_mode text) TO authenticated;
CREATE OR REPLACE FUNCTION tj_private.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text DEFAULT NULL::text, p_external_id text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text)
 RETURNS TABLE(canonical_id uuid, canonical_table text, display_name text, confidence numeric, match_method text, source_system text, source_table text, source_record_id text, external_id text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'tj','extensions','pg_temp'
AS $function$
 select l.canonical_id,l.canonical_table,l.display_name,l.confidence,l.match_method,l.source_system,l.source_table,l.source_record_id,l.external_id
 from tj.platform_identity_links l
 where tj.is_org_member(p_organization_id) and exists(select 1 from tj.organizations o where o.id=p_organization_id and o.deleted_at is null) and l.organization_id=p_organization_id and l.entity_type=p_entity_type
 and (p_source_system is null or l.source_system=p_source_system)
 and (p_external_id is null or l.external_id=p_external_id)
 and (p_source_record_id is null or l.source_record_id=p_source_record_id)
 and exists(select 1 from tj.organization_members m where m.organization_id=p_organization_id and m.user_id=tj_private.current_source_user_id() and m.status='active')
 order by l.is_primary desc,l.confidence desc,l.last_seen_at desc limit 20;
$function$;
REVOKE ALL ON FUNCTION tj_private.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) TO authenticated;
CREATE OR REPLACE FUNCTION tj.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text DEFAULT NULL::text, p_external_id text DEFAULT NULL::text, p_source_record_id text DEFAULT NULL::text) RETURNS TABLE(canonical_id uuid, canonical_table text, display_name text, confidence numeric, match_method text, source_system text, source_table text, source_record_id text, external_id text) LANGUAGE sql SECURITY INVOKER SET search_path='tj','extensions','pg_temp' AS $adapter$ SELECT * FROM tj_private.platform_resolve_identity("p_organization_id","p_entity_type","p_source_system","p_external_id","p_source_record_id"); $adapter$;
REVOKE ALL ON FUNCTION tj.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj.platform_resolve_identity(p_organization_id uuid, p_entity_type text, p_source_system text, p_external_id text, p_source_record_id text) TO authenticated;
NOTIFY pgrst,'reload schema';
