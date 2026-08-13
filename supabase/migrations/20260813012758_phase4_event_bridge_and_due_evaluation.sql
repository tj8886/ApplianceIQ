create or replace function public.phase4_emit_coaching_event()
returns trigger
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare v_event text; v_org uuid; v_entity uuid; v_actor uuid; v_payload jsonb; v_source_id text; v_dedupe text;
begin
  if tg_table_name='ai_coaching_interventions' then
    if tg_op='INSERT' then v_event:='coaching.intervention_created';
    elsif tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed' then v_event:='coaching.intervention_completed';
    else return new; end if;
    v_org:=new.organization_id; v_entity:=new.id; v_actor:=new.user_id; v_source_id:=new.id::text;
    v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.id,'employee_id',new.user_id,'status',new.status,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'skill_id',new.skill_id,'scenario_id',new.prescribed_scenario_id,'recommendation_id',new.recommendation_id));
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_steps' then
    if not (tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed') then return new; end if;
    select organization_id,user_id into v_org,v_actor from public.ai_coaching_interventions where id=new.intervention_id;
    v_entity:=new.intervention_id; v_source_id:=new.id::text;
    v_event:='coaching.step_completed'; v_payload:=jsonb_build_object('intervention_id',new.intervention_id,'step_id',new.id,'step_order',new.step_order,'step_type',new.step_type,'target_score',new.target_score,'metadata',new.metadata);
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_evaluations' then
    if not (tg_op='UPDATE' and new.status='measured' and old.status is distinct from 'measured') then return new; end if;
    select user_id into v_actor from public.ai_coaching_interventions where id=new.intervention_id;
    v_org:=new.organization_id; v_entity:=new.intervention_id; v_source_id:=new.id::text;
    v_event:='coaching.outcome_measured'; v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.intervention_id,'evaluation_id',new.id,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'observed_value',new.observed_value,'delta',new.delta,'success',new.success,'outcome_id',new.outcome_id,'measurement_source',new.measurement_source));
    v_dedupe:=v_event||':'||new.id::text;
  else return new; end if;
  perform public.platform_emit_intelligence_event(v_org,v_event,'phase4_closed_loop',v_source_id,'coaching',v_entity,null,v_actor,null,null,v_dedupe,v_payload,now(),1,jsonb_build_object('phase',4,'trigger_table',tg_table_name));
  return new;
end $$;

revoke all on function public.phase4_emit_coaching_event() from public,anon,authenticated;
grant execute on function public.phase4_emit_coaching_event() to service_role;

drop trigger if exists phase4_intervention_event_bridge on public.ai_coaching_interventions;
create trigger phase4_intervention_event_bridge after insert or update of status on public.ai_coaching_interventions for each row execute function public.phase4_emit_coaching_event();
drop trigger if exists phase4_step_event_bridge on public.ai_intervention_steps;
create trigger phase4_step_event_bridge after update of status on public.ai_intervention_steps for each row execute function public.phase4_emit_coaching_event();
drop trigger if exists phase4_evaluation_event_bridge on public.ai_intervention_evaluations;
create trigger phase4_evaluation_event_bridge after update of status on public.ai_intervention_evaluations for each row execute function public.phase4_emit_coaching_event();

create or replace function public.phase4_evaluate_due_org(p_organization_id uuid,p_limit integer default 100)
returns table(intervention_id uuid,result jsonb)
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare r record;
begin
  if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  update public.ai_intervention_evaluations set status='due',updated_at=now() where organization_id=p_organization_id and status='pending' and evaluation_due_at<=now();
  for r in select e.intervention_id from public.ai_intervention_evaluations e join public.ai_coaching_interventions i on i.id=e.intervention_id where e.organization_id=p_organization_id and e.status='due' and i.status='completed' order by e.evaluation_due_at limit greatest(1,least(coalesce(p_limit,100),500)) loop
    intervention_id:=r.intervention_id; result:=public.phase4_evaluate_intervention(r.intervention_id,false); return next;
  end loop;
  return;
end $$;
revoke all on function public.phase4_evaluate_due_org(uuid,integer) from public,anon;
grant execute on function public.phase4_evaluate_due_org(uuid,integer) to authenticated,service_role;
