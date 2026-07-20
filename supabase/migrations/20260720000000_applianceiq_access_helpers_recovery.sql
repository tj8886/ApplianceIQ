-- ApplianceIQ recovery helpers for missing private/public auth primitives.
-- Additive only. Restores the helper surface required by AICRM policies and
-- updated_at triggers without reintroducing the legacy roles/permissions stack.

create schema if not exists private;

create or replace function public.current_user_roles()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    array_agg(distinct om.role order by om.role),
    array[]::text[]
  )
  from public.organization_members om
  where om.user_id = auth.uid()
    and om.status = 'active';
$$;

create or replace function public.has_role(role_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(role_name = any(public.current_user_roles()), false);
$$;

create or replace function public.has_any_role(role_names text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    exists (
      select 1
      from unnest(coalesce(role_names, array[]::text[])) as r(role_name)
      where r.role_name = any(public.current_user_roles())
    ),
    false
  );
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false;
$$;

create or replace function public.has_permission(permission_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if permission_name is null or auth.uid() is null then
    return false;
  end if;

  if public.is_super_admin() then
    return true;
  end if;

  if exists (
    select 1
    from public.organization_members om
    where om.user_id = auth.uid()
      and om.status = 'active'
      and om.role = 'owner'
  ) then
    return true;
  end if;

  return permission_name in (
    'organization.view',
    'crm.view',
    'ats.view',
    'reporting.view',
    'billing.read',
    'ai.command.use',
    'ai.audit.view',
    'files.view',
    'communications.view',
    'notifications.view'
  );
end;
$$;

create or replace function private.user_has_org_permission(
  p_organization_id uuid,
  p_permission_name text default null,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text;
begin
  if p_organization_id is null or p_user_id is null then
    return false;
  end if;

  if public.is_super_admin() then
    return true;
  end if;

  select om.role
    into v_role
  from public.organization_members om
  where om.organization_id = p_organization_id
    and om.user_id = p_user_id
    and om.status = 'active'
  order by case when om.role = 'owner' then 0 else 1 end
  limit 1;

  if not found then
    return false;
  end if;

  if v_role = 'owner' then
    return true;
  end if;

  if p_permission_name is null then
    return true;
  end if;

  return p_permission_name in (
    'organization.view',
    'crm.view',
    'ats.view',
    'reporting.view',
    'billing.read',
    'ai.command.use',
    'ai.audit.view',
    'files.view',
    'communications.view',
    'notifications.view'
  );
end;
$$;

create or replace function private.user_can_access_organization(
  p_organization_id uuid,
  p_permission_name text default null,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.user_has_org_permission(p_organization_id, p_permission_name, p_user_id);
$$;

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function public.current_user_roles() from public;
revoke all on function public.has_role(text) from public;
revoke all on function public.has_any_role(text[]) from public;
revoke all on function public.is_super_admin() from public;
revoke all on function public.has_permission(text) from public;
revoke all on function private.user_has_org_permission(uuid, text, uuid) from public;
revoke all on function private.user_can_access_organization(uuid, text, uuid) from public;
revoke all on function private.set_updated_at() from public;

grant execute on function public.current_user_roles() to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.has_role(text) to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.has_any_role(text[]) to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.is_super_admin() to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function public.has_permission(text) to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function private.user_has_org_permission(uuid, text, uuid) to authenticated, service_role;
grant execute on function private.user_can_access_organization(uuid, text, uuid) to authenticated, service_role;
grant execute on function private.set_updated_at() to authenticated, service_role;
