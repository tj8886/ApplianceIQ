-- Bounded queue previews only. Never send, claim jobs, retry, or create/elevate a bot.
create function tj_private.connector_dispatch_preview(p_kind text,p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;conn uuid;after_id uuid;mode text;items jsonb;more boolean;
begin
 if actor is null then raise exception using errcode='42501',message='dispatch_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','connection_id','mode','after_id'))
  or exists(select 1 from jsonb_each(p_body)e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;conn:=(p_body->>'connection_id')::uuid;after_id:=(p_body->>'after_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin'))
  or (conn is not null and not exists(select 1 from tj.platform_connector_connections c where c.id=conn and c.organization_id=org)) then raise exception using errcode='42501',message='dispatch_access_denied';end if;
 if p_kind is null or p_kind not in ('alerts','recovery') then raise exception using errcode='22023',message='invalid_dispatch_kind';end if;
 mode:=coalesce(p_body->>'mode',case when p_kind='alerts' then 'manual' else 'dispatch' end);
 if mode<>'preview' then
  if mode not in ('manual','dispatch','scheduled') then raise exception using errcode='22023',message='invalid_mode';end if;
  return jsonb_build_object('ok',false,'error','connector_dispatch_verification_required','executed',false,'sent',0,'processed',0,'dispatch_enabled',false,'scheduler_enabled',false);
 end if;
 if p_kind='alerts' then
  with candidates as materialized (
   select d.id,d.alert_id,c.id connection_id,d.channel,d.status,d.attempt_count,d.max_attempts,d.next_attempt_at
   from tj.platform_connector_alert_deliveries d join tj.platform_connector_alerts a on a.id=d.alert_id
   join tj.platform_connector_connections c on c.id=a.connection_id
   where c.organization_id=org and d.organization_id=org and (conn is null or c.id=conn) and (after_id is null or d.id>after_id)
    and a.status in ('open','acknowledged') and d.status in ('pending','failed') and d.channel in ('in_app','email','email_escalation')
    and d.next_attempt_at<=statement_timestamp() and d.attempt_count>=0 and d.max_attempts>0 and d.attempt_count<d.max_attempts
    and exists(select 1 from tj.organization_members m where m.organization_id=org and m.user_id=d.user_id and m.status='active')
   order by d.id limit 26)
  select (select count(*)>25 from candidates),coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select * from candidates order by id limit 25)x),'[]') into more,items;
 else
  with candidates as materialized (
   select q.id,q.failed_job_id,c.id connection_id,q.status,q.attempt_count,q.max_attempts,q.available_at
   from tj.platform_connector_job_recovery_queue q join tj.platform_connector_connections c on c.id=q.connection_id
   join tj.platform_sync_jobs j on j.id=q.failed_job_id and j.connection_id=c.id
   where c.organization_id=org and (conn is null or c.id=conn) and (after_id is null or q.id>after_id)
    and q.status='pending' and j.status in ('failed','partial') and q.available_at<=statement_timestamp()
    and q.attempt_count>=0 and q.max_attempts>0 and q.attempt_count<q.max_attempts
   order by q.id limit 26)
  select (select count(*)>25 from candidates),coalesce((select jsonb_agg(to_jsonb(x) order by x.id) from (select * from candidates order by id limit 25)x),'[]') into more,items;
 end if;
 return jsonb_build_object('ok',true,'organization_id',org,'kind',p_kind,'preview_only',true,'executed',false,'dispatch_enabled',false,'scheduler_enabled',false,
  'items',items,'page_count',jsonb_array_length(items),'has_more',more,'next_after_id',case when more then items->24->>'id' else null end,
  'basis','recorded_due_metadata_only','blockers',case when p_kind='alerts' then jsonb_build_array('verified_sender_and_recipient_identity_required','idempotent_outbox_and_atomic_delivery_claim_required','authorized_escalation_and_scheduler_review_required')
   else jsonb_build_array('connector_destination_readiness_required','reviewed_least_privilege_worker_identity_required','atomic_retry_claim_and_connector_idempotency_required','completion_reconciliation_and_scheduler_review_required') end);
end $$;
revoke all on function tj_private.connector_dispatch_preview(text,jsonb) from public,anon,service_role;
grant execute on function tj_private.connector_dispatch_preview(text,jsonb) to authenticated;
create function public.tj_connector_alert_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.connector_dispatch_preview('alerts',p_body);$$;
create function public.tj_connector_recovery_preview(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.connector_dispatch_preview('recovery',p_body);$$;
revoke all on function public.tj_connector_alert_preview(jsonb),public.tj_connector_recovery_preview(jsonb) from public,anon,service_role;
grant execute on function public.tj_connector_alert_preview(jsonb),public.tj_connector_recovery_preview(jsonb) to authenticated;
notify pgrst,'reload schema';
