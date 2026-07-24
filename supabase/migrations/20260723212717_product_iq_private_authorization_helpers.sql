-- Keep Product IQ SECURITY DEFINER authorization helpers out of the exposed
-- public schema. RLS policies and triggers retain function OID references.
begin;

alter function public.product_iq_is_platform_admin() set schema private;
alter function public.product_iq_has_vendor_role(uuid, text[]) set schema private;
alter function public.product_iq_has_brand_capability(uuid, text, text) set schema private;
alter function public.product_iq_can_read_product(uuid, text) set schema private;
alter function public.product_iq_can_manage_product(uuid, text) set schema private;
alter function public.product_iq_can_publish_product() set schema private;
alter function public.product_iq_guard_product_governance() set schema private;

create or replace function private.product_iq_can_read_product(p_organization_id uuid, p_brand_name text)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$
  select (select private.product_iq_is_platform_admin())
      or (select private.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_read'))
      or (select private.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_manage'));
$$;

create or replace function private.product_iq_can_manage_product(p_organization_id uuid, p_brand_name text)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$
  select (select private.product_iq_is_platform_admin())
      or (
        (select private.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_manage'))
        and exists (
          select 1 from public.brand_catalog b
          join public.product_iq_brand_scopes s on s.brand_id = b.id and s.vendor_id = b.manufacturer_id
          join public.mfr_members m on m.vendor_id = s.vendor_id and m.user_id = auth.uid()
          where b.organization_id = p_organization_id and b.brand_name = p_brand_name
            and m.status = 'active' and m.role in ('vendor_owner', 'vendor_admin', 'brand_admin', 'product_editor')
        )
      );
$$;

create or replace function private.product_iq_can_publish_product()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select (select private.product_iq_is_platform_admin()); $$;

create or replace function private.product_iq_guard_product_governance()
returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' and not (select private.product_iq_can_publish_product()) then
    if new.status <> 'draft' or new.approval_status <> 'draft' or new.public_visible is distinct from false then
      raise exception 'Product IQ: non-platform users may only create unpublished drafts';
    end if;
  end if;
  if tg_op = 'UPDATE' and not (select private.product_iq_can_publish_product()) then
    if new.status is distinct from old.status or new.approval_status is distinct from old.approval_status
       or new.public_visible is distinct from old.public_visible or new.launch_date is distinct from old.launch_date
       or new.discontinued_date is distinct from old.discontinued_date then
      raise exception 'Product IQ: approval, publication, and lifecycle fields require a platform reviewer';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function private.product_iq_is_platform_admin() from public;
revoke all on function private.product_iq_has_vendor_role(uuid, text[]) from public;
revoke all on function private.product_iq_has_brand_capability(uuid, text, text) from public;
revoke all on function private.product_iq_can_read_product(uuid, text) from public;
revoke all on function private.product_iq_can_manage_product(uuid, text) from public;
revoke all on function private.product_iq_can_publish_product() from public;
revoke all on function private.product_iq_guard_product_governance() from public;

grant usage on schema private to authenticated;
grant execute on function private.product_iq_is_platform_admin() to authenticated;
grant execute on function private.product_iq_has_vendor_role(uuid, text[]) to authenticated;
grant execute on function private.product_iq_has_brand_capability(uuid, text, text) to authenticated;
grant execute on function private.product_iq_can_read_product(uuid, text) to authenticated;
grant execute on function private.product_iq_can_manage_product(uuid, text) to authenticated;
grant execute on function private.product_iq_can_publish_product() to authenticated;

commit;
