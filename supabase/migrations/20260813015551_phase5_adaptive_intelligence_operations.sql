insert into public.platform_canonical_event_types(key,name,description,subject_entity_type,outcome_relevant,coaching_relevant,active,metadata)
values
 ('coaching.adaptation_selected','Adaptive coaching selected','Phase 5 selected a personalized coaching strategy and difficulty','coaching',false,true,true,'{"phase":5}'::jsonb),
 ('coaching.strategy_learned','Adaptive strategy learned','Phase 5 incorporated a measured coaching outcome into strategy performance','coaching',true,true,true,'{"phase":5}'::jsonb)
on conflict(key) do update set active=true,coaching_relevant=true,metadata=coalesce(public.platform_canonical_event_types.metadata,'{}'::jsonb)||excluded.metadata;

create or replace function public.phase5_generate_org_adaptive_coaching(p_organization_id uuid,p_focus_date date default current_date,p_limit integer default 25)
returns table(user_id uuid,intervention_id uuid,adaptation jsonb) language plpgsql security definer set search_path='public','pg_temp' as $$
declare r record; v_result jsonb;
begin
 if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 for r in
  select d.user_id,max(case when d.actual_value<d.target_value then case when d.target_value=0 then abs(d.target_value-d.actual_value) else 100.0*(d.target_value-d.actual_value)/abs(d.target_value) end end) severity
  from public.performance_metric_diagnostics d join public.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active'
  where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value
  group by d.user_id order by severity desc nulls last limit greatest(1,least(coalesce(p_limit,25),100))
 loop
  v_result:=public.phase5_generate_adaptive_coaching(p_organization_id,r.user_id,p_focus_date);
  if v_result->>'status'='created' then user_id:=r.user_id; intervention_id:=(v_result->>'intervention_id')::uuid; adaptation:=v_result->'adaptation'; return next; end if;
 end loop;
 return;
end $$;

create or replace function public.phase5_manager_recommendations(p_organization_id uuid,p_limit integer default 25)
returns jsonb language plpgsql stable security definer set search_path='public','pg_temp' as $$
begin
 if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 return coalesce((select jsonb_agg(x order by x.priority_score desc,x.user_id) from (
  select p.user_id,
    round((case p.coaching_intensity when 'intensive' then 40 when 'standard' then 20 else 5 end
      + case when p.recent_success_rate is null then 10 when p.recent_success_rate<40 then 35 when p.recent_success_rate<60 then 20 else 0 end
      + case when p.learning_velocity is not null and p.learning_velocity<0 then 20 else 0 end
      + case when exists(select 1 from public.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 25 else 0 end)::numeric,2) priority_score,
    p.coaching_intensity,p.challenge_level,p.recent_success_rate,p.learning_velocity,p.confidence,p.preferred_strategy,
    case
      when exists(select 1 from public.ai_coaching_interventions i where i.organization_id=p.organization_id and i.user_id=p.user_id and i.status in('recommended','assigned','in_progress') and i.due_at<now()) then 'Intervention overdue: manager follow-up recommended'
      when p.recent_success_rate is not null and p.recent_success_rate<40 then 'Low coaching effectiveness: review strategy and observe live behavior'
      when p.learning_velocity is not null and p.learning_velocity<0 then 'Performance is moving backward: increase observation and coaching intensity'
      when p.coaching_intensity='intensive' then 'Intensive coaching profile: schedule manager touchpoint'
      else 'Continue adaptive coaching and collect more evidence' end recommended_action,
    (select count(*) from public.ai_adaptive_coaching_decisions d where d.organization_id=p.organization_id and d.user_id=p.user_id and d.learned_at is not null) learned_interventions
  from public.ai_adaptive_coaching_profiles p where p.organization_id=p_organization_id
  order by priority_score desc limit greatest(1,least(coalesce(p_limit,25),100))
 )x),'[]'::jsonb);
end $$;

revoke all on function public.phase5_generate_org_adaptive_coaching(uuid,date,integer),public.phase5_manager_recommendations(uuid,integer) from public,anon;
grant execute on function public.phase5_generate_org_adaptive_coaching(uuid,date,integer),public.phase5_manager_recommendations(uuid,integer) to authenticated,service_role;
