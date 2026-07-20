-- KPI events: append-only performance event stream, auto-captured by triggers.
create table if not exists public.kpi_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid,
  event_type text not null check (event_type in (
    'recording_uploaded','recording_transcribed','recording_analyzed',
    'roleplay_completed','coaching_generated','email_reviewed',
    'presentation_sent','follow_up_completed')),
  ref_table text,
  ref_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.kpi_events enable row level security;
create policy kpi_events_select on public.kpi_events for select using (is_org_member(organization_id));
-- No client insert/update/delete policies: events are system-generated only.

create index kpi_events_org_created_idx on public.kpi_events (organization_id, created_at desc);
create index kpi_events_org_type_idx on public.kpi_events (organization_id, event_type);

-- Trigger: recording lifecycle -> events (fires for ANY recording_source, current or future)
create or replace function public.log_recording_kpi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, new.user_id, 'recording_uploaded', 'sales_recordings', new.id,
            jsonb_build_object('source', new.recording_source, 'duration_seconds', new.duration_seconds));
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'transcribed' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_transcribed', 'sales_recordings', new.id);
    elsif new.status = 'complete' then
      insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id)
      values (new.organization_id, new.user_id, 'recording_analyzed', 'sales_recordings', new.id);
    end if;
  end if;
  return new;
end $$;

drop trigger if exists sales_recordings_kpi on public.sales_recordings;
create trigger sales_recordings_kpi
  after insert or update on public.sales_recordings
  for each row execute function public.log_recording_kpi();

-- Trigger: coaching reviews -> coaching_generated (with score in metadata)
create or replace function public.log_coaching_kpi() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.review_kind = 'coaching' then
    insert into kpi_events (organization_id, event_type, ref_table, ref_id, metadata)
    values (new.organization_id, 'coaching_generated', 'ai_coaching_reviews', new.id,
            jsonb_build_object('overall_score', new.overall_score));
  end if;
  return new;
end $$;

drop trigger if exists ai_coaching_reviews_kpi on public.ai_coaching_reviews;
create trigger ai_coaching_reviews_kpi
  after insert on public.ai_coaching_reviews
  for each row execute function public.log_coaching_kpi();

-- Backfill from existing data (no history overwrite; append snapshot of what already happened)
insert into kpi_events (organization_id, user_id, event_type, ref_table, ref_id, metadata, created_at)
select organization_id, user_id, 'recording_uploaded', 'sales_recordings', id,
       jsonb_build_object('source', recording_source, 'backfilled', true), created_at
from public.sales_recordings;

insert into kpi_events (organization_id, event_type, ref_table, ref_id, metadata, created_at)
select organization_id, 'coaching_generated', 'ai_coaching_reviews', id,
       jsonb_build_object('overall_score', overall_score, 'backfilled', true), created_at
from public.ai_coaching_reviews where review_kind = 'coaching';
