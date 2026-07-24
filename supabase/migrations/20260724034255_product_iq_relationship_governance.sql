begin;

alter table public.aiq_product_relationships
  add column if not exists direction text not null default 'forward',
  add column if not exists requirement_level text not null default 'optional',
  add column if not exists compatibility_status text not null default 'unverified',
  add column if not exists compatibility_notes text,
  add column if not exists installation_notes text,
  add column if not exists quantity integer,
  add column if not exists minimum_quantity integer,
  add column if not exists maximum_quantity integer,
  add column if not exists same_brand_requirement boolean not null default false,
  add column if not exists compatible_finish_requirement boolean not null default false,
  add column if not exists source_type text not null default 'internal',
  add column if not exists source_reference text,
  add column if not exists source_confidence numeric(5,2),
  add column if not exists effective_start_date date,
  add column if not exists effective_end_date date,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid,
  add column if not exists created_by uuid,
  add column if not exists updated_by uuid;

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_relationship_type_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_relationship_type_check
  check (relationship_type in (
    'accessory',
    'required_accessory',
    'optional_accessory',
    'compatible_with',
    'incompatible_with',
    'replaces',
    'replaced_by',
    'predecessor',
    'successor',
    'package_companion',
    'installation_dependency',
    'pedestal',
    'stacking_kit',
    'panel',
    'handle',
    'trim_kit',
    'filter',
    'hose',
    'power_cord',
    'ventilation_dependency',
    'cooking_dependency',
    'laundry_pair',
    'refrigeration_pair',
    'outdoor_pair',
    'alternate_finish',
    'equivalent_model',
    'service_part',
    'other'
  ));

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_direction_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_direction_check
  check (direction in ('forward', 'bidirectional'));

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_requirement_level_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_requirement_level_check
  check (requirement_level in ('required', 'recommended', 'optional', 'not_applicable'));

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_compatibility_status_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_compatibility_status_check
  check (compatibility_status in ('verified', 'likely', 'conditional', 'incompatible', 'unverified', 'discontinued', 'not_applicable'));

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_quantity_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_quantity_check
  check (quantity is null or quantity > 0);

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_minimum_quantity_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_minimum_quantity_check
  check (minimum_quantity is null or minimum_quantity > 0);

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_maximum_quantity_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_maximum_quantity_check
  check (maximum_quantity is null or maximum_quantity > 0);

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_quantity_range_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_quantity_range_check
  check (minimum_quantity is null or maximum_quantity is null or minimum_quantity <= maximum_quantity);

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_source_confidence_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_source_confidence_check
  check (source_confidence is null or (source_confidence >= 0 and source_confidence <= 100));

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_effective_date_check;
alter table public.aiq_product_relationships
  add constraint aiq_product_relationships_effective_date_check
  check (effective_start_date is null or effective_end_date is null or effective_end_date >= effective_start_date);

create unique index if not exists aiq_product_relationships_active_unique_idx
  on public.aiq_product_relationships (organization_id, product_id, related_product_id, relationship_type, direction)
  where archived_at is null;

create index if not exists aiq_product_relationships_product_active_idx
  on public.aiq_product_relationships (product_id, archived_at, relationship_type, direction);

create index if not exists aiq_product_relationships_related_active_idx
  on public.aiq_product_relationships (related_product_id, archived_at, relationship_type, direction);

alter table public.aiq_product_relationships
  drop constraint if exists aiq_product_relationships_organization_id_product_id_relate_key;

drop policy if exists "product iq relationships read" on public.aiq_product_relationships;
create policy "product iq relationships read" on public.aiq_product_relationships
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.aiq_products p
      where p.id = aiq_product_relationships.product_id
        and private.product_iq_can_read_product(p.organization_id, p.brand_name)
    )
    or exists (
      select 1
      from public.aiq_products p
      where p.id = aiq_product_relationships.related_product_id
        and private.product_iq_can_read_product(p.organization_id, p.brand_name)
    )
  );

drop policy if exists "product iq relationships manage" on public.aiq_product_relationships;
create policy "product iq relationships manage" on public.aiq_product_relationships
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.aiq_products p
      where p.id = aiq_product_relationships.product_id
        and private.product_iq_can_manage_product(p.organization_id, p.brand_name)
    )
  )
  with check (
    exists (
      select 1
      from public.aiq_products p
      where p.id = aiq_product_relationships.product_id
        and private.product_iq_can_manage_product(p.organization_id, p.brand_name)
    )
  );

drop policy if exists "product iq relationship versions read" on public.aiq_product_relationship_versions;
create policy "product iq relationship versions read" on public.aiq_product_relationship_versions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.aiq_product_relationships r
      join public.aiq_products p on p.id = r.product_id
      where r.id = aiq_product_relationship_versions.relationship_id
        and private.product_iq_can_read_product(p.organization_id, p.brand_name)
    )
    or exists (
      select 1
      from public.aiq_product_relationships r
      join public.aiq_products p on p.id = r.related_product_id
      where r.id = aiq_product_relationship_versions.relationship_id
        and private.product_iq_can_read_product(p.organization_id, p.brand_name)
    )
  );

commit;
