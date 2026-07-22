-- Email dispatch support (Resend transport)
alter table public.crm_emails
  add column if not exists status text not null default 'sent',
  add column if not exists from_email text,
  add column if not exists provider_message_id text;
alter table public.crm_emails drop constraint if exists crm_emails_status_check;
alter table public.crm_emails add constraint crm_emails_status_check check (status in ('queued','sent','failed'));
create index if not exists crm_emails_org_created_idx on public.crm_emails (organization_id, created_at desc);
