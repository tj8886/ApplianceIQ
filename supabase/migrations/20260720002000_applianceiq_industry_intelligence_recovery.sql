-- ApplianceIQ industry intelligence recovery.
-- Minimal additive recovery for the live front-end queries that reference aiq_* tables.

create extension if not exists pgcrypto;

create table if not exists public.aiq_products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  manufacturer_name text not null,
  brand_name text not null,
  product_line text,
  category text not null,
  series text,
  model text not null,
  status text not null default 'draft' check (status in ('draft', 'active', 'paused', 'archived', 'discontinued')),
  launch_date date,
  discontinued_date date,
  msrp numeric(12,2),
  country_availability text[] not null default '{}'::text[],
  product_family text,
  short_description text,
  public_visible boolean not null default false,
  approval_status text not null default 'draft' check (approval_status in ('draft', 'pending_review', 'approved', 'rejected')),
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aiq_product_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_product_specifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  dimensions jsonb,
  electrical jsonb,
  gas jsonb,
  ventilation jsonb,
  installation jsonb,
  performance jsonb,
  certifications jsonb,
  warranty jsonb,
  documents jsonb,
  notes text,
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id)
);

create table if not exists public.aiq_product_specification_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  document_type text not null check (document_type in ('manual', 'installation_guide', 'specification_sheet', 'cad', 'bim', 'brochure', 'price_book', 'warranty', 'video', 'other')),
  title text not null,
  description text,
  file_url text,
  media_url text,
  version text,
  public_visible boolean not null default false,
  approval_status text not null default 'draft' check (approval_status in ('draft', 'pending_review', 'approved', 'rejected')),
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aiq_document_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_id uuid not null references public.aiq_documents(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_competitive_comparisons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  competitor_product_name text not null,
  competitor_product_id uuid,
  advantages text,
  disadvantages text,
  price_position text,
  feature_comparison jsonb,
  target_customer text,
  replacement_recommendations text,
  cross_reference_products text[] not null default '{}'::text[],
  notes text,
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aiq_competitive_comparison_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  comparison_id uuid not null references public.aiq_competitive_comparisons(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_product_training_assets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  asset_type text not null check (asset_type in ('video', 'certification', 'knowledge_check', 'sales_tip', 'installation_tip', 'faq', 'troubleshooting', 'talking_point', 'other')),
  title text not null,
  summary text,
  url text,
  content jsonb,
  knowledge_checks jsonb,
  public_visible boolean not null default false,
  status text not null default 'draft' check (status in ('draft', 'active', 'archived')),
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aiq_product_training_asset_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  training_asset_id uuid not null references public.aiq_product_training_assets(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_product_relationships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  related_product_id uuid not null references public.aiq_products(id) on delete cascade,
  relationship_type text not null check (relationship_type in ('replacement', 'accessory', 'companion', 'alternative', 'successor', 'compatible')),
  relationship_label text,
  notes text,
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, product_id, related_product_id, relationship_type)
);

create table if not exists public.aiq_product_relationship_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  relationship_id uuid not null references public.aiq_product_relationships(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create table if not exists public.aiq_industry_news (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid references public.aiq_products(id) on delete set null,
  manufacturer_name text,
  headline text not null,
  news_type text not null check (news_type in ('new_product', 'product_update', 'award', 'safety_notice', 'recall', 'discontinuation', 'industry_news', 'manufacturer_announcement')),
  summary text,
  source_url text,
  published_at timestamptz,
  public_visible boolean not null default false,
  version_number integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.aiq_industry_news_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  news_id uuid not null references public.aiq_industry_news(id) on delete cascade,
  version_number integer not null,
  snapshot jsonb not null,
  created_at timestamptz not null default now()
);

create or replace function public.aiq_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  if tg_op = 'UPDATE' then
    new.version_number := coalesce(old.version_number, 0) + 1;
  end if;
  return new;
end;
$$;

create or replace function public.aiq_record_version()
returns trigger
language plpgsql
as $$
declare
  version_table text := tg_argv[0];
  fk_column text := tg_argv[1];
begin
  execute format(
    'insert into public.%I (organization_id, %I, version_number, snapshot) values ($1.organization_id, $1.id, $1.version_number, to_jsonb($1))',
    version_table,
    fk_column
  ) using new;
  return null;
end;
$$;

drop trigger if exists trg_aiq_products_touch_updated_at on public.aiq_products;
create trigger trg_aiq_products_touch_updated_at before update on public.aiq_products for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_product_specifications_touch_updated_at on public.aiq_product_specifications;
create trigger trg_aiq_product_specifications_touch_updated_at before update on public.aiq_product_specifications for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_documents_touch_updated_at on public.aiq_documents;
create trigger trg_aiq_documents_touch_updated_at before update on public.aiq_documents for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_competitive_comparisons_touch_updated_at on public.aiq_competitive_comparisons;
create trigger trg_aiq_competitive_comparisons_touch_updated_at before update on public.aiq_competitive_comparisons for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_product_training_assets_touch_updated_at on public.aiq_product_training_assets;
create trigger trg_aiq_product_training_assets_touch_updated_at before update on public.aiq_product_training_assets for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_product_relationships_touch_updated_at on public.aiq_product_relationships;
create trigger trg_aiq_product_relationships_touch_updated_at before update on public.aiq_product_relationships for each row execute function public.aiq_touch_updated_at();
drop trigger if exists trg_aiq_industry_news_touch_updated_at on public.aiq_industry_news;
create trigger trg_aiq_industry_news_touch_updated_at before update on public.aiq_industry_news for each row execute function public.aiq_touch_updated_at();

drop trigger if exists trg_aiq_products_version on public.aiq_products;
create trigger trg_aiq_products_version after insert or update on public.aiq_products for each row execute function public.aiq_record_version('aiq_product_versions', 'product_id');
drop trigger if exists trg_aiq_product_specifications_version on public.aiq_product_specifications;
create trigger trg_aiq_product_specifications_version after insert or update on public.aiq_product_specifications for each row execute function public.aiq_record_version('aiq_product_specification_versions', 'product_id');
drop trigger if exists trg_aiq_documents_version on public.aiq_documents;
create trigger trg_aiq_documents_version after insert or update on public.aiq_documents for each row execute function public.aiq_record_version('aiq_document_versions', 'document_id');
drop trigger if exists trg_aiq_competitive_comparisons_version on public.aiq_competitive_comparisons;
create trigger trg_aiq_competitive_comparisons_version after insert or update on public.aiq_competitive_comparisons for each row execute function public.aiq_record_version('aiq_competitive_comparison_versions', 'comparison_id');
drop trigger if exists trg_aiq_product_training_assets_version on public.aiq_product_training_assets;
create trigger trg_aiq_product_training_assets_version after insert or update on public.aiq_product_training_assets for each row execute function public.aiq_record_version('aiq_product_training_asset_versions', 'training_asset_id');
drop trigger if exists trg_aiq_product_relationships_version on public.aiq_product_relationships;
create trigger trg_aiq_product_relationships_version after insert or update on public.aiq_product_relationships for each row execute function public.aiq_record_version('aiq_product_relationship_versions', 'relationship_id');
drop trigger if exists trg_aiq_industry_news_version on public.aiq_industry_news;
create trigger trg_aiq_industry_news_version after insert or update on public.aiq_industry_news for each row execute function public.aiq_record_version('aiq_industry_news_versions', 'news_id');

create index if not exists aiq_products_org_status_idx on public.aiq_products (organization_id, status, approval_status, updated_at desc nulls last);
create index if not exists aiq_products_org_brand_idx on public.aiq_products (organization_id, brand_name, model);
create index if not exists aiq_product_specifications_org_idx on public.aiq_product_specifications (organization_id, product_id);
create index if not exists aiq_documents_org_idx on public.aiq_documents (organization_id, product_id, approval_status, updated_at desc nulls last);
create index if not exists aiq_competitive_comparisons_org_idx on public.aiq_competitive_comparisons (organization_id, product_id, updated_at desc nulls last);
create index if not exists aiq_product_training_assets_org_idx on public.aiq_product_training_assets (organization_id, product_id, status, updated_at desc nulls last);
create index if not exists aiq_product_relationships_org_idx on public.aiq_product_relationships (organization_id, product_id, relationship_type);
create index if not exists aiq_industry_news_org_idx on public.aiq_industry_news (organization_id, published_at desc nulls last, news_type);

alter table public.aiq_products enable row level security;
alter table public.aiq_product_specifications enable row level security;
alter table public.aiq_documents enable row level security;
alter table public.aiq_competitive_comparisons enable row level security;
alter table public.aiq_product_training_assets enable row level security;
alter table public.aiq_product_relationships enable row level security;
alter table public.aiq_industry_news enable row level security;

drop policy if exists "aiq products select" on public.aiq_products;
create policy "aiq products select" on public.aiq_products
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq products write" on public.aiq_products;
create policy "aiq products write" on public.aiq_products
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product specifications select" on public.aiq_product_specifications;
create policy "aiq product specifications select" on public.aiq_product_specifications
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product specifications write" on public.aiq_product_specifications;
create policy "aiq product specifications write" on public.aiq_product_specifications
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq documents select" on public.aiq_documents;
create policy "aiq documents select" on public.aiq_documents
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq documents write" on public.aiq_documents;
create policy "aiq documents write" on public.aiq_documents
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq competitive comparisons select" on public.aiq_competitive_comparisons;
create policy "aiq competitive comparisons select" on public.aiq_competitive_comparisons
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq competitive comparisons write" on public.aiq_competitive_comparisons;
create policy "aiq competitive comparisons write" on public.aiq_competitive_comparisons
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product training assets select" on public.aiq_product_training_assets;
create policy "aiq product training assets select" on public.aiq_product_training_assets
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product training assets write" on public.aiq_product_training_assets;
create policy "aiq product training assets write" on public.aiq_product_training_assets
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq product relationships select" on public.aiq_product_relationships;
create policy "aiq product relationships select" on public.aiq_product_relationships
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq product relationships write" on public.aiq_product_relationships;
create policy "aiq product relationships write" on public.aiq_product_relationships
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

drop policy if exists "aiq industry news select" on public.aiq_industry_news;
create policy "aiq industry news select" on public.aiq_industry_news
for select
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.view'));

drop policy if exists "aiq industry news write" on public.aiq_industry_news;
create policy "aiq industry news write" on public.aiq_industry_news
for all
to authenticated
using (private.user_can_access_organization(organization_id, 'crm.manage'))
with check (private.user_can_access_organization(organization_id, 'crm.manage'));

grant select, insert, update, delete on public.aiq_products to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_specifications to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_specification_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_documents to authenticated, service_role;
grant select, insert, update, delete on public.aiq_document_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_competitive_comparisons to authenticated, service_role;
grant select, insert, update, delete on public.aiq_competitive_comparison_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_training_assets to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_training_asset_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_relationships to authenticated, service_role;
grant select, insert, update, delete on public.aiq_product_relationship_versions to authenticated, service_role;
grant select, insert, update, delete on public.aiq_industry_news to authenticated, service_role;
grant select, insert, update, delete on public.aiq_industry_news_versions to authenticated, service_role;

comment on table public.aiq_products is 'ApplianceIQ product master for manufacturer, brand, category, series, and model intelligence.';
comment on table public.aiq_product_specifications is 'ApplianceIQ structured product specification record.';
comment on table public.aiq_documents is 'ApplianceIQ versioned document library.';
comment on table public.aiq_competitive_comparisons is 'ApplianceIQ competitive comparison and replacement engine.';
comment on table public.aiq_product_training_assets is 'ApplianceIQ product training and knowledge asset library.';
comment on table public.aiq_product_relationships is 'ApplianceIQ product relationship matrix.';
comment on table public.aiq_industry_news is 'ApplianceIQ industry news and manufacturer announcement tracker.';
