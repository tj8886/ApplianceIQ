-- Product IQ Phase 1: additive governance, provenance, and approved-data
-- contract. This migration does not activate a manufacturer, brand scope, or
-- platform user and does not alter the existing product source of truth.
begin;

alter table public.aiq_products
  add column if not exists brand_id uuid references public.brand_catalog(id) on delete restrict,
  add column if not exists manufacturer_id uuid references public.mfr_vendors(id) on delete restrict,
  add column if not exists source_type text not null default 'internal' check (source_type in ('raw_import','ai_extracted','ai_suggested','manufacturer_submitted','aiq_reviewed','internal')),
  add column if not exists source_reference text,
  add column if not exists source_confidence numeric(5,2) check (source_confidence is null or (source_confidence >= 0 and source_confidence <= 100)),
  add column if not exists source_extracted_at timestamptz,
  add column if not exists source_review_status text not null default 'not_required' check (source_review_status in ('not_required','pending','accepted','rejected','needs_review')),
  add column if not exists source_reviewed_by uuid references auth.users(id) on delete set null,
  add column if not exists source_reviewed_at timestamptz,
  add column if not exists published_at timestamptz,
  add column if not exists unpublished_at timestamptz,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null;

create index if not exists aiq_products_brand_id_idx on public.aiq_products (brand_id);
create index if not exists aiq_products_manufacturer_id_idx on public.aiq_products (manufacturer_id);

alter table public.product_iq_platform_roles
  drop constraint if exists product_iq_platform_roles_role_check;
alter table public.product_iq_platform_roles
  add constraint product_iq_platform_roles_role_check check (role in ('product_iq_super_admin', 'super_admin', 'data_reviewer', 'data_publisher'));

create or replace function private.product_iq_is_platform_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.product_iq_platform_roles r
    where r.user_id = auth.uid() and r.status = 'active'
      and (r.expires_at is null or r.expires_at > now())
      and r.role in ('product_iq_super_admin', 'super_admin', 'data_reviewer', 'data_publisher')
  );
$$;

create table if not exists public.product_iq_change_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  requested_version_number integer not null,
  request_type text not null check (request_type in ('create','update','submit','publish','unpublish','discontinue','restore')),
  status text not null default 'draft' check (status in ('draft','submitted','in_review','changes_requested','approved','rejected','published','cancelled')),
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  submitted_at timestamptz,
  resolved_at timestamptz,
  summary text,
  source_type text not null default 'manufacturer_submitted' check (source_type in ('raw_import','ai_extracted','ai_suggested','manufacturer_submitted','aiq_reviewed','internal')),
  source_reference text,
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists product_iq_change_requests_queue_idx on public.product_iq_change_requests (organization_id,status,requested_at desc);

create table if not exists public.product_iq_reviews (
  id uuid primary key default gen_random_uuid(),
  change_request_id uuid not null references public.product_iq_change_requests(id) on delete cascade,
  decision text not null check (decision in ('approve','request_changes','reject','publish','unpublish')),
  reviewer_id uuid references auth.users(id) on delete set null,
  reviewer_role text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists product_iq_reviews_change_request_idx on public.product_iq_reviews (change_request_id,created_at desc);

create table if not exists public.product_iq_data_quality_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  version_number integer not null,
  score numeric(5,2) not null check (score between 0 and 100),
  section_scores jsonb not null default '{}'::jsonb,
  issues jsonb not null default '[]'::jsonb,
  validation_source text not null default 'rules' check (validation_source in ('rules','ai_suggestion','manual')),
  validated_at timestamptz not null default now(),
  validated_by uuid references auth.users(id) on delete set null,
  unique(product_id,version_number,validation_source)
);

create table if not exists public.product_iq_ai_suggestions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  issue_type text not null,
  affected_field text,
  current_value jsonb,
  suggested_value jsonb,
  reasoning_summary text not null,
  source_reference text,
  confidence numeric(5,2) not null check (confidence between 0 and 100),
  extracted_at timestamptz not null default now(),
  review_status text not null default 'pending' check (review_status in ('pending','accepted','rejected','edited','assigned','not_applicable')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  reviewer_notes text
);
create index if not exists product_iq_ai_suggestions_queue_idx on public.product_iq_ai_suggestions (organization_id,review_status,extracted_at desc);

create table if not exists public.product_iq_distribution_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  product_id uuid not null references public.aiq_products(id) on delete cascade,
  product_version_number integer not null,
  destination text not null check (destination in ('applianceiq_ai','spec_iq','crm','brand_academy','ai_sales_coach','field_reports')),
  status text not null default 'queued' check (status in ('queued','processing','published','blocked','failed','invalidated')),
  eligible_at timestamptz,
  processed_at timestamptz,
  error_message text,
  payload_hash text,
  created_at timestamptz not null default now()
);
create index if not exists product_iq_distribution_events_status_idx on public.product_iq_distribution_events (destination,status,created_at desc);

create table if not exists public.product_iq_governance_audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid,
  product_id uuid,
  entity_type text not null,
  entity_id uuid,
  action text not null,
  actor_id uuid,
  actor_kind text not null default 'user' check (actor_kind in ('user','system_migration','service')),
  reason text,
  old_record jsonb,
  new_record jsonb,
  created_at timestamptz not null default now()
);
create index if not exists product_iq_governance_audit_entity_idx on public.product_iq_governance_audit_log (entity_type,entity_id,created_at desc);

alter table public.product_iq_change_requests enable row level security;
alter table public.product_iq_reviews enable row level security;
alter table public.product_iq_data_quality_results enable row level security;
alter table public.product_iq_ai_suggestions enable row level security;
alter table public.product_iq_distribution_events enable row level security;
alter table public.product_iq_governance_audit_log enable row level security;

create policy "product iq platform change requests" on public.product_iq_change_requests for all to authenticated
  using ((select private.product_iq_is_platform_admin())) with check ((select private.product_iq_is_platform_admin()));
create policy "product iq platform reviews" on public.product_iq_reviews for all to authenticated
  using ((select private.product_iq_is_platform_admin())) with check ((select private.product_iq_is_platform_admin()));
create policy "product iq platform quality results" on public.product_iq_data_quality_results for select to authenticated
  using ((select private.product_iq_is_platform_admin()));
create policy "product iq platform ai suggestions" on public.product_iq_ai_suggestions for all to authenticated
  using ((select private.product_iq_is_platform_admin())) with check ((select private.product_iq_is_platform_admin()));
create policy "product iq platform distribution events" on public.product_iq_distribution_events for select to authenticated
  using ((select private.product_iq_is_platform_admin()));
create policy "product iq platform governance audit read" on public.product_iq_governance_audit_log for select to authenticated
  using ((select private.product_iq_is_platform_admin()));

-- Approved-data contract. This security-invoker view is the only public
-- Product IQ distribution surface; draft, submitted, and non-public products
-- cannot enter it. It inherits aiq_products RLS for each consuming user.
create or replace view public.product_iq_approved_products
with (security_invoker = true)
as
select
  p.id, p.organization_id, p.brand_id, p.manufacturer_id, p.manufacturer_name,
  p.brand_name, p.product_line, p.category, p.series, p.model, p.product_family,
  p.short_description, p.msrp, p.country_availability, p.status, p.approval_status,
  p.version_number, p.published_at, p.source_type, p.source_reference,
  p.source_confidence, p.updated_at,
  s.dimensions, s.electrical, s.gas, s.ventilation, s.installation,
  s.performance, s.certifications, s.warranty
from public.aiq_products p
left join public.aiq_product_specifications s on s.product_id = p.id
where p.approval_status = 'approved'
  and p.public_visible = true
  and p.status in ('active','discontinued');

revoke all on table public.product_iq_approved_products from public, anon;
grant select on table public.product_iq_approved_products to authenticated;

commit;
