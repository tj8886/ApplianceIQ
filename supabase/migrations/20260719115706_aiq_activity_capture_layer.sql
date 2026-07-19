-- Conversation & activity capture layer.
-- REUSE: public.activities extended to serve as crm_activity_items (it already had
-- org RLS, actor_user_id, and nullable entity_type/entity_id = the attachment columns).
-- NEW: sales_recordings, recording_transcripts, ai_coaching_reviews, crm_emails,
-- crm_presentations, crm-media storage bucket.
-- crm_conversation_records = view; crm_record_attachments = the entity columns on activities.

-- 1) Extend activities -> crm_activity_items shape
alter table public.activities
  add column if not exists user_id uuid references auth.users(id) on delete set null,
  add column if not exists title text,
  add column if not exists source text not null default 'manual'
    check (source in ('manual','ai_generated','email_integration','call_integration','upload')),
  add column if not exists related_file_path text,
  add column if not exists related_recording_id uuid,
  add column if not exists related_email_id uuid,
  add column if not exists related_presentation_id uuid,
  add column if not exists updated_at timestamptz not null default now();

comment on table public.activities is 'CRM activity items (crm_activity_items). entity_type/entity_id = CRM record attachment (deal|company|contact); null = unattached, linkable later.';

-- activity_type values used by the capture layer:
-- email, spec_presentation, voice_call, sales_pitch_recording, ai_coaching_review, ai_summary, note

create trigger activities_touch before update on public.activities
  for each row execute function public.touch_updated_at();

-- 2) Recordings
create table public.sales_recordings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  kind text not null default 'sales_pitch' check (kind in ('sales_pitch','voice_call')),
  file_path text not null,
  mime_type text,
  duration_seconds int,
  status text not null default 'uploaded' check (status in ('uploaded','transcribing','transcribed','failed')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index sales_recordings_org_idx on public.sales_recordings (organization_id, created_at desc);
create trigger sales_recordings_touch before update on public.sales_recordings
  for each row execute function public.touch_updated_at();

-- 3) Transcripts
create table public.recording_transcripts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  recording_id uuid not null references public.sales_recordings(id) on delete cascade,
  content text not null,
  language text,
  model text,
  status text not null default 'completed' check (status in ('completed','failed')),
  created_at timestamptz not null default now()
);
create index recording_transcripts_rec_idx on public.recording_transcripts (recording_id);

-- 4) AI coaching reviews (incl. KPI scoring vs the 7 steps of sales)
create table public.ai_coaching_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  activity_id uuid references public.activities(id) on delete cascade,
  recording_id uuid references public.sales_recordings(id) on delete set null,
  review_kind text not null default 'coaching' check (review_kind in ('coaching','summary')),
  analysis jsonb not null default '{}'::jsonb,          -- strengths, improvements, quotes, next_actions
  kpi_scores jsonb not null default '{}'::jsonb,        -- {prospecting, preparation, needs_discovery, presentation, objection_handling, closing, follow_up} 0-10
  overall_score numeric(4,1),
  model text,
  created_at timestamptz not null default now()
);
create index ai_coaching_reviews_org_idx on public.ai_coaching_reviews (organization_id, created_at desc);
create index ai_coaching_reviews_act_idx on public.ai_coaching_reviews (activity_id);

-- 5) Emails + presentations sent to clients (light records the activity refs point at)
create table public.crm_emails (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  to_email text,
  subject text not null,
  body text,
  sent_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index crm_emails_org_idx on public.crm_emails (organization_id, sent_at desc);

create table public.crm_presentations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  title text not null,
  file_path text,
  sent_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index crm_presentations_org_idx on public.crm_presentations (organization_id, created_at desc);

-- FK the activity refs now that targets exist
alter table public.activities
  add constraint activities_recording_fk foreign key (related_recording_id)
    references public.sales_recordings(id) on delete set null,
  add constraint activities_email_fk foreign key (related_email_id)
    references public.crm_emails(id) on delete set null,
  add constraint activities_presentation_fk foreign key (related_presentation_id)
    references public.crm_presentations(id) on delete set null;

-- 6) crm_conversation_records as a view (no duplicate storage)
create or replace view public.crm_conversation_records
with (security_invoker = true) as
select a.id as activity_id, a.organization_id, a.user_id, a.entity_type as crm_record_type,
       a.entity_id as crm_record_id, a.activity_type, a.title, a.summary, a.source,
       a.related_file_path, a.created_at,
       r.id as recording_id, r.kind as recording_kind, r.file_path as recording_path, r.status as recording_status,
       t.id as transcript_id, t.content as transcript,
       cr.id as coaching_review_id, cr.kpi_scores, cr.overall_score
from public.activities a
left join public.sales_recordings r on r.id = a.related_recording_id
left join public.recording_transcripts t on t.recording_id = r.id
left join lateral (select * from public.ai_coaching_reviews x where x.activity_id = a.id order by x.created_at desc limit 1) cr on true
where a.activity_type in ('voice_call','sales_pitch_recording','email','spec_presentation','ai_coaching_review','ai_summary','note');

-- 7) RLS
alter table public.sales_recordings enable row level security;
alter table public.recording_transcripts enable row level security;
alter table public.ai_coaching_reviews enable row level security;
alter table public.crm_emails enable row level security;
alter table public.crm_presentations enable row level security;

do $$
declare t text;
begin
  foreach t in array array['sales_recordings','recording_transcripts','ai_coaching_reviews','crm_emails','crm_presentations']
  loop
    execute format('create policy %I_org_select on public.%I for select using (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_insert on public.%I for insert with check (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_update on public.%I for update using (public.is_org_member(organization_id));', t, t);
    execute format('create policy %I_org_delete on public.%I for delete using (public.is_org_admin(organization_id));', t, t);
  end loop;
end $$;

-- 8) Storage: private crm-media bucket, org-scoped by first path folder = org uuid
insert into storage.buckets (id, name, public) values ('crm-media','crm-media', false)
on conflict (id) do nothing;

create policy crm_media_select on storage.objects for select to authenticated
using (bucket_id = 'crm-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.is_org_member(((storage.foldername(name))[1])::uuid));

create policy crm_media_insert on storage.objects for insert to authenticated
with check (bucket_id = 'crm-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.is_org_member(((storage.foldername(name))[1])::uuid));

create policy crm_media_delete on storage.objects for delete to authenticated
using (bucket_id = 'crm-media'
  and (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and public.is_org_admin(((storage.foldername(name))[1])::uuid));
