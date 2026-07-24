begin;

create unique index if not exists mfr_assets_one_active_primary_per_product_idx
  on public.mfr_assets (product_id)
  where product_id is not null
    and is_primary = true
    and archived_at is null;

commit;
