begin;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('revoke execute on function %s from public', r.fn);
  end loop;
end $$;

create table if not exists public.platform_security_status (
  singleton boolean primary key default true check (singleton),
  passed boolean not null default false,
  critical_findings integer not null default 0,
  warning_findings integer not null default 0,
  findings jsonb not null default '[]'::jsonb,
  evaluated_at timestamptz not null default now()
);

alter table public.platform_security_status enable row level security;
revoke all on table public.platform_security_status from anon, authenticated;
grant select on table public.platform_security_status to authenticated;
drop policy if exists platform_security_status_authenticated_read on public.platform_security_status;
create policy platform_security_status_authenticated_read on public.platform_security_status
for select to authenticated using (true);

alter table public.platform_connector_certifications
  add column if not exists platform_security_passed boolean not null default false,
  add column if not exists platform_security_evaluated_at timestamptz;

create or replace function public.refresh_platform_security_status()
returns public.platform_security_status
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_findings jsonb := '[]'::jsonb;
  v_critical integer := 0;
  v_warning integer := 0;
  v_row public.platform_security_status;
begin
  with f as (
    select c.relname as object_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
  )
  select count(*), coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','rls_disabled','object',object_name)),'[]'::jsonb)
  into v_critical, v_findings from f;

  with f as (
    select c.relname as object_name
    from pg_class c
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v'
      and not coalesce('security_invoker=true' = any(c.reloptions), false)
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','view_not_security_invoker','object',object_name)),'[]'::jsonb) j from f
  )
  select v_critical + cnt, v_findings || j into v_critical, v_findings from a;

  with f as (
    select p.oid::regprocedure::text as object_name
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, array[]::text[])) x where x like 'search_path=%')
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','warning','type','definer_search_path_unpinned','object',object_name)),'[]'::jsonb) j from f
  )
  select cnt, v_findings || j into v_warning, v_findings from a;

  with f as (
    select p.oid::regprocedure::text as object_name
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and has_function_privilege('public', p.oid, 'EXECUTE')
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','definer_public_execute','object',object_name)),'[]'::jsonb) j from f
  )
  select v_critical + cnt, v_findings || j into v_critical, v_findings from a;

  insert into public.platform_security_status(singleton,passed,critical_findings,warning_findings,findings,evaluated_at)
  values(true, v_critical=0, v_critical, v_warning, v_findings, now())
  on conflict(singleton) do update set
    passed=excluded.passed,
    critical_findings=excluded.critical_findings,
    warning_findings=excluded.warning_findings,
    findings=excluded.findings,
    evaluated_at=excluded.evaluated_at
  returning * into v_row;

  update public.platform_connector_certifications
  set platform_security_passed=v_row.passed,
      platform_security_evaluated_at=v_row.evaluated_at,
      updated_at=now();

  return v_row;
end;
$$;

revoke execute on function public.refresh_platform_security_status() from public, anon, authenticated;
grant execute on function public.refresh_platform_security_status() to service_role;

create or replace function public.enforce_platform_security_certification()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.lifecycle_status='certified' and not new.platform_security_passed then
    raise exception 'Connector cannot be certified while Platform Security Gate is failing';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_platform_security_certification() from public, anon, authenticated;
grant execute on function public.enforce_platform_security_certification() to service_role;

drop trigger if exists trg_enforce_platform_security_certification on public.platform_connector_certifications;
create trigger trg_enforce_platform_security_certification
before insert or update of lifecycle_status, platform_security_passed
on public.platform_connector_certifications
for each row execute function public.enforce_platform_security_certification();

commit;
