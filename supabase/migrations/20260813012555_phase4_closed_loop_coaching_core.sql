create table if not exists public.ai_intervention_evaluations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  intervention_id uuid not null unique references public.ai_coaching_interventions(id) on delete cascade,
  recommendation_id uuid references public.intelligence_recommendations(id) on delete set null,
  metric_key text,
  baseline_value numeric,
  target_value numeric,
  observed_value numeric,
  delta numeric,
  success boolean,
  status text not null default 'pending' check (status in ('pending','due','measured','insufficient_data','cancelled')),
  baseline_observed_at timestamptz,
  evaluation_due_at timestamptz,
  measured_at timestamptz,
  measurement_source text,
  outcome_id uuid references public.intelligence_outcomes(id) on delete set null,
  evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_intervention_evaluations enable row level security;
revoke all on public.ai_intervention_evaluations from anon, authenticated;
grant all on public.ai_intervention_evaluations to service_role;

alter table public.ai_coaching_interventions
  add column if not exists recommendation_id uuid references public.intelligence_recommendations(id) on delete set null,
  add column if not exists evaluation_id uuid references public.ai_intervention_evaluations(id) on delete set null;

create index if not exists ai_intervention_evaluations_org_due_idx on public.ai_intervention_evaluations(organization_id,status,evaluation_due_at);
create index if not exists ai_coaching_interventions_org_user_status_idx on public.ai_coaching_interventions(organization_id,user_id,status,created_at desc);
create index if not exists ai_intervention_steps_status_idx on public.ai_intervention_steps(intervention_id,status,step_order);

insert into public.platform_canonical_event_types(key,name,description,subject_entity_type,outcome_relevant,coaching_relevant,active,metadata)
values
 ('coaching.intervention_created','Coaching intervention created','Closed-loop coaching intervention prescribed','coaching',false,true,true,'{"phase":4}'::jsonb),
 ('coaching.step_completed','Coaching step completed','A prescribed coaching intervention step was completed','coaching',true,true,true,'{"phase":4}'::jsonb),
 ('coaching.intervention_completed','Coaching intervention completed','All required intervention steps were completed','coaching',true,true,true,'{"phase":4}'::jsonb),
 ('coaching.outcome_measured','Coaching outcome measured','Post-intervention performance was measured against baseline','coaching',true,true,true,'{"phase":4}'::jsonb)
on conflict(key) do update set active=true, coaching_relevant=true, metadata=coalesce(public.platform_canonical_event_types.metadata,'{}'::jsonb)||excluded.metadata;

create or replace function public.phase4_ensure_intervention_recommendation(p_intervention_id uuid)
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_i public.ai_coaching_interventions%rowtype; v_rec uuid; v_entity uuid;
begin
  select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if auth.uid() is not null and not public.is_org_member(v_i.organization_id) then raise exception 'Not authorized'; end if;
  if v_i.recommendation_id is not null then return v_i.recommendation_id; end if;
  select intelligence_entity_id into v_entity from public.platform_identity_links
  where organization_id=v_i.organization_id and entity_type='employee' and canonical_id=v_i.user_id and intelligence_entity_id is not null
  order by verified_at desc nulls last,last_seen_at desc limit 1;
  v_rec:=public.intelligence_record_recommendation(v_i.organization_id,'coaching_intervention','employee',v_i.user_id::text,v_i.diagnosis,coalesce(v_i.metric_key,'performance_brain'),v_entity,case when (v_i.evidence->>'confidence') ~ '^[0-9.]+$' then least(1,greatest(0,(v_i.evidence->>'confidence')::numeric)) else null end,jsonb_build_object('intervention_id',v_i.id,'evidence',v_i.evidence,'baseline',v_i.baseline_value,'target',v_i.target_value,'skill_id',v_i.skill_id,'scenario_id',v_i.prescribed_scenario_id),'[]'::jsonb,'phase4_closed_loop',v_i.id::text);
  update public.ai_coaching_interventions set recommendation_id=v_rec,updated_at=now() where id=v_i.id;
  return v_rec;
end $$;

create or replace function public.phase4_generate_coaching(p_organization_id uuid,p_user_id uuid,p_focus_date date default current_date)
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_intervention uuid; v_rec uuid; v_eval uuid; v_i public.ai_coaching_interventions%rowtype;
begin
  if auth.uid() is not null then
    if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
    if p_user_id<>auth.uid() and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized to generate coaching for this user'; end if;
  end if;
  v_intervention:=public.ai_generate_daily_coaching_focus(p_organization_id,p_user_id,p_focus_date);
  if v_intervention is null then return null; end if;
  v_rec:=public.phase4_ensure_intervention_recommendation(v_intervention);
  select * into v_i from public.ai_coaching_interventions where id=v_intervention;
  insert into public.ai_intervention_evaluations(organization_id,intervention_id,recommendation_id,metric_key,baseline_value,target_value,status,baseline_observed_at,evaluation_due_at,evidence)
  values(v_i.organization_id,v_i.id,v_rec,v_i.metric_key,v_i.baseline_value,v_i.target_value,'pending',v_i.created_at,coalesce(v_i.due_at,v_i.created_at+interval '7 days'),jsonb_build_object('trigger_type',v_i.trigger_type,'skill_id',v_i.skill_id))
  on conflict(intervention_id) do update set recommendation_id=excluded.recommendation_id,metric_key=excluded.metric_key,baseline_value=excluded.baseline_value,target_value=excluded.target_value,evaluation_due_at=excluded.evaluation_due_at,updated_at=now()
  returning id into v_eval;
  update public.ai_coaching_interventions set evaluation_id=v_eval where id=v_intervention;
  return v_intervention;
end $$;

create or replace function public.phase4_complete_step(p_intervention_id uuid,p_step_order integer,p_completion_ref uuid default null,p_score numeric default null,p_metadata jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_i public.ai_coaching_interventions%rowtype; v_step public.ai_intervention_steps%rowtype; v_remaining int; v_completed boolean;
begin
  select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if auth.uid() is not null and auth.uid()<>v_i.user_id and not public.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
  update public.ai_intervention_steps set status='completed',completion_ref=coalesce(p_completion_ref,completion_ref),completed_at=coalesce(completed_at,now()),metadata=coalesce(metadata,'{}'::jsonb)||coalesce(p_metadata,'{}'::jsonb)||jsonb_strip_nulls(jsonb_build_object('score',p_score)),updated_at=now()
  where intervention_id=p_intervention_id and step_order=p_step_order returning * into v_step;
  if v_step.id is null then raise exception 'Intervention step not found'; end if;
  update public.ai_coaching_interventions set status=case when status='recommended' then 'in_progress' else status end,started_at=coalesce(started_at,now()),updated_at=now() where id=p_intervention_id;
  select count(*) into v_remaining from public.ai_intervention_steps where intervention_id=p_intervention_id and status not in ('completed','skipped');
  v_completed:=v_remaining=0;
  if v_completed then
    update public.ai_coaching_interventions set status='completed',completed_at=coalesce(completed_at,now()),updated_at=now() where id=p_intervention_id;
    update public.ai_intervention_evaluations set status=case when evaluation_due_at<=now() then 'due' else 'pending' end,updated_at=now() where intervention_id=p_intervention_id;
  end if;
  return jsonb_build_object('intervention_id',p_intervention_id,'step_order',p_step_order,'step_status','completed','intervention_completed',v_completed,'remaining_steps',v_remaining);
end $$;

create or replace function public.phase4_evaluate_intervention(p_intervention_id uuid,p_force boolean default false)
returns jsonb language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_i public.ai_coaching_interventions%rowtype; v_e public.ai_intervention_evaluations%rowtype; v_current numeric; v_current_at timestamptz; v_delta numeric; v_success boolean; v_outcome uuid; v_rec uuid; v_source text;
begin
  select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if auth.uid() is not null and not public.is_org_member(v_i.organization_id) then raise exception 'Not authorized'; end if;
  if auth.uid() is not null and auth.uid()<>v_i.user_id and not public.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
  select * into v_e from public.ai_intervention_evaluations where intervention_id=p_intervention_id;
  if v_e.id is null then perform public.phase4_generate_coaching(v_i.organization_id,v_i.user_id,current_date); select * into v_e from public.ai_intervention_evaluations where intervention_id=p_intervention_id; end if;
  if not p_force and v_e.evaluation_due_at>now() then return jsonb_build_object('status','not_due','evaluation_due_at',v_e.evaluation_due_at); end if;
  if v_i.metric_key is not null then select d.actual_value,d.computed_at into v_current,v_current_at from public.performance_metric_diagnostics d where d.organization_id=v_i.organization_id and d.user_id=v_i.user_id and d.metric_key=v_i.metric_key and d.actual_value is not null order by d.computed_at desc limit 1; v_source:='performance_metric_diagnostics'; end if;
  if v_current is null and v_i.skill_id is not null then
    select ss.rolling_score,ss.last_observed_at into v_current,v_current_at from public.ai_skill_definitions s join public.performance_competencies c on c.code=case s.skill_key when 'attach_selling' then 'attachment' when 'active_listening' then 'communication' when 'solution_matching' then 'recommendation' when 'value_communication' then 'value_building' else s.skill_key end join public.performance_skill_state ss on ss.competency_id=c.id and ss.organization_id=v_i.organization_id and ss.user_id=v_i.user_id where s.id=v_i.skill_id order by ss.last_observed_at desc nulls last limit 1; v_source:='performance_skill_state';
  end if;
  if v_current is null then update public.ai_intervention_evaluations set status='insufficient_data',measured_at=now(),measurement_source=coalesce(v_source,'none'),evidence=evidence||jsonb_build_object('reason','No post-intervention metric available'),updated_at=now() where id=v_e.id; return jsonb_build_object('status','insufficient_data'); end if;
  v_delta:=case when v_i.baseline_value is null then null else v_current-v_i.baseline_value end;
  v_success:=case when v_i.target_value is not null then v_current>=v_i.target_value when v_delta is not null then v_delta>0 else null end;
  v_rec:=coalesce(v_i.recommendation_id,public.phase4_ensure_intervention_recommendation(v_i.id));
  v_outcome:=public.intelligence_record_outcome(v_rec,'coaching_effectiveness',v_success,v_current,case when v_success is true then 'improved' when v_success is false then 'not_yet_improved' else 'measured' end,1,jsonb_build_object('intervention_id',v_i.id,'baseline',v_i.baseline_value,'target',v_i.target_value,'delta',v_delta,'measurement_source',v_source,'measured_at',v_current_at),'phase4_closed_loop',v_i.id::text,now());
  update public.ai_intervention_evaluations set observed_value=v_current,delta=v_delta,success=v_success,status='measured',measured_at=now(),measurement_source=v_source,outcome_id=v_outcome,evidence=evidence||jsonb_build_object('metric_observed_at',v_current_at),updated_at=now() where id=v_e.id;
  update public.ai_coaching_interventions set outcome_value=v_current,outcome_delta=v_delta,outcome_metadata=coalesce(outcome_metadata,'{}'::jsonb)||jsonb_build_object('success',v_success,'outcome_id',v_outcome,'measurement_source',v_source),updated_at=now() where id=v_i.id;
  update public.intelligence_recommendations set status=case when status in ('generated','presented') then 'accepted' else status end,resolved_at=coalesce(resolved_at,now()),updated_at=now() where id=v_rec;
  return jsonb_build_object('status','measured','baseline',v_i.baseline_value,'target',v_i.target_value,'observed',v_current,'delta',v_delta,'success',v_success,'outcome_id',v_outcome);
end $$;

create or replace function public.phase4_generate_org_coaching(p_organization_id uuid,p_focus_date date default current_date,p_limit integer default 25)
returns table(user_id uuid,intervention_id uuid) language plpgsql security definer set search_path='public','pg_temp' as $$
declare r record; v_id uuid;
begin
  if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  for r in select distinct d.user_id,max(d.target_gap_pct) gap from public.performance_metric_diagnostics d join public.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active' where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value group by d.user_id order by gap desc nulls last limit greatest(1,least(coalesce(p_limit,25),100)) loop
    v_id:=public.phase4_generate_coaching(p_organization_id,r.user_id,p_focus_date); if v_id is not null then user_id:=r.user_id; intervention_id:=v_id; return next; end if;
  end loop; return;
end $$;

create or replace function public.phase4_coaching_dashboard(p_organization_id uuid)
returns jsonb language sql stable security definer set search_path='public','pg_temp' as $$
select case when exists(select 1 from public.organization_members m where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.status='active') then jsonb_build_object(
'active_interventions',(select count(*) from public.ai_coaching_interventions i where i.organization_id=p_organization_id and i.status in ('recommended','assigned','in_progress')),
'completed_interventions',(select count(*) from public.ai_coaching_interventions i where i.organization_id=p_organization_id and i.status='completed'),
'evaluations_due',(select count(*) from public.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status in ('pending','due') and e.evaluation_due_at<=now()),
'measured_outcomes',(select count(*) from public.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status='measured'),
'successful_outcomes',(select count(*) from public.ai_intervention_evaluations e where e.organization_id=p_organization_id and e.status='measured' and e.success is true),
'effectiveness_pct',(select case when count(*) filter(where e.status='measured' and e.success is not null)>0 then round(100.0*count(*) filter(where e.status='measured' and e.success is true)/count(*) filter(where e.status='measured' and e.success is not null),2) end from public.ai_intervention_evaluations e where e.organization_id=p_organization_id),
'latest',(select coalesce(jsonb_agg(x order by x.created_at desc),'[]'::jsonb) from (select i.id,i.user_id,i.status,i.metric_key,i.diagnosis,i.baseline_value,i.target_value,i.outcome_value,i.outcome_delta,i.created_at,e.status evaluation_status,e.evaluation_due_at,e.success from public.ai_coaching_interventions i left join public.ai_intervention_evaluations e on e.intervention_id=i.id where i.organization_id=p_organization_id order by i.created_at desc limit 50)x)) else null end;
$$;

revoke all on function public.phase4_ensure_intervention_recommendation(uuid) from public,anon,authenticated;
revoke all on function public.phase4_generate_coaching(uuid,uuid,date) from public,anon;
revoke all on function public.phase4_complete_step(uuid,integer,uuid,numeric,jsonb) from public,anon;
revoke all on function public.phase4_evaluate_intervention(uuid,boolean) from public,anon;
revoke all on function public.phase4_generate_org_coaching(uuid,date,integer) from public,anon;
revoke all on function public.phase4_coaching_dashboard(uuid) from public,anon;
grant execute on function public.phase4_generate_coaching(uuid,uuid,date) to authenticated,service_role;
grant execute on function public.phase4_complete_step(uuid,integer,uuid,numeric,jsonb) to authenticated,service_role;
grant execute on function public.phase4_evaluate_intervention(uuid,boolean) to authenticated,service_role;
grant execute on function public.phase4_generate_org_coaching(uuid,date,integer) to authenticated,service_role;
grant execute on function public.phase4_coaching_dashboard(uuid) to authenticated,service_role;
grant execute on function public.phase4_ensure_intervention_recommendation(uuid) to service_role;
