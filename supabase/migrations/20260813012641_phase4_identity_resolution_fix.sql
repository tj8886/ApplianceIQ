create or replace function public.phase4_ensure_intervention_recommendation(p_intervention_id uuid)
returns uuid
language plpgsql
security definer
set search_path='public','pg_temp'
as $$
declare
  v_i public.ai_coaching_interventions%rowtype;
  v_rec uuid;
  v_entity uuid;
begin
  select * into v_i from public.ai_coaching_interventions where id=p_intervention_id;
  if v_i.id is null then raise exception 'Intervention not found'; end if;
  if auth.uid() is not null and not public.is_org_member(v_i.organization_id) then raise exception 'Not authorized'; end if;
  if v_i.recommendation_id is not null then return v_i.recommendation_id; end if;
  select intelligence_entity_id into v_entity
  from public.platform_identity_links
  where organization_id=v_i.organization_id and entity_type='employee' and canonical_id=v_i.user_id and intelligence_entity_id is not null
  order by is_primary desc, verified_at desc nulls last, confidence desc nulls last, last_seen_at desc limit 1;
  v_rec := public.intelligence_record_recommendation(v_i.organization_id,'coaching_intervention','employee',v_i.user_id::text,v_i.diagnosis,coalesce(v_i.metric_key,'performance_brain'),v_entity,case when (v_i.evidence->>'confidence') ~ '^[0-9.]+$' then least(1,greatest(0,(v_i.evidence->>'confidence')::numeric)) else null end,jsonb_build_object('intervention_id',v_i.id,'evidence',v_i.evidence,'baseline',v_i.baseline_value,'target',v_i.target_value,'skill_id',v_i.skill_id,'scenario_id',v_i.prescribed_scenario_id),'[]'::jsonb,'phase4_closed_loop',v_i.id::text);
  update public.ai_coaching_interventions set recommendation_id=v_rec,updated_at=now() where id=v_i.id;
  return v_rec;
end $$;
revoke all on function public.phase4_ensure_intervention_recommendation(uuid) from public,anon,authenticated;
grant execute on function public.phase4_ensure_intervention_recommendation(uuid) to service_role;
