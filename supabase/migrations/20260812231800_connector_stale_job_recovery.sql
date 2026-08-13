create table if not exists public.platform_connector_job_recovery_queue (
 id uuid primary key default gen_random_uuid(),
 failed_job_id uuid not null references public.platform_sync_jobs(id) on delete cascade,
 connection_id uuid not null references public.platform_connector_connections(id) on delete cascade,
 reason text not null,
 status text not null default 'pending' check(status in ('pending','dispatching','completed','dead_letter','canceled')),
 attempt_count integer not null default 0,
 max_attempts integer not null default 3,
 available_at timestamptz not null default now(),
 last_error text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(failed_job_id)
);
alter table public.platform_connector_job_recovery_queue enable row level security;
revoke all on public.platform_connector_job_recovery_queue from anon,authenticated;
grant select,insert,update,delete on public.platform_connector_job_recovery_queue to service_role;
create index if not exists idx_connector_job_recovery_due on public.platform_connector_job_recovery_queue(available_at) where status='pending';

create or replace function public.platform_recover_stale_connector_jobs(p_stale_minutes integer default 30)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n int:=0; q int:=0;
begin
  with stale as (
    update public.platform_sync_jobs
    set status='failed',completed_at=now(),error_details=coalesce(error_details,'{}'::jsonb)||jsonb_build_object('recovery_reason','stale_running_job','recovered_at',now())
    where status='running' and started_at < now()-make_interval(mins=>p_stale_minutes)
    returning id,connection_id
  )
  insert into public.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason)
  select id,connection_id,'stale_running_job' from stale on conflict(failed_job_id) do nothing;
  get diagnostics n=row_count;

  insert into public.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason,available_at)
  select j.id,j.connection_id,'transient_sync_failure',now()+interval '2 minutes'
  from public.platform_sync_jobs j
  where j.status='failed' and j.completed_at>=now()-interval '24 hours'
    and coalesce(j.attempt_count,0)<3
    and coalesce(j.error_details->>'message','') ~* '(429|rate limit|timeout|timed out|502|503|504|ECONNRESET|network|fetch failed)'
  on conflict(failed_job_id) do nothing;
  get diagnostics q=row_count;
  return jsonb_build_object('stale_recovered',n,'transient_queued',q);
end $$;
revoke all on function public.platform_recover_stale_connector_jobs(integer) from public,anon,authenticated;
grant execute on function public.platform_recover_stale_connector_jobs(integer) to service_role;

select cron.unschedule(jobid) from cron.job where jobname='iq-connector-stale-job-recovery';
select cron.schedule('iq-connector-stale-job-recovery','*/5 * * * *','select public.platform_recover_stale_connector_jobs(30);');
