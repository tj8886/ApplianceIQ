create table if not exists public.platform_user_context (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete set null,
  location_id uuid references public.org_locations(id) on delete set null,
  entity_type text,
  entity_id text,
  entity_label text,
  source_module_key text,
  context jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.platform_user_context enable row level security;
drop policy if exists platform_user_context_select_self on public.platform_user_context;
create policy platform_user_context_select_self on public.platform_user_context for select to authenticated using (user_id=auth.uid());
drop policy if exists platform_user_context_insert_self on public.platform_user_context;
create policy platform_user_context_insert_self on public.platform_user_context for insert to authenticated with check (user_id=auth.uid());
drop policy if exists platform_user_context_update_self on public.platform_user_context;
create policy platform_user_context_update_self on public.platform_user_context for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

create or replace function public.my_platform_context() returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare uid uuid:=auth.uid(); out_ctx jsonb; begin
 if uid is null then raise exception 'authentication_required'; end if;
 select jsonb_build_object('user_id',uid,'organization_id',c.organization_id,'organization_name',o.name,'organization_role',om.role,'location_id',c.location_id,'location_name',l.name,'location_code',l.code,'entity_type',c.entity_type,'entity_id',c.entity_id,'entity_label',c.entity_label,'source_module_key',c.source_module_key,'context',coalesce(c.context,'{}'::jsonb),'updated_at',c.updated_at) into out_ctx
 from public.platform_user_context c left join public.organizations o on o.id=c.organization_id left join public.organization_members om on om.organization_id=c.organization_id and om.user_id=uid and coalesce(om.status,'active')='active' left join public.org_locations l on l.id=c.location_id where c.user_id=uid;
 if out_ctx is null then
   select jsonb_build_object('user_id',uid,'organization_id',om.organization_id,'organization_name',o.name,'organization_role',om.role,'location_id',lm.location_id,'location_name',l.name,'location_code',l.code,'entity_type',null,'entity_id',null,'entity_label',null,'source_module_key','platform','context','{}'::jsonb,'updated_at',now()) into out_ctx
   from public.organization_members om join public.organizations o on o.id=om.organization_id left join lateral (select olm.location_id from public.org_location_members olm where olm.organization_id=om.organization_id and olm.user_id=uid order by olm.is_primary desc,olm.created_at limit 1) lm on true left join public.org_locations l on l.id=lm.location_id where om.user_id=uid and coalesce(om.status,'active')='active' order by om.created_at limit 1;
 end if;
 return coalesce(out_ctx,jsonb_build_object('user_id',uid,'context','{}'::jsonb));
end $$;
revoke all on function public.my_platform_context() from public,anon; grant execute on function public.my_platform_context() to authenticated,service_role;

create or replace function public.set_platform_context(p_organization_id uuid default null,p_location_id uuid default null,p_entity_type text default null,p_entity_id text default null,p_entity_label text default null,p_source_module_key text default null,p_context jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare uid uuid:=auth.uid(); org_id uuid; begin
 if uid is null then raise exception 'authentication_required'; end if;
 org_id:=p_organization_id;
 if org_id is null then select organization_id into org_id from public.platform_user_context where user_id=uid; end if;
 if org_id is null then select organization_id into org_id from public.organization_members where user_id=uid and coalesce(status,'active')='active' order by created_at limit 1; end if;
 if org_id is not null and not exists(select 1 from public.organization_members where user_id=uid and organization_id=org_id and coalesce(status,'active')='active') then raise exception 'organization_access_denied'; end if;
 if p_location_id is not null and not exists(select 1 from public.org_locations where id=p_location_id and organization_id=org_id and is_active=true) then raise exception 'location_access_denied'; end if;
 insert into public.platform_user_context(user_id,organization_id,location_id,entity_type,entity_id,entity_label,source_module_key,context,updated_at) values(uid,org_id,p_location_id,p_entity_type,p_entity_id,p_entity_label,p_source_module_key,coalesce(p_context,'{}'::jsonb),now())
 on conflict(user_id) do update set organization_id=excluded.organization_id,location_id=excluded.location_id,entity_type=excluded.entity_type,entity_id=excluded.entity_id,entity_label=excluded.entity_label,source_module_key=excluded.source_module_key,context=excluded.context,updated_at=now();
 return public.my_platform_context();
end $$;
revoke all on function public.set_platform_context(uuid,uuid,text,text,text,text,jsonb) from public,anon; grant execute on function public.set_platform_context(uuid,uuid,text,text,text,text,jsonb) to authenticated,service_role;

create or replace function public.my_platform_organizations() returns table(organization_id uuid,organization_name text,role text) language sql security definer set search_path=public,auth as $$ select o.id,o.name,om.role from public.organization_members om join public.organizations o on o.id=om.organization_id where om.user_id=auth.uid() and coalesce(om.status,'active')='active' and o.deleted_at is null order by o.name $$;
revoke all on function public.my_platform_organizations() from public,anon; grant execute on function public.my_platform_organizations() to authenticated,service_role;

create or replace function public.my_platform_locations(p_organization_id uuid) returns table(location_id uuid,location_name text,location_code text,location_type text) language sql security definer set search_path=public,auth as $$ select l.id,l.name,l.code,l.location_type from public.org_locations l where l.organization_id=p_organization_id and l.is_active=true and exists(select 1 from public.organization_members om where om.organization_id=p_organization_id and om.user_id=auth.uid() and coalesce(om.status,'active')='active') order by l.name $$;
revoke all on function public.my_platform_locations(uuid) from public,anon; grant execute on function public.my_platform_locations(uuid) to authenticated,service_role;
