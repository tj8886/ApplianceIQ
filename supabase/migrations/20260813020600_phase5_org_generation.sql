create or replace function public.phase5_generate_org_adaptive_coaching(p_organization_id uuid,p_focus_date date default current_date,p_limit integer default 25)
returns table(user_id uuid,intervention_id uuid,adaptation jsonb)
language plpgsql security definer set search_path='public','pg_temp' as $$
declare r record; v_result jsonb;
begin
 if auth.uid() is not null and not public.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
 for r in
  select d.user_id,max(case when d.actual_value<d.target_value then case when d.target_value=0 then abs(d.target_value-d.actual_value) else 100.0*(d.target_value-d.actual_value)/abs(d.target_value) end end) severity
  from public.performance_metric_diagnostics d
  join public.organization_members m on m.organization_id=d.organization_id and m.user_id=d.user_id and m.status='active'
  where d.organization_id=p_organization_id and d.actual_value is not null and d.target_value is not null and d.actual_value<d.target_value
  group by d.user_id order by severity desc nulls last limit greatest(1,least(coalesce(p_limit,25),100))
 loop
  v_result:=public.phase5_generate_adaptive_coaching(p_organization_id,r.user_id,p_focus_date);
  if v_result->>'status'='created' then
   user_id:=r.user_id; intervention_id:=(v_result->>'intervention_id')::uuid; adaptation:=v_result->'adaptation'; return next;
  end if;
 end loop;
 return;
end $$;

revoke all on function public.phase5_generate_org_adaptive_coaching(uuid,date,integer) from public;
grant execute on function public.phase5_generate_org_adaptive_coaching(uuid,date,integer) to authenticated;
