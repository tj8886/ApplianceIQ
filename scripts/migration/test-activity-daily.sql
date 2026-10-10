begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;conv uuid;foreign_conv uuid;recording uuid;activity uuid;d timestamptz:=((now() at time zone 'UTC')::date-1)::timestamp at time zone 'UTC';begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback analytics','rollback-analytics-'||gen_random_uuid()) returning id into org;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 insert into tj.organizations(name,slug) values('Rollback foreign analytics','rollback-analytics-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.ai_conversations(user_id,organization_id,title) values(actor,org,'PRIVATE TITLE') returning id into conv;
 insert into tj.ai_conversations(user_id,organization_id,title) values(actor,other,'PRIVATE FOREIGN') returning id into foreign_conv;
 insert into tj.ai_conversation_turns(conversation_id,role,content,persona_name,metadata,created_at) values
 (conv,'assistant','PRIVATE TEXT','TJ','{"tier":"fast","total_cost_usd":0.01,"failover_used":true}',d),
 (conv,'assistant','PRIVATE TEXT','TJ','{"tier":"standard","total_cost_usd":0.02}',d+interval '1 second'),
 (conv,'assistant','PRIVATE TEXT','Natalie','{"tier":"strong","total_cost_usd":0.03}',d+interval '2 seconds'),
 (conv,'assistant','PRIVATE TEXT','Natalie','{"tier":"deterministic","total_cost_usd":0}',d+interval '3 seconds'),
 (conv,'user','PRIVATE TEXT','TJ','{}',d),
 (foreign_conv,'assistant','PRIVATE FOREIGN','FOREIGN','{"tier":"strong","total_cost_usd":999}',d);
 with more as (insert into tj.ai_conversations(user_id,organization_id) select actor,org from generate_series(1,501) returning id)
 insert into tj.ai_conversation_turns(conversation_id,role,content,persona_name,metadata,created_at) select id,'assistant','PRIVATE TEXT','TJ','{"tier":"fast","total_cost_usd":0.001}',d from more;
 insert into tj.ai_feedback_signals(user_id,organization_id,conversation_id,signal_type,created_at) values(actor,org,conv,'thumbs_up',d),(actor,org,conv,'thumbs_down',d),(actor,org,conv,'correction',d),(actor,org,foreign_conv,'thumbs_up',d),(actor,other,foreign_conv,'thumbs_up',d);
 insert into tj.ai_knowledge_gaps(query_text,organization_id,last_seen_at) values('PRIVATE GAP',org,d),('PRIVATE FOREIGN GAP',other,d),('PRIVATE GLOBAL GAP',null,d);
 insert into tj.sales_recordings(organization_id,user_id,file_path,consent_confirmed) values(org,actor,'private/must-not-download.webm',false) returning id into recording;
 insert into tj.activities(organization_id,actor_user_id,entity_type,activity_type,related_recording_id) values(org,actor,'contact','call',recording) returning id into activity;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.analytics.native',native::text,true);perform set_config('test.analytics.actor',actor::text,true);perform set_config('test.analytics.org',org::text,true);perform set_config('test.analytics.other',other::text,true);perform set_config('test.analytics.conv',conv::text,true);perform set_config('test.analytics.recording',recording::text,true);perform set_config('test.analytics.activity',activity::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;r2 jsonb;mode text;begin
 r:=public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org')));
 if r#>>'{analytics,total_requests}'<>'505' or (r#>>'{analytics,total_cost_usd}')::numeric<>0.561 or r#>>'{analytics,fast_tier_requests}'<>'502' or r#>>'{analytics,knowledge_gaps_detected}'<>'1' or r#>>'{analytics,thumbs_up_count}'<>'1' or (r#>>'{analytics,satisfaction_rate}')::numeric<>0.5 or r#>>'{analytics,cost_complete}'<>'true' or r::text like '%PRIVATE%' or r::text like '%FOREIGN%' then raise exception 'rollup_scope_counts_or_cost_failed';end if;
 r2:=public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org')));if r2#>>'{analytics,id}'<>r#>>'{analytics,id}' then raise exception 'duplicate_day_created';end if;
 begin perform public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.other')));raise exception 'foreign_rollup_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org'),'date','2026-02-30'));raise exception 'bad_date_accepted';exception when datetime_field_overflow then null;end;
 begin perform public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org'),'date','9999-01-01'));raise exception 'future_day_accepted';exception when invalid_parameter_value then null;end;
 r:=public.tj_activity_preflight(jsonb_build_object('mode','status','activity_id',current_setting('test.analytics.activity')));if r->>'consent_confirmed'<>'false' or r->>'processing_enabled'<>'false' or r::text like '%private/%' then raise exception 'unsafe_activity_status';end if;
 foreach mode in array array['process','transcribe','coach','summarize'] loop r:=public.tj_activity_preflight(jsonb_build_object('mode',mode,'activity_id',current_setting('test.analytics.activity')));if r->>'error'<>'consent_not_confirmed' or r->>'executed'<>'false' then raise exception 'missing_consent_accepted';end if;end loop;
 begin perform public.tj_activity_preflight(jsonb_build_object('activity_id',current_setting('test.analytics.activity'),'organization_id',current_setting('test.analytics.other')));raise exception 'mismatched_activity_org_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org')));raise exception 'unmapped_rollup_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_activity_preflight(jsonb_build_object('activity_id',current_setting('test.analytics.activity')));raise exception 'unmapped_activity_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.analytics.native'),true);
end $$;
reset role;
insert into tj.ai_conversation_turns(conversation_id,role,content,metadata,created_at) values(current_setting('test.analytics.conv')::uuid,'assistant','PRIVATE MISSING COST','{"tier":"unknown","total_cost_usd":"bad"}',((now() at time zone 'UTC')::date)::timestamp at time zone 'UTC'-interval '1 microsecond');
update tj.sales_recordings set consent_confirmed=true where id=current_setting('test.analytics.recording')::uuid;
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org')));if r#>>'{analytics,total_requests}'<>'506' or r#>>'{analytics,total_cost_usd}' is not null or r#>>'{analytics,cost_complete}'<>'false' or r#>>'{analytics,unknown_cost_requests}'<>'1' or r#>>'{analytics,unknown_tier_requests}'<>'1' then raise exception 'missing_cost_or_end_boundary_failed';end if;
 r:=public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org'),'date',((now() at time zone 'UTC')::date)::text));if r#>>'{analytics,total_requests}'<>'0' or r#>>'{analytics,satisfaction_rate}' is not null or (r#>>'{analytics,total_cost_usd}')::numeric<>0 then raise exception 'empty_day_failed';end if;
 r:=public.tj_activity_preflight(jsonb_build_object('mode','transcribe','activity_id',current_setting('test.analytics.activity')));if r->>'error'<>'activity_processing_verification_required' then raise exception 'provider_processing_accepted';end if;
end $$;
reset role;
update tj.sales_recordings set organization_id=current_setting('test.analytics.other')::uuid where id=current_setting('test.analytics.recording')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_activity_preflight(jsonb_build_object('activity_id',current_setting('test.analytics.activity')));raise exception 'foreign_recording_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
update tj.sales_recordings set organization_id=current_setting('test.analytics.org')::uuid where id=current_setting('test.analytics.recording')::uuid;
update tj.organization_members set role='member' where organization_id=current_setting('test.analytics.org')::uuid and user_id=current_setting('test.analytics.actor')::uuid;
set local role authenticated;
do $$declare r jsonb;begin
 begin perform public.tj_daily_analytics(jsonb_build_object('organization_id',current_setting('test.analytics.org')));raise exception 'nonadmin_rollup_accepted';exception when insufficient_privilege then null;end;
 r:=public.tj_activity_preflight(jsonb_build_object('activity_id',current_setting('test.analytics.activity')));if r->>'ok'<>'true' then raise exception 'owner_activity_denied';end if;
end $$;
reset role;
update tj.activities set actor_user_id=null,user_id=null where id=current_setting('test.analytics.activity')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_activity_preflight(jsonb_build_object('activity_id',current_setting('test.analytics.activity')));raise exception 'unowned_activity_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_daily_analytics(jsonb)','tj_private.daily_analytics(jsonb)','public.tj_activity_preflight(jsonb)','tj_private.activity_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if exists(select 1 from tj.sales_recordings where id=current_setting('test.analytics.recording')::uuid and status<>'uploaded') then raise exception 'recording_mutated';end if;
 if exists(select 1 from tj.ai_daily_analytics where organization_id=current_setting('test.analytics.other')::uuid) then raise exception 'foreign_analytics_written';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','tenant daily rollup and activity consent','persisted_rows',0) verification;
