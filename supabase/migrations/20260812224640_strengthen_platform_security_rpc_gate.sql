begin;

create table if not exists public.platform_security_rpc_allowlist (
  function_signature text primary key,
  allow_anon boolean not null default false,
  allow_authenticated boolean not null default false,
  rationale text not null,
  reviewed_by uuid,
  reviewed_at timestamptz not null default now(),
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
);
alter table public.platform_security_rpc_allowlist enable row level security;
revoke all on table public.platform_security_rpc_allowlist from anon, authenticated;
grant all on table public.platform_security_rpc_allowlist to service_role;

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
    select c.relname as object_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','rls_disabled','object',object_name)),'[]'::jsonb) j from f
  ) select cnt,j into v_critical,v_findings from a;

  with f as (
    select c.relname as object_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v' and not coalesce('security_invoker=true' = any(c.reloptions), false)
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','view_not_security_invoker','object',object_name)),'[]'::jsonb) j from f
  ) select v_critical+cnt,v_findings||j into v_critical,v_findings from a;

  with f as (
    select p.oid::regprocedure::text object_name from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef
      and not exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) x where x like 'search_path=%')
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','warning','type','definer_search_path_unpinned','object',object_name)),'[]'::jsonb) j from f
  ) select v_warning+cnt,v_findings||j into v_warning,v_findings from a;

  with f as (
    select p.oid::regprocedure::text object_name from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('public',p.oid,'EXECUTE')
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','definer_public_execute','object',object_name)),'[]'::jsonb) j from f
  ) select v_critical+cnt,v_findings||j into v_critical,v_findings from a;

  with f as (
    select p.oid::regprocedure::text object_name
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    left join public.platform_security_rpc_allowlist a
      on a.function_signature=p.oid::regprocedure::text and a.allow_anon and (a.expires_at is null or a.expires_at>now())
    where n.nspname='public' and p.prosecdef and has_function_privilege('anon',p.oid,'EXECUTE') and a.function_signature is null
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','critical','type','unreviewed_anon_security_definer_rpc','object',object_name)),'[]'::jsonb) j from f
  ) select v_critical+cnt,v_findings||j into v_critical,v_findings from a;

  with f as (
    select p.oid::regprocedure::text object_name
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    left join public.platform_security_rpc_allowlist a
      on a.function_signature=p.oid::regprocedure::text and a.allow_authenticated and (a.expires_at is null or a.expires_at>now())
    where n.nspname='public' and p.prosecdef and has_function_privilege('authenticated',p.oid,'EXECUTE') and a.function_signature is null
  ), a as (
    select count(*) cnt, coalesce(jsonb_agg(jsonb_build_object('severity','warning','type','unreviewed_authenticated_security_definer_rpc','object',object_name)),'[]'::jsonb) j from f
  ) select v_warning+cnt,v_findings||j into v_warning,v_findings from a;

  insert into public.platform_security_status(singleton,passed,critical_findings,warning_findings,findings,evaluated_at)
  values(true,v_critical=0,v_critical,v_warning,v_findings,now())
  on conflict(singleton) do update set passed=excluded.passed,critical_findings=excluded.critical_findings,
    warning_findings=excluded.warning_findings,findings=excluded.findings,evaluated_at=excluded.evaluated_at
  returning * into v_row;

  update public.platform_connector_certifications
  set platform_security_passed=v_row.passed,platform_security_evaluated_at=v_row.evaluated_at,updated_at=now();
  return v_row;
end;
$$;
revoke execute on function public.refresh_platform_security_status() from public, anon, authenticated;
grant execute on function public.refresh_platform_security_status() to service_role;

commit;
