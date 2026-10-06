-- Metadata preflight only. Never retrieve transcript text or recording bytes.
create function tj_private.recording_review_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();rec record;tr uuid;action text;org uuid;
begin
 if actor is null then raise exception using errcode='42501',message='recording_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192
  or exists(select 1 from jsonb_object_keys(p_body) k where k not in ('organization_id','recording_id','action'))
  or exists(select 1 from jsonb_each(p_body) e where jsonb_typeof(e.value)<>'string') then raise exception using errcode='22023',message='invalid_request';end if;
 action:=coalesce(p_body->>'action','review');
 if action not in ('status','review') or p_body->>'recording_id' is null then raise exception using errcode='22023',message='invalid_request';end if;
 select id,organization_id,user_id,consent_confirmed,transcript_id into rec from tj.sales_recordings where id=(p_body->>'recording_id')::uuid;
 if rec.id is null then raise exception using errcode='42501',message='recording_access_denied';end if;
 org:=rec.organization_id;
 if (p_body ? 'organization_id' and (p_body->>'organization_id')::uuid is distinct from org) or not exists(
  select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id
  where o.id=org and o.status='active' and o.deleted_at is null and m.user_id=actor and m.status='active'
   and (rec.user_id=actor or m.role in ('owner','admin','super_admin'))
 ) then raise exception using errcode='42501',message='recording_access_denied';end if;
 if rec.consent_confirmed is distinct from true then
  return jsonb_build_object('ok',action='status','error',case when action<>'status' then 'consent_required' else null end,'organization_id',org,'recording_id',rec.id,'consent_confirmed',false,'transcript_metadata_checked',false,'completed_transcript_linked',false,'review_enabled',false,'executed',false,'provider_called',false,'reviews_created',0);
 end if;
 if rec.transcript_id is not null then
  select id into tr from tj.recording_transcripts where id=rec.transcript_id and recording_id=rec.id and organization_id=org and status='completed';
 else
  select id into tr from tj.recording_transcripts where recording_id=rec.id and organization_id=org and status='completed' order by created_at desc,id desc limit 1;
 end if;
 return jsonb_build_object('ok',action='status','error',case when action='status' then null when tr is null then 'completed_transcript_required' else 'recording_review_verification_required' end,
  'organization_id',org,'recording_id',rec.id,'consent_confirmed',true,'transcript_metadata_checked',true,'completed_transcript_linked',tr is not null,
  'review_enabled',false,'executed',false,'provider_called',false,'reviews_created',0,
  'blockers',jsonb_build_array('transcript_provenance_privacy_and_version_verification_required','tier_provider_and_cost_governance_required','complete_finite_competency_scores_and_transcript_grounded_evidence_validation_required','atomic_idempotent_review_finalization_and_consent_recheck_required'));
end $$;
revoke all on function tj_private.recording_review_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.recording_review_preflight(jsonb) to authenticated;
create function public.tj_recording_review_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.recording_review_preflight(p_body);$$;
revoke all on function public.tj_recording_review_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_recording_review_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
