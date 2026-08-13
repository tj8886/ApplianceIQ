update public.platform_canonical_event_types
set subject_entity_type='employee',metadata=coalesce(metadata,'{}'::jsonb)||'{"semantic_subject":"coaching"}'::jsonb
where key in ('coaching.intervention_created','coaching.step_completed','coaching.intervention_completed','coaching.outcome_measured');

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
    v_org:=new.organization_id; v_entity:=new.user_id; v_actor:=new.user_id; v_source_id:=new.id::text;
    v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.id,'employee_id',new.user_id,'status',new.status,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'skill_id',new.skill_id,'scenario_id',new.prescribed_scenario_id,'recommendation_id',new.recommendation_id));
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_steps' then
    if not (tg_op='UPDATE' and new.status='completed' and old.status is distinct from 'completed') then return new; end if;
    select organization_id,user_id into v_org,v_actor from public.ai_coaching_interventions where id=new.intervention_id;
    v_entity:=v_actor; v_source_id:=new.id::text; v_event:='coaching.step_completed';
    v_payload:=jsonb_build_object('intervention_id',new.intervention_id,'employee_id',v_actor,'step_id',new.id,'step_order',new.step_order,'step_type',new.step_type,'target_score',new.target_score,'metadata',new.metadata);
    v_dedupe:=v_event||':'||new.id::text;
  elsif tg_table_name='ai_intervention_evaluations' then
    if not (tg_op='UPDATE' and new.status='measured' and old.status is distinct from 'measured') then return new; end if;
    select user_id into v_actor from public.ai_coaching_interventions where id=new.intervention_id;
    v_org:=new.organization_id; v_entity:=v_actor; v_source_id:=new.id::text; v_event:='coaching.outcome_measured';
    v_payload:=jsonb_strip_nulls(jsonb_build_object('intervention_id',new.intervention_id,'employee_id',v_actor,'evaluation_id',new.id,'metric_key',new.metric_key,'baseline_value',new.baseline_value,'target_value',new.target_value,'observed_value',new.observed_value,'delta',new.delta,'success',new.success,'outcome_id',new.outcome_id,'measurement_source',new.measurement_source));
    v_dedupe:=v_event||':'||new.id::text;
  else return new; end if;
  perform public.platform_emit_intelligence_event(v_org,v_event,'phase4_closed_loop',v_source_id,'employee',v_entity,null,v_actor,null,null,v_dedupe,v_payload,now(),1,jsonb_build_object('phase',4,'semantic_subject','coaching','trigger_table',tg_table_name));
  return new;
end $$;
revoke all on function public.phase4_emit_coaching_event() from public,anon,authenticated;
grant execute on function public.phase4_emit_coaching_event() to service_role;
