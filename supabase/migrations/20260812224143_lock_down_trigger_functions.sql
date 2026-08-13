begin;

do $$
declare r record;
begin
  for r in
    select distinct p.oid::regprocedure as fn
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    join pg_trigger t on t.tgfoid=p.oid and not t.tgisinternal
    where n.nspname='public'
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.fn);
    execute format('grant execute on function %s to service_role', r.fn);
  end loop;
end $$;

commit;
