-- Extend sales_recordings for the browser capture feature + future external sources
alter table public.sales_recordings
  add column if not exists crm_record_id uuid,
  add column if not exists crm_record_type text,
  add column if not exists recording_source text not null default 'browser',
  add column if not exists file_name text,
  add column if not exists file_size_bytes bigint,
  add column if not exists consent_confirmed boolean not null default false,
  add column if not exists consent_confirmed_at timestamptz,
  add column if not exists transcript_id uuid references public.recording_transcripts(id) on delete set null,
  add column if not exists coaching_review_id uuid references public.ai_coaching_reviews(id) on delete set null;

comment on column public.sales_recordings.file_path is 'Storage path in the crm-media bucket (spec name: storage_path)';

alter table public.sales_recordings
  add constraint sales_recordings_crm_record_type_check
  check (crm_record_type is null or crm_record_type in ('deal','contact','company'));

alter table public.sales_recordings
  add constraint sales_recordings_recording_source_check
  check (recording_source in ('browser','wearable','phone_system','uploaded_file','meeting_platform'));

-- Widen status lifecycle: uploaded -> transcribing -> transcribed -> analyzing -> complete | failed
alter table public.sales_recordings drop constraint if exists sales_recordings_status_check;
alter table public.sales_recordings
  add constraint sales_recordings_status_check
  check (status in ('uploaded','transcribing','transcribed','analyzing','complete','failed'));

create index if not exists sales_recordings_org_created_idx
  on public.sales_recordings (organization_id, created_at desc);
create index if not exists sales_recordings_crm_record_idx
  on public.sales_recordings (crm_record_type, crm_record_id) where crm_record_id is not null;

-- File size safeguard at the storage layer (50 MB hard cap; app enforces 25 MB)
update storage.buckets set file_size_limit = 52428800 where id = 'crm-media';
