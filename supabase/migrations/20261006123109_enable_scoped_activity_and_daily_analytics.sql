-- Manual per-tenant UTC rollups. No cron, provider call or global rollup.
alter table tj.ai_daily_analytics add column cost_complete boolean not null default false,
 add column unknown_cost_requests integer not null default 0,
 add column unknown_tier_requests integer not null default 0;
alter table tj.ai_daily_analytics alter column total_cost_usd drop not null,
 alter column fast_cost_usd drop not null,alter column standard_cost_usd drop not null,alter column strong_cost_usd drop not null;
create function tj_private.daily_analytics(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();org uuid;day date;start_at timestamptz;stop_at timestamptz;s record;r tj.ai_daily_analytics%rowtype;answer jsonb;
begin
 if actor is null then raise exception using errcode='42501',message='analytics_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192 or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('organization_id','date')) then raise exception using errcode='22023',message='invalid_request';end if;
 org:=(p_body->>'organization_id')::uuid;
 if org is null or org='00000000-0000-0000-0000-000000000000'::uuid or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id where m.organization_id=org and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin') and o.status='active' and o.deleted_at is null) then raise exception using errcode='42501',message='analytics_access_denied';end if;
 if p_body ? 'date' and (jsonb_typeof(p_body->'date')<>'string' or (p_body->>'date') !~ '^\d{4}-\d{2}-\d{2}$') then raise exception using errcode='22023',message='invalid_date';end if;
 day:=coalesce((p_body->>'date')::date,(now() at time zone 'UTC')::date-1);
 if day>(now() at time zone 'UTC')::date then raise exception using errcode='22023',message='future_date';end if;
 start_at:=day::timestamp at time zone 'UTC';stop_at:=(day+1)::timestamp at time zone 'UTC';
 perform pg_advisory_xact_lock(hashtextextended('tj.daily-analytics.'||org::text||'.'||day::text,0));
 with feedback as materialized (select count(*) filter(where signal_type='thumbs_up') up,count(*) filter(where signal_type='thumbs_down') down,count(*) filter(where signal_type='correction') corrections
 from tj.ai_feedback_signals fb where fb.organization_id=org and fb.created_at>=start_at and fb.created_at<stop_at
  and (fb.conversation_id is null or exists(select 1 from tj.ai_conversations c where c.id=fb.conversation_id and c.organization_id=org))
  and (fb.turn_id is null or exists(select 1 from tj.ai_conversation_turns t join tj.ai_conversations c on c.id=t.conversation_id where t.id=fb.turn_id and c.organization_id=org and (fb.conversation_id is null or fb.conversation_id=c.id)))), turns as materialized (
  select c.user_id,t.persona_name,t.metadata from tj.ai_conversation_turns t join tj.ai_conversations c on c.id=t.conversation_id
  where c.organization_id=org and t.role='assistant' and t.created_at>=start_at and t.created_at<stop_at order by t.id limit 100001
 ), measured as (
  select *,metadata->>'tier' tier,case when jsonb_typeof(metadata->'total_cost_usd')='number' and length(metadata->>'total_cost_usd')<=30
   then case when (metadata->>'total_cost_usd')::numeric between 0 and 1000000 then (metadata->>'total_cost_usd')::numeric else null end else null end cost from turns
 ) select count(*) total,count(*) filter(where tier='deterministic') deterministic,count(*) filter(where tier='fast') fast,
  count(*) filter(where tier='standard') standard,count(*) filter(where tier='strong') strong,
  count(*) filter(where tier is null or tier not in ('deterministic','fast','standard','strong')) unknown_tier,
  count(*) filter(where cost is null) unknown_cost,count(*) filter(where metadata->'failover_used'='true'::jsonb) failover,count(distinct user_id) users,
  case when count(*) filter(where cost is null)>0 then null else round(coalesce(sum(cost),0),6) end cost,
  case when count(*) filter(where cost is null and tier='fast')>0 then null else round(coalesce(sum(cost) filter(where tier='fast'),0),6) end fast_cost,
  case when count(*) filter(where cost is null and tier='standard')>0 then null else round(coalesce(sum(cost) filter(where tier='standard'),0),6) end standard_cost,
  case when count(*) filter(where cost is null and tier='strong')>0 then null else round(coalesce(sum(cost) filter(where tier='strong'),0),6) end strong_cost,
  (select coalesce(jsonb_object_agg(p.name,p.n),'{}') from (select case when length(persona_name) between 1 and 128 then persona_name else 'unknown' end name,count(*) n from turns group by 1)p) persona_distribution
,
  (select up from feedback) up,(select down from feedback) down,(select corrections from feedback) corrections,
  (select count(*) from tj.ai_knowledge_gaps g where g.organization_id=org and g.last_seen_at>=start_at and g.last_seen_at<stop_at) gap_count
 into s from measured;
 if s.total>100000 then raise exception using errcode='54000',message='day_too_large';end if;
 insert into tj.ai_daily_analytics(analytics_date,organization_id,total_requests,deterministic_requests,fast_tier_requests,standard_tier_requests,strong_tier_requests,failover_count,total_cost_usd,fast_cost_usd,standard_cost_usd,strong_cost_usd,thumbs_up_count,thumbs_down_count,correction_count,satisfaction_rate,persona_distribution,knowledge_gaps_detected,active_users,cost_complete,unknown_cost_requests,unknown_tier_requests,updated_at)
 values(day,org,s.total,s.deterministic,s.fast,s.standard,s.strong,s.failover,s.cost,s.fast_cost,s.standard_cost,s.strong_cost,s.up,s.down,s.corrections,case when s.up+s.down>0 then round(s.up::numeric/(s.up+s.down),4) else null end,s.persona_distribution,s.gap_count,s.users,s.unknown_cost=0,s.unknown_cost,s.unknown_tier,clock_timestamp())
 on conflict (analytics_date,(coalesce(organization_id,'00000000-0000-0000-0000-000000000000'::uuid))) do update set
 total_requests=excluded.total_requests,deterministic_requests=excluded.deterministic_requests,fast_tier_requests=excluded.fast_tier_requests,standard_tier_requests=excluded.standard_tier_requests,strong_tier_requests=excluded.strong_tier_requests,failover_count=excluded.failover_count,total_cost_usd=excluded.total_cost_usd,fast_cost_usd=excluded.fast_cost_usd,standard_cost_usd=excluded.standard_cost_usd,strong_cost_usd=excluded.strong_cost_usd,thumbs_up_count=excluded.thumbs_up_count,thumbs_down_count=excluded.thumbs_down_count,correction_count=excluded.correction_count,satisfaction_rate=excluded.satisfaction_rate,persona_distribution=excluded.persona_distribution,knowledge_gaps_detected=excluded.knowledge_gaps_detected,active_users=excluded.active_users,cost_complete=excluded.cost_complete,unknown_cost_requests=excluded.unknown_cost_requests,unknown_tier_requests=excluded.unknown_tier_requests,updated_at=excluded.updated_at returning * into r;
 answer:=jsonb_build_object('ok',true,'date',day,'timezone','UTC','organization_id',org,'orgs_processed',1,'assistant_turns_processed',s.total,'analytics',to_jsonb(r),'scheduled',false,'partial_day',day=(now() at time zone 'UTC')::date);
 if octet_length(answer::text)>262144 then raise exception using errcode='54000',message='rollup_too_large';end if;
 return answer;
end $$;
revoke all on function tj_private.daily_analytics(jsonb) from public,anon,service_role;
grant execute on function tj_private.daily_analytics(jsonb) to authenticated;
create function public.tj_daily_analytics(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.daily_analytics(p_body);$$;
revoke all on function public.tj_daily_analytics(jsonb) from public,anon,service_role;
grant execute on function public.tj_daily_analytics(jsonb) to authenticated;

-- No audio/text is retrieved. The legacy transcribe path missed its consent check.
create function tj_private.activity_preflight(p_body jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=tj_private.current_source_user_id();a tj.activities%rowtype;rec tj.sales_recordings%rowtype;org uuid;mode text;admin boolean;
begin
 if actor is null then raise exception using errcode='42501',message='activity_access_denied';end if;
 if jsonb_typeof(p_body) is distinct from 'object' or octet_length(p_body::text)>8192 or exists(select 1 from jsonb_object_keys(p_body)k where k not in ('mode','activity_id','organization_id','question')) then raise exception using errcode='22023',message='invalid_request';end if;
 mode:=coalesce(p_body->>'mode','status');if mode not in ('status','process','transcribe','coach','summarize','persona_coach') then raise exception using errcode='22023',message='invalid_mode';end if;
 if p_body ? 'activity_id' then
  select * into a from tj.activities where id=(p_body->>'activity_id')::uuid and deleted_at is null;
  if a.id is null then raise exception using errcode='42501',message='activity_access_denied';end if;org:=a.organization_id;
  if p_body ? 'organization_id' and (p_body->>'organization_id')::uuid is distinct from org then raise exception using errcode='42501',message='activity_access_denied';end if;
 else org:=(p_body->>'organization_id')::uuid;if mode not in ('status','persona_coach') then raise exception using errcode='22023',message='activity_id_required';end if;end if;
 if org is null or not exists(select 1 from tj.organization_members m join tj.organizations o on o.id=m.organization_id where m.organization_id=org and m.user_id=actor and m.status='active' and o.status='active' and o.deleted_at is null) then raise exception using errcode='42501',message='activity_access_denied';end if;
 select exists(select 1 from tj.organization_members m where m.organization_id=org and m.user_id=actor and m.status='active' and m.role in ('owner','admin','super_admin')) into admin;
 if a.id is not null and not admin and a.actor_user_id is distinct from actor and a.user_id is distinct from actor then raise exception using errcode='42501',message='activity_access_denied';end if;
 if a.related_recording_id is not null then
  select * into rec from tj.sales_recordings where id=a.related_recording_id and organization_id=org;
  if rec.id is null or (not admin and rec.user_id is distinct from actor) then raise exception using errcode='42501',message='recording_access_denied';end if;
  if mode<>'status' and not rec.consent_confirmed then return jsonb_build_object('ok',false,'error','consent_not_confirmed','executed',false);end if;
  if mode<>'status' and (coalesce(rec.file_size_bytes,0)>26214400 or coalesce(rec.duration_seconds,0)>10800) then return jsonb_build_object('ok',false,'error','recording_limits_exceeded','executed',false);end if;
 elsif mode in ('process','transcribe') then raise exception using errcode='22023',message='recording_required';end if;
 if mode='persona_coach' and (jsonb_typeof(p_body->'question') is distinct from 'string' or length(btrim(p_body->>'question')) not between 1 and 4000) then raise exception using errcode='22023',message='question_required';end if;
 if mode<>'status' then return jsonb_build_object('ok',false,'error','activity_processing_verification_required','executed',false,'provider_called',false);end if;
 return jsonb_build_object('ok',true,'organization_id',org,'activity_accessible',a.id is not null,'recording_attached',rec.id is not null,'consent_confirmed',coalesce(rec.consent_confirmed,false),'processing_enabled',false,'executed',false);
end $$;
revoke all on function tj_private.activity_preflight(jsonb) from public,anon,service_role;
grant execute on function tj_private.activity_preflight(jsonb) to authenticated;
create function public.tj_activity_preflight(p_body jsonb) returns jsonb language sql security invoker set search_path='' as $$select tj_private.activity_preflight(p_body);$$;
revoke all on function public.tj_activity_preflight(jsonb) from public,anon,service_role;
grant execute on function public.tj_activity_preflight(jsonb) to authenticated;
notify pgrst,'reload schema';
