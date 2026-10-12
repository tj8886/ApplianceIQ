CREATE OR REPLACE FUNCTION tj_private.phase7_seed_default_policies(p_organization_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_actor uuid:=tj_private.current_source_user_id(); v_count integer;
begin
  if v_actor is not null and not tj.is_org_admin(p_organization_id) then raise exception 'Organization admin required'; end if;
  -- Serialize seeds per organization, including the nullable module key.
  perform pg_advisory_xact_lock(hashtextextended('phase7-policy-seed:'||p_organization_id::text,0));
  insert into tj.phase7_automation_policies(organization_id,action_type,action_module,mode,created_by,updated_by)
  select p_organization_id,v.action_type,v.action_module,v.mode,v_actor,v_actor
  from (values
    ('performance_gap','ai-coach','approval_required'),
    ('performance_gap','academy','approval_required'),
    ('crm_pipeline','crm','approval_required'),
    ('manager_task',null,'auto_execute'),
    ('customer_outreach','crm','disabled')
  ) v(action_type,action_module,mode)
  where not exists (
    select 1 from tj.phase7_automation_policies p
    where p.organization_id=p_organization_id and p.action_type=v.action_type
      and p.action_module is not distinct from v.action_module
  )
  on conflict(organization_id,action_type,action_module) do nothing;
  get diagnostics v_count=row_count;
  return v_count;
end $function$;

REVOKE ALL ON FUNCTION tj_private.phase7_seed_default_policies(uuid) FROM PUBLIC, anon;
