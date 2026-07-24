begin;

-- Additive metadata only. Existing product/specification records remain the
-- source of truth; no alternate product or specification storage is created.
alter table public.aiq_documents
  add column if not exists language text,
  add column if not exists source_type text,
  add column if not exists source_reference text,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users(id) on delete set null;

alter table public.mfr_assets
  add column if not exists product_id uuid references public.aiq_products(id) on delete set null,
  add column if not exists image_type text,
  add column if not exists alt_text text,
  add column if not exists is_primary boolean not null default false,
  add column if not exists display_order integer,
  add column if not exists source_type text,
  add column if not exists source_reference text,
  add column if not exists archived_at timestamptz,
  add column if not exists archived_by uuid references auth.users(id) on delete set null;

create index if not exists mfr_assets_product_id_idx on public.mfr_assets(product_id, display_order);
create index if not exists aiq_products_brand_model_ci_idx on public.aiq_products (lower(brand_name), lower(regexp_replace(model, '[^a-zA-Z0-9]', '', 'g')));

commit;
