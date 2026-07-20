-- ApplianceIQ AI research compatibility expansion for executive and product-fit read models.
-- Additive only.

alter table public.aicrm_ai_research
  add column if not exists recommended_products jsonb not null default '[]'::jsonb,
  add column if not exists recommended_campaign text,
  add column if not exists recommended_campaign_reasoning text,
  add column if not exists recommended_next_action text,
  add column if not exists recommended_next_action_reasoning text,
  add column if not exists recommended_next_action_confidence numeric,
  add column if not exists product_fit_scores jsonb not null default '{}'::jsonb;
