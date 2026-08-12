select vault.create_secret(
  encode(gen_random_bytes(32),'hex'),
  'connector_recovery_dispatch',
  'Internal connector recovery dispatcher token'
)
where not exists (
  select 1 from vault.decrypted_secrets where name='connector_recovery_dispatch'
);

create or replace function public.platform_validate_connector_dispatch_token(p_token text)
returns boolean
language sql
security definer
set search_path=public,vault
as $$
  select exists(
    select 1
    from vault.decrypted_secrets
    where name='connector_recovery_dispatch'
      and decrypted_secret=p_token
  );
$$;
revoke all on function public.platform_validate_connector_dispatch_token(text) from public,anon,authenticated;
grant execute on function public.platform_validate_connector_dispatch_token(text) to service_role;

create or replace function public.platform_get_connector_recovery_secret()
returns text
language sql
security definer
set search_path=public,vault
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name='connector_recovery_dispatch'
  limit 1;
$$;
revoke all on function public.platform_get_connector_recovery_secret() from public,anon,authenticated;
grant execute on function public.platform_get_connector_recovery_secret() to service_role;
