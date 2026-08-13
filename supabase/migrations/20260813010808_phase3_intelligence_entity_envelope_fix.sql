alter table public.platform_identity_links add column if not exists intelligence_entity_id uuid references public.intelligence_entities(id) on delete set null;
create index if not exists idx_identity_links_intelligence_entity on public.platform_identity_links(intelligence_entity_id) where intelligence_entity_id is not null;

create or replace function public.platform_emit_intelligence_event(p_organization_id uuid,p_event_type text,p_source_system text,p_source_record_id text,p_subject_entity_type text default null,p_entity_id uuid default null,p_store_id uuid default null,p_actor_id uuid default null,p_correlation_id uuid default null,p_causation_id uuid default null,p_dedupe_key text default null,p_payload jsonb default '{}'::jsonb,p_occurred_at timestamptz default now(),p_identity_confidence numeric default null,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_subject text; v_intel_type text; v_intel_entity uuid; v_name text;
begin
 select et.subject_entity_type,ce.intelligence_entity_type into v_subject,v_intel_type from public.platform_canonical_event_types et left join public.platform_canonical_entity_types ce on ce.key=et.subject_entity_type where et.key=p_event_type and et.active=true;
 if v_subject is null then raise exception 'unknown_event_type:%',p_event_type; end if;
 if p_subject_entity_type is not null and p_subject_entity_type<>v_subject then raise exception 'event_subject_mismatch:% expected % got %',p_event_type,v_subject,p_subject_entity_type; end if;
 if p_entity_id is not null then select id into v_intel_entity from public.intelligence_entities where id=p_entity_id and organization_id=p_organization_id; end if;
 if v_intel_entity is null then select id into v_intel_entity from public.intelligence_entities where organization_id=p_organization_id and source_system=p_source_system and source_record_id=p_source_record_id limit 1; end if;
 if v_intel_entity is null then
   v_name:=coalesce(nullif(p_payload->>'name',''),nullif(p_payload->>'display_name',''),nullif(p_payload->>'model',''),nullif(p_payload->>'pos_transaction_id',''),nullif(p_payload->>'course_key',''),v_subject||':'||p_source_record_id);
   insert into public.intelligence_entities(organization_id,entity_type,canonical_name,slug,source_system,source_record_id,status,metadata,created_at,updated_at)
   values(p_organization_id,coalesce(v_intel_type,v_subject),v_name,null,p_source_system,p_source_record_id,'active',jsonb_build_object('business_entity_id',p_entity_id,'subject_entity_type',v_subject,'phase3',true),now(),now())
   on conflict(organization_id,source_system,source_record_id) do update set updated_at=now(),metadata=intelligence_entities.metadata||jsonb_build_object('business_entity_id',coalesce(p_entity_id,(intelligence_entities.metadata->>'business_entity_id')::uuid),'subject_entity_type',v_subject,'phase3',true)
   returning id into v_intel_entity;
 end if;
 insert into public.intelligence_events(organization_id,entity_id,event_type,canonical_event_type,source_system,source_record_id,actor_id,correlation_id,causation_id,payload,occurred_at,subject_entity_type,store_id,event_version,dedupe_key,processing_status,identity_confidence,metadata)
 values(p_organization_id,v_intel_entity,p_event_type,p_event_type,p_source_system,p_source_record_id,p_actor_id,coalesce(p_correlation_id,gen_random_uuid()),p_causation_id,coalesce(p_payload,'{}'::jsonb),coalesce(p_occurred_at,now()),v_subject,p_store_id,1,p_dedupe_key,'ready',p_identity_confidence,coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('business_entity_id',p_entity_id))
 on conflict(organization_id,source_system,dedupe_key) where dedupe_key is not null do update set metadata=intelligence_events.metadata||excluded.metadata returning id into v_id;
 update public.platform_identity_links set intelligence_entity_id=v_intel_entity,last_seen_at=now() where organization_id=p_organization_id and entity_type=v_subject and canonical_id=p_entity_id and intelligence_entity_id is null;
 return v_id;
end $$;
revoke all on function public.platform_emit_intelligence_event(uuid,text,text,text,text,uuid,uuid,uuid,uuid,uuid,text,jsonb,timestamptz,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.platform_emit_intelligence_event(uuid,text,text,text,text,uuid,uuid,uuid,uuid,uuid,text,jsonb,timestamptz,numeric,jsonb) to service_role;