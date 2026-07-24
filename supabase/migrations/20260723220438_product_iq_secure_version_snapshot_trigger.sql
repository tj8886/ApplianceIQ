-- Version snapshots are written only by the existing server-side trigger,
-- never by an authenticated client. This preserves immutable history while
-- allowing authorized Product IQ changes to be versioned.
begin;

create or replace function public.aiq_record_version()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  version_table text := tg_argv[0];
  fk_column text := tg_argv[1];
begin
  execute format(
    'insert into public.%I (organization_id, %I, version_number, snapshot) values ($1.organization_id, $1.id, $1.version_number, to_jsonb($1))',
    version_table, fk_column
  ) using new;
  return null;
end;
$$;

revoke all on function public.aiq_record_version() from public;

commit;
