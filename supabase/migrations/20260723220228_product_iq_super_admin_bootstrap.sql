-- Server-side, idempotent bootstrap for the verified initial Product IQ
-- Super Administrator. This migration intentionally contains the immutable
-- Auth UUID, never an email or client-provided metadata authorization rule.
begin;

alter table public.product_iq_platform_roles
  add column if not exists grant_authority text not null default 'system',
  add column if not exists approval_reason text;

create or replace function private.product_iq_record_governance_audit()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  rec jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  entity_uuid uuid := nullif(rec ->> 'id', '')::uuid;
begin
  if tg_table_name = 'product_iq_platform_roles' then
    entity_uuid := nullif(rec ->> 'user_id', '')::uuid;
  end if;
  insert into public.product_iq_governance_audit_log (
    organization_id, product_id, entity_type, entity_id, action, actor_id,
    actor_kind, reason, old_record, new_record
  ) values (
    nullif(rec ->> 'organization_id','')::uuid,
    nullif(rec ->> 'product_id','')::uuid,
    tg_table_name,
    entity_uuid,
    lower(tg_op),
    auth.uid(),
    case when auth.uid() is null then 'system_migration' else 'user' end,
    coalesce(rec ->> 'approval_reason', rec ->> 'reason'),
    case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;
revoke all on function private.product_iq_record_governance_audit() from public;

drop trigger if exists trg_product_iq_platform_roles_audit on public.product_iq_platform_roles;
create trigger trg_product_iq_platform_roles_audit
  after insert or update or delete on public.product_iq_platform_roles
  for each row execute function private.product_iq_record_governance_audit();
drop trigger if exists trg_product_iq_brand_scopes_audit on public.product_iq_brand_scopes;
create trigger trg_product_iq_brand_scopes_audit
  after insert or update or delete on public.product_iq_brand_scopes
  for each row execute function private.product_iq_record_governance_audit();
drop trigger if exists trg_product_iq_change_requests_audit on public.product_iq_change_requests;
create trigger trg_product_iq_change_requests_audit
  after insert or update or delete on public.product_iq_change_requests
  for each row execute function private.product_iq_record_governance_audit();

drop policy if exists "product iq platform roles manage" on public.product_iq_platform_roles;
create policy "product iq platform roles manage" on public.product_iq_platform_roles
  for all to authenticated
  using ((select private.product_iq_is_platform_admin()))
  with check ((select private.product_iq_is_platform_admin()));
drop policy if exists "product iq platform manages brand scopes" on public.product_iq_brand_scopes;
create policy "product iq platform manages brand scopes" on public.product_iq_brand_scopes
  for all to authenticated
  using ((select private.product_iq_is_platform_admin()))
  with check ((select private.product_iq_is_platform_admin()));

-- Verified exact match: one confirmed Auth account was queried before this
-- migration was generated. ON CONFLICT makes repeated deployment idempotent.
insert into public.product_iq_platform_roles (
  user_id, role, status, granted_by, granted_at, grant_authority, approval_reason, notes
) values (
  'ce2145b0-0283-45da-af4c-3a88f84cecae',
  'product_iq_super_admin',
  'active',
  null,
  now(),
  'product_iq_super_admin_bootstrap_migration',
  'Initial Product IQ Super Administrator approved bootstrap for verified Auth user.',
  'Server-side bootstrap. No manufacturer ownership or brand scope granted.'
)
on conflict (user_id) do update
set role = excluded.role,
    status = 'active',
    grant_authority = excluded.grant_authority,
    approval_reason = excluded.approval_reason,
    notes = excluded.notes
where public.product_iq_platform_roles.role <> 'product_iq_super_admin'
   or public.product_iq_platform_roles.status <> 'active';

commit;
