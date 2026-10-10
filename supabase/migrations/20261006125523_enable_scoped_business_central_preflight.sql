-- Read-only Business Central readiness; no token access, refresh or sync writes.
create function tj_private.business_central_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();c tj.platform_connector_connections%rowtype;
 action text;tenant uuid;credential_recorded boolean;environment text;company text;blockers jsonb:='[]';
begin
 if actor is null then raise exception using errcode='42501',message='connection_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('connection_id','organization_id','action','environment','company_id','sync_type','since'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 select * into c from tj.platform_connector_connections where id=(p_body->>'connection_id')::uuid;
 if c.id is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where m.organization_id=c.organization_id and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin') and o.status='active' and o.deleted_at is null)
  or (p_body ? 'organization_id' and (p_body->>'organization_id')::uuid<>c.organization_id) then raise exception using errcode='42501',message='connection_access_denied';end if;
 if not exists(select 1 from tj.platform_connectors p join tj.platform_connector_variants v on v.connector_id=p.id
  where p.id=c.connector_id and v.id=c.variant_id and p.key='microsoft_dynamics_365' and v.key='business_central') then raise exception using errcode='22023',message='not_business_central_connection';end if;
 action:=coalesce(p_body->>'action','sync');
 if action not in ('status','discover','sync') then raise exception using errcode='22023',message='invalid_action';end if;
 -- Review and private credential provenance must independently match the tenant organization.
 -- No imported reference, auth_metadata claim or mutable settings flag can establish approval.
 select r.tenant_id into tenant from tj_private.microsoft_oauth_review r join tj.organization_members m on m.user_id=r.approved_by and m.organization_id=r.organization_id
  where r.connection_id=c.id and r.organization_id=c.organization_id and r.expires_at>clock_timestamp() and m.status='active' and m.role in ('owner','admin','super_admin');
 select exists(select 1 from tj_private.microsoft_credentials k join vault.secrets s on s.id=k.secret_id
  where k.connection_id=c.id and k.organization_id=c.organization_id and k.secret_id::text=c.credential_ref) into credential_recorded;
 if tenant is null then blockers:=blockers||'"microsoft_destination_tenant_review_required"'::jsonb;end if;
 if not credential_recorded then blockers:=blockers||'"microsoft_destination_oauth_required"'::jsonb;end if;
 if tenant is not null and c.auth_metadata->>'tenant_id' is distinct from tenant::text then blockers:=blockers||'"microsoft_recorded_tenant_mismatch"'::jsonb;end if;
 if c.auth_status is distinct from 'valid' then blockers:=blockers||'"microsoft_authorization_not_valid"'::jsonb;end if;
 if c.status is null or c.status not in ('pending','active') then blockers:=blockers||'"connection_not_enabled_for_verification"'::jsonb;end if;
 environment:=coalesce(p_body->>'environment',c.settings->>'environment');company:=coalesce(p_body->>'company_id',c.settings->>'company_id');
 if environment is null or environment !~ '^[A-Za-z0-9][A-Za-z0-9 _-]{0,79}$' then blockers:=blockers||'"business_central_environment_required"'::jsonb;end if;
 if company is null or company !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or company='00000000-0000-0000-0000-000000000000' then blockers:=blockers||'"business_central_company_selection_required"'::jsonb;end if;
 blockers:=blockers||'["business_central_api_and_company_verification_required","business_central_resumable_importer_required","business_central_nested_pagination_required","business_central_atomic_checkpoint_and_reconciliation_required"]'::jsonb;
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'business_central_destination_verification_required' else null end,
  'connection_id',c.id,'organization_id',c.organization_id,'preflight_only',true,'sync_ready',false,'executed',false,'imported_records',0,'job_created',false,'performance_orders',0,
  'destination_tenant_review_recorded',tenant is not null,'destination_credential_recorded',credential_recorded,'provider_verified',false,'blockers',blockers);
end $$;
revoke all on function tj_private.business_central_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.business_central_preflight(jsonb) to authenticated;
create function public.tj_business_central_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.business_central_preflight(p_body);$$;
revoke all on function public.tj_business_central_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_business_central_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
