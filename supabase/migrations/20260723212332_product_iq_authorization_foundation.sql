-- Product IQ Phase 1: deny-by-default manufacturer authorization foundation.
-- This migration deliberately does not activate any manufacturer or brand. A
-- controlling vendor and brand scope require separate human-approved records.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '45s';

-- Preserve legacy columns for compatibility but make the authoritative
-- membership lifecycle explicit. Existing rows are never auto-activated.
alter table public.mfr_members
  add column if not exists role text,
  add column if not exists status text,
  add column if not exists invited_by uuid,
  add column if not exists approved_by uuid,
  add column if not exists invitation_id uuid,
  add column if not exists approved_at timestamptz,
  add column if not exists activated_at timestamptz,
  add column if not exists suspended_at timestamptz,
  add column if not exists revoked_at timestamptz,
  add column if not exists expires_at timestamptz,
  add column if not exists updated_at timestamptz,
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.mfr_members
  drop constraint if exists mfr_members_role_check,
  drop constraint if exists mfr_members_status_check,
  drop constraint if exists mfr_members_active_approval_check;

alter table public.mfr_members
  add constraint mfr_members_role_check check (role is null or role in (
    'vendor_owner', 'vendor_admin', 'brand_admin', 'product_editor',
    'product_reviewer', 'asset_editor', 'training_editor', 'viewer'
  )),
  add constraint mfr_members_status_check check (status is null or status in (
    'pending', 'active', 'suspended', 'revoked'
  )),
  add constraint mfr_members_active_approval_check check (
    status is distinct from 'active'
    or (role is not null and approved_by is not null and approved_at is not null and activated_at is not null)
  );

create index if not exists mfr_members_vendor_active_role_idx
  on public.mfr_members (vendor_id, role)
  where status = 'active';

-- A brand may only be scoped to its controlling vendor. This creates a
-- deliberate two-key approval gate: brand_catalog.manufacturer_id plus an
-- active Product IQ scope. Both are empty until ownership governance approves.
create table if not exists public.product_iq_brand_scopes (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.mfr_vendors(id) on delete restrict,
  brand_id uuid not null references public.brand_catalog(id) on delete restrict,
  countries text[] not null default '{}',
  capabilities text[] not null default array['product_read', 'product_manage'],
  status text not null default 'pending' check (status in ('pending', 'active', 'suspended', 'revoked')),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  expires_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (vendor_id, brand_id),
  constraint product_iq_brand_scope_active_approval_check check (
    status is distinct from 'active' or (approved_by is not null and approved_at is not null)
  )
);
create index if not exists product_iq_brand_scopes_active_lookup_idx
  on public.product_iq_brand_scopes (brand_id, vendor_id)
  where status = 'active';

-- Platform administration is deliberately server-managed. There is no browser
-- write policy for this table; bootstrap must be a reviewed privileged action.
create table if not exists public.product_iq_platform_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('super_admin', 'data_reviewer', 'data_publisher')),
  status text not null default 'active' check (status in ('active', 'suspended', 'revoked')),
  granted_by uuid references auth.users(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  notes text
);

alter table public.product_iq_brand_scopes enable row level security;
alter table public.product_iq_platform_roles enable row level security;

-- Definer functions are narrow boolean authorization predicates. They do not
-- accept an actor parameter and bind every decision to auth.uid().
create or replace function public.product_iq_is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.product_iq_platform_roles r
    where r.user_id = auth.uid()
      and r.status = 'active'
      and (r.expires_at is null or r.expires_at > now())
      and r.role in ('super_admin', 'data_reviewer', 'data_publisher')
  );
$$;

create or replace function public.product_iq_has_vendor_role(p_vendor_id uuid, p_roles text[])
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.mfr_members m
    where m.user_id = auth.uid()
      and m.vendor_id = p_vendor_id
      and m.status = 'active'
      and m.role = any(p_roles)
      and (m.expires_at is null or m.expires_at > now())
  );
$$;

create or replace function public.product_iq_has_brand_capability(
  p_organization_id uuid,
  p_brand_name text,
  p_capability text
)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.brand_catalog b
    join public.product_iq_brand_scopes s
      on s.brand_id = b.id
     and s.vendor_id = b.manufacturer_id
    join public.mfr_members m
      on m.vendor_id = s.vendor_id
     and m.user_id = auth.uid()
    where b.organization_id = p_organization_id
      and b.brand_name = p_brand_name
      and b.manufacturer_id is not null
      and s.status = 'active'
      and s.approved_by is not null
      and s.approved_at is not null
      and (s.expires_at is null or s.expires_at > now())
      and p_capability = any(s.capabilities)
      and m.status = 'active'
      and m.role in ('vendor_owner', 'vendor_admin', 'brand_admin', 'product_editor', 'product_reviewer', 'asset_editor', 'training_editor', 'viewer')
      and (m.expires_at is null or m.expires_at > now())
  );
$$;

create or replace function public.product_iq_can_read_product(p_organization_id uuid, p_brand_name text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select (select public.product_iq_is_platform_admin())
      or (select public.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_read'))
      or (select public.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_manage'));
$$;

create or replace function public.product_iq_can_manage_product(p_organization_id uuid, p_brand_name text)
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select (select public.product_iq_is_platform_admin())
      or (
        (select public.product_iq_has_brand_capability(p_organization_id, p_brand_name, 'product_manage'))
        and exists (
          select 1 from public.brand_catalog b
          join public.product_iq_brand_scopes s on s.brand_id = b.id and s.vendor_id = b.manufacturer_id
          join public.mfr_members m on m.vendor_id = s.vendor_id and m.user_id = auth.uid()
          where b.organization_id = p_organization_id
            and b.brand_name = p_brand_name
            and m.status = 'active'
            and m.role in ('vendor_owner', 'vendor_admin', 'brand_admin', 'product_editor')
        )
      );
$$;

create or replace function public.product_iq_can_publish_product()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select (select public.product_iq_is_platform_admin());
$$;

create or replace function public.product_iq_guard_product_governance()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' and not (select public.product_iq_can_publish_product()) then
    if new.status <> 'draft' or new.approval_status <> 'draft' or new.public_visible is distinct from false then
      raise exception 'Product IQ: non-platform users may only create unpublished drafts';
    end if;
  end if;

  if tg_op = 'UPDATE' and not (select public.product_iq_can_publish_product()) then
    if new.status is distinct from old.status
       or new.approval_status is distinct from old.approval_status
       or new.public_visible is distinct from old.public_visible
       or new.launch_date is distinct from old.launch_date
       or new.discontinued_date is distinct from old.discontinued_date then
      raise exception 'Product IQ: approval, publication, and lifecycle fields require a platform reviewer';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.product_iq_is_platform_admin() from public;
revoke all on function public.product_iq_has_vendor_role(uuid, text[]) from public;
revoke all on function public.product_iq_has_brand_capability(uuid, text, text) from public;
revoke all on function public.product_iq_can_read_product(uuid, text) from public;
revoke all on function public.product_iq_can_manage_product(uuid, text) from public;
revoke all on function public.product_iq_can_publish_product() from public;
grant execute on function public.product_iq_is_platform_admin() to authenticated;
grant execute on function public.product_iq_has_vendor_role(uuid, text[]) to authenticated;
grant execute on function public.product_iq_has_brand_capability(uuid, text, text) to authenticated;
grant execute on function public.product_iq_can_read_product(uuid, text) to authenticated;
grant execute on function public.product_iq_can_manage_product(uuid, text) to authenticated;
grant execute on function public.product_iq_can_publish_product() to authenticated;

-- Replace self-service privileged manufacturer access. Enrollment, role grants,
-- scope grants, and platform roles are server-only until the reviewed invitation
-- flow is built.
drop policy if exists "own role upsert" on public.mfr_user_roles;
drop policy if exists "own role" on public.mfr_user_roles;
drop policy if exists "self join membership" on public.mfr_members;
drop policy if exists "admin manage members" on public.mfr_members;
drop policy if exists "own memberships" on public.mfr_members;
drop policy if exists "member update own vendor" on public.mfr_vendors;
drop policy if exists "manage own assets" on public.mfr_assets;
drop policy if exists "read published assets" on public.mfr_assets;

drop policy if exists "product iq own membership read" on public.mfr_members;
create policy "product iq own membership read" on public.mfr_members
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.product_iq_is_platform_admin()));

drop policy if exists "product iq own role read" on public.mfr_user_roles;
create policy "product iq own role read" on public.mfr_user_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.product_iq_is_platform_admin()));

drop policy if exists "product iq platform roles read" on public.product_iq_platform_roles;
create policy "product iq platform roles read" on public.product_iq_platform_roles
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.product_iq_is_platform_admin()));

drop policy if exists "product iq brand scope read" on public.product_iq_brand_scopes;
create policy "product iq brand scope read" on public.product_iq_brand_scopes
  for select to authenticated
  using (
    (select public.product_iq_is_platform_admin())
    or (select public.product_iq_has_vendor_role(vendor_id, array['vendor_owner','vendor_admin','brand_admin','product_editor','product_reviewer','asset_editor','training_editor','viewer']))
  );

drop policy if exists "product iq scoped asset management" on public.mfr_assets;
create policy "product iq scoped asset management" on public.mfr_assets
  for all to authenticated
  using (
    (select public.product_iq_is_platform_admin())
    or (select public.product_iq_has_vendor_role(vendor_id, array['vendor_owner','vendor_admin','brand_admin','asset_editor']))
  )
  with check (
    (select public.product_iq_is_platform_admin())
    or (select public.product_iq_has_vendor_role(vendor_id, array['vendor_owner','vendor_admin','brand_admin','asset_editor']))
  );

create policy "product iq published asset read" on public.mfr_assets
  for select to authenticated
  using (is_published = true);

-- A brand controller is a governance decision, never an organization-admin
-- convenience edit. Existing member read behaviour remains unchanged.
drop policy if exists "bc_write" on public.brand_catalog;
create policy "product iq platform manages brand ownership" on public.brand_catalog
  for all to authenticated
  using ((select public.product_iq_is_platform_admin()))
  with check ((select public.product_iq_is_platform_admin()));

-- Product IQ becomes the authoring boundary. Existing CRM organization
-- permissions no longer reveal drafts; only authoritative published data is
-- available to a tenant member. Downstream systems must use the view added in
-- the next Product IQ contract migration, not direct PIM table reads.
drop policy if exists "aiq products select" on public.aiq_products;
drop policy if exists "aiq products write" on public.aiq_products;
create policy "product iq products read" on public.aiq_products
  for select to authenticated
  using (
    (select public.product_iq_can_read_product(organization_id, brand_name))
    or (
      approval_status = 'approved'
      and public_visible = true
      and private.user_can_access_organization(organization_id, 'crm.view'::text)
    )
  );
create policy "product iq products insert" on public.aiq_products
  for insert to authenticated
  with check ((select public.product_iq_can_manage_product(organization_id, brand_name)));
create policy "product iq products update" on public.aiq_products
  for update to authenticated
  using ((select public.product_iq_can_manage_product(organization_id, brand_name)))
  with check ((select public.product_iq_can_manage_product(organization_id, brand_name)));
create policy "product iq products delete" on public.aiq_products
  for delete to authenticated
  using ((select public.product_iq_is_platform_admin()));

drop trigger if exists trg_product_iq_guard_product_governance on public.aiq_products;
create trigger trg_product_iq_guard_product_governance
  before insert or update on public.aiq_products
  for each row execute function public.product_iq_guard_product_governance();

-- Child records inherit their product's authorization. Current Product IQ
-- versioning triggers write snapshots as the table owner; user writes remain
-- restricted to the product scope.
do $$
declare
  t text;
begin
  foreach t in array array[
    'aiq_product_specifications', 'aiq_documents', 'aiq_product_relationships', 'aiq_product_training_assets',
    'aiq_product_versions', 'aiq_product_specification_versions', 'aiq_document_versions',
    'aiq_product_relationship_versions', 'aiq_product_training_asset_versions'
  ] loop
    execute format('drop policy if exists %I on public.%I', replace(t, '_', ' ') || ' select', t);
    execute format('drop policy if exists %I on public.%I', replace(t, '_', ' ') || ' write', t);
  end loop;
end;
$$;

-- Explicit child policies avoid any client path based solely on organization.
create policy "product iq specifications read" on public.aiq_product_specifications for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq specifications manage" on public.aiq_product_specifications for all to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
) with check (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
);
create policy "product iq documents read" on public.aiq_documents for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq documents manage" on public.aiq_documents for all to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
) with check (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
);
create policy "product iq relationships read" on public.aiq_product_relationships for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq relationships manage" on public.aiq_product_relationships for all to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
) with check (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
);
create policy "product iq training assets read" on public.aiq_product_training_assets for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq training assets manage" on public.aiq_product_training_assets for all to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
) with check (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_manage_product(p.organization_id, p.brand_name))
);

-- Version snapshots are immutable for application users and visible only with
-- access to their parent product.
create policy "product iq product versions read" on public.aiq_product_versions for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq specification versions read" on public.aiq_product_specification_versions for select to authenticated using (
  exists (select 1 from public.aiq_products p where p.id = product_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq document versions read" on public.aiq_document_versions for select to authenticated using (
  exists (select 1 from public.aiq_documents d join public.aiq_products p on p.id = d.product_id where d.id = document_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq relationship versions read" on public.aiq_product_relationship_versions for select to authenticated using (
  exists (select 1 from public.aiq_product_relationships r join public.aiq_products p on p.id = r.product_id where r.id = relationship_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);
create policy "product iq training asset versions read" on public.aiq_product_training_asset_versions for select to authenticated using (
  exists (select 1 from public.aiq_product_training_assets a join public.aiq_products p on p.id = a.product_id where a.id = training_asset_id and public.product_iq_can_read_product(p.organization_id, p.brand_name))
);

commit;
