-- Closeout: drop duplicate index flagged by performance advisor
drop index if exists public.sales_recordings_org_idx;
-- Hot-path FK covering indexes for the recording/coaching pipeline
create index if not exists sales_recordings_user_idx on public.sales_recordings (user_id);
create index if not exists sales_recordings_transcript_idx on public.sales_recordings (transcript_id) where transcript_id is not null;
create index if not exists sales_recordings_review_idx on public.sales_recordings (coaching_review_id) where coaching_review_id is not null;
create index if not exists ai_coaching_reviews_recording_idx on public.ai_coaching_reviews (recording_id) where recording_id is not null;
create index if not exists recording_transcripts_org_idx on public.recording_transcripts (organization_id);
create index if not exists activities_recording_idx on public.activities (related_recording_id) where related_recording_id is not null;
