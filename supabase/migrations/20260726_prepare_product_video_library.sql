alter table public.pim_product_videos
  add column if not exists transcript text,
  add column if not exists caption_url text,
  add column if not exists country text,
  add column if not exists platform text,
  add column if not exists external_video_id text,
  add column if not exists publication_date date,
  add column if not exists last_verified_at timestamptz,
  add column if not exists verification_status text not null default 'unverified',
  add column if not exists manufacturer_verified boolean not null default false,
  add column if not exists keywords text[] not null default '{}',
  add column if not exists ai_summary text,
  add column if not exists is_current boolean not null default true,
  add column if not exists replaces_video_id uuid references public.pim_product_videos(id) on delete set null,
  add column if not exists source_reference text,
  add column if not exists archived_at timestamptz;

create index if not exists idx_pim_product_videos_product_current
  on public.pim_product_videos(product_id, is_current, display_order)
  where archived_at is null;

create index if not exists idx_pim_product_videos_brand
  on public.pim_product_videos(brand_id);

create index if not exists idx_pim_product_videos_type
  on public.pim_product_videos(video_type);

create index if not exists idx_pim_product_videos_external
  on public.pim_product_videos(platform, external_video_id)
  where external_video_id is not null;

create index if not exists idx_pim_product_videos_keywords
  on public.pim_product_videos using gin(keywords);

insert into public.pim_asset_types(id, category, label, description, icon, sort_order)
values
  ('feature_demo','video','Feature Demonstration','Focused demonstration of a specific product feature','play',36),
  ('setup_video','video','Setup & Configuration','Initial setup, pairing, calibration, or configuration walkthrough','settings',37),
  ('maintenance_video','video','Cleaning & Maintenance','Cleaning, care, filter replacement, and routine maintenance','tool',38),
  ('troubleshooting_video','video','Troubleshooting','Error codes, resets, diagnostics, and common issue resolution','alert',39),
  ('service_video','video','Service & Repair','Technical service, disassembly, component replacement, and repair guidance','wrench',40),
  ('retail_training_video','video','Retail Training','Sales, positioning, comparison, and retailer product training','graduation',41),
  ('professional_training_video','video','Professional Training','Installer, designer, builder, distributor, or technician training','briefcase',42),
  ('safety_recall_video','video','Safety & Recall','Safety notices, recalls, corrective actions, and compliance guidance','shield',43),
  ('brand_story_video','video','Brand Story','Manufacturer or brand introduction and positioning','building',44),
  ('launch_video','video','Product Launch','Launch announcement, event, or new-product introduction','spark',45),
  ('app_walkthrough_video','video','App Walkthrough','Connected app, Wi-Fi, smart-home, or firmware walkthrough','phone',46),
  ('owner_training_video','video','Owner Training','Daily use, controls, recommended settings, and ownership guidance','user',47)
on conflict (id) do update set
  category = excluded.category,
  label = excluded.label,
  description = excluded.description,
  icon = excluded.icon,
  sort_order = excluded.sort_order;
