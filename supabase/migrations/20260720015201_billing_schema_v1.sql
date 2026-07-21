-- Billing schema: org subscriptions, token limits, Stripe audit
alter table public.organizations
  add column if not exists tier text not null default 'starter' check (tier in ('starter','pro','enterprise','demo')),
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists subscription_status text check (subscription_status in ('active','past_due','canceled','trialing')),
  add column if not exists billing_email text,
  add column if not exists trial_ends_at timestamptz,
  add column if not exists canceled_at timestamptz;

create table if not exists public.ai_token_limits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete cascade,
  tier text not null check (tier in ('starter','pro','enterprise','demo')),
  monthly_limit bigint not null,
  tokens_used_this_month bigint not null default 0,
  reset_date date not null default (current_date + interval '1 month'),
  updated_at timestamptz not null default now()
);
alter table public.ai_token_limits enable row level security;
create policy ai_token_limits_select on public.ai_token_limits for select using (is_org_member(organization_id));
create index ai_token_limits_org_idx on public.ai_token_limits (organization_id);

create table if not exists public.stripe_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  event_type text not null,
  event_id text not null unique,
  object_id text,
  payload jsonb not null,
  processed_at timestamptz not null default now()
);
create index stripe_events_org_idx on public.stripe_events (organization_id);
create index stripe_events_type_idx on public.stripe_events (event_type);

-- Tier pricing config (reference; actual prices in Stripe dashboard)
-- starter: $29/mo, 100K tokens, 10 rec/mo
-- pro: $99/mo, 1M tokens, 100 rec/mo
-- enterprise: $299/mo, 10M tokens, unlimited
-- demo: free, 10K tokens, 2 rec/mo (for testing)

-- Initialize limits for demo org
insert into public.ai_token_limits (organization_id, tier, monthly_limit)
select id, 'demo', 10000 from public.organizations where tier='demo'
on conflict (organization_id) do nothing;

-- Token budget check helper
create or replace function public.check_token_budget(p_organization_id uuid, p_tokens_needed integer)
returns table(has_budget boolean, tokens_remaining bigint, org_tier text)
language sql security definer set search_path = public as $$
  select
    (l.monthly_limit - l.tokens_used_this_month) >= p_tokens_needed,
    (l.monthly_limit - l.tokens_used_this_month),
    o.tier
  from public.ai_token_limits l
  join public.organizations o on o.id = l.organization_id
  where l.organization_id = p_organization_id;
$$;

-- Token deduction helper
create or replace function public.deduct_tokens(p_organization_id uuid, p_tokens_used integer)
returns table(success boolean, tokens_remaining bigint)
language sql security definer set search_path = public as $$
  update public.ai_token_limits
  set tokens_used_this_month = tokens_used_this_month + p_tokens_used
  where organization_id = p_organization_id
    and tokens_used_this_month + p_tokens_used <= monthly_limit
  returning true as success, (monthly_limit - tokens_used_this_month - p_tokens_used) as tokens_remaining;
$$;
