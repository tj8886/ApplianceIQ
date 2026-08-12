-- Canonical coaching consolidation.
-- Performance Brain diagnoses; the existing AI intervention engine executes;
-- daily_coaching_focus and crm_daily_five remain the operational surfaces.

create or replace function public.ai_generate_daily_coaching_focus(p_organization_id uuid, p_user_id uuid, p_focus_date date default current_date)
returns uuid language plpgsql set search_path to 'public','pg_temp' as $function$
declare
  v_diag record; v_perf record; v_skill record; v_scenario record; v_intervention uuid; v_existing uuid;
  v_skill_key text; v_difficulty integer; v_insight text; v_existing_items jsonb := '[]'::jsonb; v_retained_items jsonb := '[]'::jsonb; v_coaching_items jsonb;
begin
  if auth.uid() is not null then
    if p_user_id <> auth.uid() and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized to generate coaching for this user'; end if;
    if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  end if;

  select i.id into v_existing from public.ai_coaching_interventions i
  where i.organization_id=p_organization_id and i.user_id=p_user_id
    and i.status in ('recommended','assigned','in_progress')
    and i.created_at >= p_focus_date::timestamptz - interval '1 day'
  order by i.created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;

  select d.* into v_diag from public.performance_metric_diagnostics d
  where d.organization_id=p_organization_id and d.user_id=p_user_id
    and d.actual_value is not null and d.target_value is not null and d.actual_value < d.target_value
  order by d.target_gap_pct desc nulls last,d.causal_weight desc,d.computed_at desc limit 1;

  if v_diag.metric_key is null then
    select ss.rolling_score,ss.confidence,ss.sample_size,c.id competency_id,c.code competency_code,c.name competency_name
      into v_perf
    from public.performance_skill_state ss join public.performance_competencies c on c.id=ss.competency_id
    where ss.organization_id=p_organization_id and ss.user_id=p_user_id and c.active
    order by ss.rolling_score asc,ss.confidence desc,ss.last_observed_at desc nulls last limit 1;
    if v_perf.competency_id is null then return null; end if;
  else
    select ss.rolling_score,ss.confidence,ss.sample_size,c.id competency_id,c.code competency_code,c.name competency_name
      into v_perf
    from public.performance_competencies c
    left join public.performance_skill_state ss on ss.competency_id=c.id and ss.organization_id=p_organization_id and ss.user_id=p_user_id
    where c.id=v_diag.competency_id limit 1;
  end if;

  v_skill_key := case v_perf.competency_code
    when 'attachment' then 'attach_selling' when 'closing' then 'closing'
    when 'communication' then 'active_listening' when 'discovery' then 'discovery'
    when 'objection_handling' then 'objection_handling' when 'process_discipline' then 'follow_up'
    when 'product_knowledge' then 'product_knowledge' when 'recommendation' then 'solution_matching'
    when 'trust' then 'rapport' when 'value_building' then 'value_communication'
    else v_perf.competency_code end;

  select s.id,s.skill_key,s.name into v_skill from public.ai_skill_definitions s where s.active and s.skill_key=v_skill_key limit 1;
  if v_skill.id is null then return null; end if;

  v_difficulty := case when coalesce(v_perf.rolling_score,50)<45 then 2 when coalesce(v_perf.rolling_score,50)<60 then 4 when coalesce(v_perf.rolling_score,50)<75 then 6 when coalesce(v_perf.rolling_score,50)<88 then 8 else 10 end;
  select s.id,s.title,s.difficulty into v_scenario from public.ai_scenario_definitions s
  where s.active and (s.organization_id is null or s.organization_id=p_organization_id) and s.target_skills ? v_skill.skill_key
  order by abs(s.difficulty-v_difficulty),case when s.organization_id=p_organization_id then 0 else 1 end,s.difficulty desc limit 1;

  if v_diag.metric_key is not null then
    v_insight := format('%s is below target (%s vs %s). Performance Brain links the gap most strongly to %s. Sales DNA is %s/100 with %s confidence across %s observations. %s',v_diag.metric_key,v_diag.actual_value,v_diag.target_value,v_perf.competency_name,coalesce(round(v_perf.rolling_score,1)::text,'baseline'),coalesce(round(v_perf.confidence*100)::text||'%','low'),coalesce(v_perf.sample_size,0),coalesce(v_diag.rationale,''));
  else
    v_insight := format('Performance Brain identifies %s as the current coaching priority at %s/100. Today''s work targets that behaviour directly.',v_perf.competency_name,coalesce(round(v_perf.rolling_score,1)::text,'baseline'));
  end if;

  insert into public.ai_coaching_interventions(organization_id,user_id,status,trigger_type,metric_key,skill_id,diagnosis,evidence,baseline_value,target_value,prescribed_scenario_id,due_at)
  values(p_organization_id,p_user_id,'recommended',case when v_diag.metric_key is null then 'performance_brain' else 'metric_gap' end,v_diag.metric_key,v_skill.id,v_insight,
    jsonb_strip_nulls(jsonb_build_object('source','performance_brain','competency_code',v_perf.competency_code,'competency_name',v_perf.competency_name,'sales_dna_score',v_perf.rolling_score,'confidence',v_perf.confidence,'sample_size',v_perf.sample_size,'causal_weight',v_diag.causal_weight,'target_gap_pct',v_diag.target_gap_pct,'recommended_difficulty',v_difficulty)),
    coalesce(v_diag.actual_value,v_perf.rolling_score),coalesce(v_diag.target_value,80),v_scenario.id,(p_focus_date+7)::timestamptz)
  returning id into v_intervention;

  insert into public.ai_intervention_steps(intervention_id,step_order,step_type,title,resource_ref,target_score,metadata) values
    (v_intervention,1,'lesson',format('Micro-training: %s',v_skill.name),format('skill:%s',v_skill.skill_key),null,jsonb_build_object('source','performance_brain','competency_code',v_perf.competency_code)),
    (v_intervention,2,'roleplay',coalesce(format('Beat the Bot: %s',v_scenario.title),'Beat the Bot targeted practice'),case when v_scenario.id is not null then 'scenario:'||v_scenario.id::text end,80,jsonb_build_object('difficulty',v_difficulty,'competency_code',v_perf.competency_code)),
    (v_intervention,3,'floor_challenge',format('Live floor challenge: practice %s five times',v_skill.name),format('skill:%s',v_skill.skill_key),null,jsonb_build_object('repeat_count',5,'competency_code',v_perf.competency_code)),
    (v_intervention,4,'review','End-of-day reflection and 7-day performance recheck',case when v_diag.metric_key is not null then 'metric:'||v_diag.metric_key else 'competency:'||v_perf.competency_code end,null,jsonb_build_object('baseline',coalesce(v_diag.actual_value,v_perf.rolling_score),'target',coalesce(v_diag.target_value,80)));

  insert into public.daily_coaching_focus(organization_id,user_id,focus_date,primary_kpi_name,previous_score,target_score,insight,intervention_id,skill_id,prescribed_scenario_id)
  values(p_organization_id,p_user_id,p_focus_date,coalesce(v_diag.metric_key,v_perf.competency_name),coalesce(v_diag.actual_value,v_perf.rolling_score),coalesce(v_diag.target_value,80),v_insight,v_intervention,v_skill.id,v_scenario.id)
  on conflict(organization_id,user_id,focus_date) do update set primary_kpi_name=excluded.primary_kpi_name,previous_score=excluded.previous_score,target_score=excluded.target_score,insight=excluded.insight,intervention_id=excluded.intervention_id,skill_id=excluded.skill_id,prescribed_scenario_id=excluded.prescribed_scenario_id;

  select coalesce(items,'[]'::jsonb) into v_existing_items from public.crm_daily_five where organization_id=p_organization_id and user_id=p_user_id and work_date=p_focus_date;
  select coalesce(jsonb_agg(q.value order by q.ord),'[]'::jsonb) into v_retained_items
  from (select x.value,x.ord from jsonb_array_elements(v_existing_items) with ordinality x(value,ord) where coalesce(x.value->>'type','crm') <> 'coaching' order by x.ord limit 2) q;

  v_coaching_items := jsonb_build_array(
    jsonb_build_object('type','coaching','step_order',1,'action','Micro-training','title',format('Learn: %s',v_skill.name),'reason','Performance Brain coaching prescription','intervention_id',v_intervention,'resource_ref',format('skill:%s',v_skill.skill_key),'completed',false),
    jsonb_build_object('type','coaching','step_order',2,'action','Beat the Bot','title',coalesce(v_scenario.title,'Targeted roleplay'),'reason',format('Practice %s at the right difficulty',v_perf.competency_name),'intervention_id',v_intervention,'resource_ref',case when v_scenario.id is not null then 'scenario:'||v_scenario.id::text end,'completed',false),
    jsonb_build_object('type','coaching','step_order',3,'action','Floor challenge','title',format('Use %s with 5 live customers',v_skill.name),'reason','Transfer practice to the sales floor','intervention_id',v_intervention,'resource_ref',format('skill:%s',v_skill.skill_key),'completed',false));

  insert into public.crm_daily_five(organization_id,user_id,work_date,items,completed_count,total_count,generated_at)
  values(p_organization_id,p_user_id,p_focus_date,v_coaching_items||v_retained_items,0,jsonb_array_length(v_coaching_items||v_retained_items),now())
  on conflict(organization_id,user_id,work_date) do update set items=excluded.items,total_count=excluded.total_count,generated_at=excluded.generated_at,updated_at=now();

  return v_intervention;
end;$function$;

revoke all on function public.ai_generate_daily_coaching_focus(uuid,uuid,date) from public,anon;
grant execute on function public.ai_generate_daily_coaching_focus(uuid,uuid,date) to authenticated,service_role;
