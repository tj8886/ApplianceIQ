-- CHQ legacy tables have no organization_id. Do not infer ownership or select recipients.
create function tj_private.chq_notification_preflight(p_workflow text,p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;action text;
begin
 if actor is null then raise exception using errcode='42501',message='notification_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('organization_id','action'))
  or exists(select 1 from jsonb_each(p_body) e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) then raise exception using errcode='42501',message='notification_access_denied';end if;
 if p_workflow is null or p_workflow not in ('booking','contractor','reminders') then raise exception using errcode='22023',message='invalid_workflow';end if;
 action:=coalesce(p_body->>'action',case when p_workflow='reminders' then 'run' else 'send' end);
 if action<>'status' and action<>(case when p_workflow='reminders' then 'run' else 'send' end) then raise exception using errcode='22023',message='invalid_action';end if;
 return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'chq_notification_verification_required' else null end,
  'workflow',p_workflow,'organization_id',org,'preflight_only',true,'notification_enabled',false,'scheduler_enabled',false,'recipient_selection_enabled',false,
  'executed',false,'sent',0,'delivery_attempts',0,'notification_records_created',0,
  'blockers',jsonb_build_array('chq_explicit_record_tenant_ownership_required','verified_event_authorization_and_replay_protection_required','tenant_scoped_recipient_eligibility_required','verified_sender_and_delivery_adapter_required','escaped_templates_and_approved_app_links_required','idempotent_outbox_and_delivery_result_required')
    ||case when p_workflow='reminders' then jsonb_build_array('booking_timezone_and_dst_rules_required','reminder_deduplication_and_schedule_review_required') else '[]'::jsonb end);
end $$;
revoke all on function tj_private.chq_notification_preflight(text,jsonb) from public,anon,service_role;
grant execute on function tj_private.chq_notification_preflight(text,jsonb) to authenticated;
create function public.tj_chq_booking_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.chq_notification_preflight('booking',p_body);$$;
create function public.tj_chq_contractor_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.chq_notification_preflight('contractor',p_body);$$;
create function public.tj_chq_reminders_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.chq_notification_preflight('reminders',p_body);$$;
revoke all on function public.tj_chq_booking_preflight(jsonb),public.tj_chq_contractor_preflight(jsonb),public.tj_chq_reminders_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_chq_booking_preflight(jsonb),public.tj_chq_contractor_preflight(jsonb),public.tj_chq_reminders_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
