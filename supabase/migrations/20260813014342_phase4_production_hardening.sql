create index if not exists ai_intervention_evaluations_recommendation_id_idx on public.ai_intervention_evaluations(recommendation_id);
create index if not exists ai_intervention_evaluations_outcome_id_idx on public.ai_intervention_evaluations(outcome_id);
create index if not exists ai_coaching_interventions_recommendation_id_idx on public.ai_coaching_interventions(recommendation_id);
create index if not exists ai_coaching_interventions_evaluation_id_idx on public.ai_coaching_interventions(evaluation_id);

create or replace function public.phase4_attach_evaluation(p_intervention_id uuid)
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_i public.ai_coaching_interventions%rowtype; v_rec uuid; v_eval uuid;
begin
 select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
 if v_i.id is null then raise exception 'Intervention not found'; end if;
 if auth.uid() is not null and auth.uid()<>v_i.user_id and not public.is_org_admin(v_i.organization_id) then raise exception 'Not authorized'; end if;
 v_rec:=public.phase4_ensure_intervention_recommendation(v_i.id);
 insert into public.ai_intervention_evaluations(organization_id,intervention_id,recommendation_id,metric_key,baseline_value,target_value,status,baseline_observed_at,evaluation_due_at,evidence)
 values(v_i.organization_id,v_i.id,v_rec,v_i.metric_key,v_i.baseline_value,v_i.target_value,'pending',v_i.created_at,coalesce(v_i.due_at,v_i.created_at+interval '7 days'),jsonb_build_object('trigger_type',v_i.trigger_type,'skill_id',v_i.skill_id))
 on conflict(intervention_id) do update set recommendation_id=excluded.recommendation_id,metric_key=excluded.metric_key,baseline_value=excluded.baseline_value,target_value=excluded.target_value,evaluation_due_at=excluded.evaluation_due_at,updated_at=now()
 returning id into v_eval;
 update public.ai_coaching_interventions set evaluation_id=v_eval,updated_at=now() where id=v_i.id;
 return v_eval;
end $$;
revoke all on function public.phase4_attach_evaluation(uuid) from public,anon,authenticated;
grant execute on function public.phase4_attach_evaluation(uuid) to service_role;

create or replace function public.phase4_generate_coaching(p_organization_id uuid,p_user_id uuid,p_focus_date date default current_date)
returns uuid language plpgsql security definer set search_path='public','pg_temp' as $$
declare v_intervention uuid;
begin
 if auth.uid() is not null then
  if not public.is_org_member(p_organization_id) then raise exception 'Not a member of this organization'; end if;
  if p_user_id<>auth.uid() and not public.is_org_admin(p_organization_id) then raise exception 'Not authorized to generate coaching for this user'; end if;
 end if;
 v_intervention:=public.ai_generate_daily_coaching_focus(p_organization_id,p_user_id,p_focus_date);
 if v_intervention is null then return null; end if;
 perform public.phase4_attach_evaluation(v_intervention);
 return v_intervention;
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
 if v_e.id is null then perform public.phase4_attach_evaluation(p_intervention_id); select * into v_e from public.ai_intervention_evaluations where intervention_id=p_intervention_id; end if;
 if not p_force and v_e.evaluation_due_at>now() then return jsonb_build_object('status','not_due','evaluation_due_at',v_e.evaluation_due_at); end if;
 if v_i.metric_key is not null then select d.actual_value,d.computed_at into v_current,v_current_at from public.performance_metric_diagnostics d where d.organization_id=v_i.organization_id and d.user_id=v_i.user_id and d.metric_key=v_i.metric_key and d.actual_value is not null order by d.computed_at desc limit 1; v_source:='performance_metric_diagnostics'; end if;
 if v_current is null and v_i.skill_id is not null then select ss.rolling_score,ss.last_observed_at into v_current,v_current_at from public.ai_skill_definitions s join public.performance_competencies c on c.code=case s.skill_key when 'attach_selling' then 'attachment' when 'active_listening' then 'communication' when 'solution_matching' then 'recommendation' when 'value_communication' then 'value_building' else s.skill_key end join public.performance_skill_state ss on ss.competency_id=c.id and ss.organization_id=v_i.organization_id and ss.user_id=v_i.user_id where s.id=v_i.skill_id order by ss.last_observed_at desc nulls last limit 1; v_source:='performance_skill_state'; end if;
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
 for r in select d.user_id,max(case when d.actual_value<d.target_value then case when d.target_value=0 then abs(d.target_value-d.actual_value) else 100.0*(d.target_value-d.actual_value)/abs(d.target_value) end end) gap_severity_pct from public.performance_metric_diagnostics d join public.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active' where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value group by d.user_id order by gap_severity_pct desc nulls last limit greatest(1,least(coalesce(p_limit,25),100)) loop
  v_id:=public.phase4_generate_coaching(p_organization_id,r.user_id,p_focus_date); if v_id is not null then user_id:=r.user_id; intervention_id:=v_id; return next; end if;
 end loop; return;
end $$;

create or replace function public.phase4_evaluate_all_due(p_limit_per_org integer default 100)
returns table(organization_id uuid,intervention_id uuid,result jsonb) language plpgsql security definer set search_path='public','pg_temp' as $$
declare org record; r record;
begin
 if auth.uid() is not null then raise exception 'Service execution only'; end if;
 for org in select distinct e.organization_id from public.ai_intervention_evaluations e join public.ai_coaching_interventions i on i.id=e.intervention_id where e.status in ('pending','due') and e.evaluation_due_at<=now() and i.status='completed' loop
  for r in select * from public.phase4_evaluate_due_org(org.organization_id,p_limit_per_org) loop organization_id:=org.organization_id; intervention_id:=r.intervention_id; result:=r.result; return next; end loop;
 end loop; return;
end $$;
revoke all on function public.phase4_evaluate_all_due(integer) from public,anon,authenticated;
grant execute on function public.phase4_evaluate_all_due(integer) to service_role;

do $$ declare v_jobid bigint; begin
 select jobid into v_jobid from cron.job where jobname='phase4-evaluate-due-interventions';
 if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
 perform cron.schedule('phase4-evaluate-due-interventions','17 * * * *','select * from public.phase4_evaluate_all_due(100);');
end $$;