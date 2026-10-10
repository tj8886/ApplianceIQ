begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;connector uuid;conn uuid;foreign_conn uuid;a uuid;j uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select id into connector from tj.platform_connectors where key='oracle_xstore';
 if native is null or connector is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback dispatch','rollback-dispatch-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign dispatch','rollback-dispatch-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 insert into tj.platform_connector_connections(organization_id,connector_id,display_name,created_by) values(org,connector,'PRIVATE',actor) returning id into conn;
 insert into tj.platform_connector_connections(organization_id,connector_id,display_name,created_by) values(other,connector,'PRIVATE FOREIGN',actor) returning id into foreign_conn;
 with alerts as (insert into tj.platform_connector_alerts(connection_id,alert_type,title,message,fingerprint) select conn,'test','PRIVATE TITLE','PRIVATE MESSAGE',gen_random_uuid()::text from generate_series(1,26) returning id)
 insert into tj.platform_connector_alert_deliveries(alert_id,organization_id,user_id,channel,next_attempt_at) select id,org,actor,'email',now()-interval '1 hour' from alerts;
 with jobs as (insert into tj.platform_sync_jobs(connection_id,job_type,status,error_details,cursor) select conn,'incremental','failed','{"private":"PRIVATE ERROR"}','{"private":"PRIVATE CURSOR"}' from generate_series(1,26) returning id)
 insert into tj.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason,available_at) select id,conn,'PRIVATE REASON',now()-interval '1 hour' from jobs;
 insert into tj.platform_connector_alerts(connection_id,alert_type,title,fingerprint) values(foreign_conn,'test','PRIVATE FOREIGN',gen_random_uuid()::text) returning id into a;
 insert into tj.platform_connector_alert_deliveries(alert_id,organization_id,user_id,channel,next_attempt_at) values(a,org,actor,'email',now()-interval '1 hour');
 select id into a from tj.platform_connector_alerts where connection_id=conn limit 1;
 insert into tj.platform_connector_alert_deliveries(alert_id,organization_id,user_id,channel,next_attempt_at) values(a,other,actor,'in_app',now()-interval '1 hour');
 insert into tj.platform_sync_jobs(connection_id,job_type,status) values(foreign_conn,'incremental','failed') returning id into j;
 insert into tj.platform_connector_job_recovery_queue(failed_job_id,connection_id,reason,available_at) values(j,conn,'PRIVATE MISMATCH',now()-interval '1 hour');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.dispatch.native',native::text,true);perform set_config('test.dispatch.actor',actor::text,true);perform set_config('test.dispatch.org',org::text,true);perform set_config('test.dispatch.other',other::text,true);perform set_config('test.dispatch.conn',conn::text,true);perform set_config('test.dispatch.foreign',foreign_conn::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;r2 jsonb;r3 jsonb;f text;begin
 foreach f in array array['tj_connector_alert_preview','tj_connector_recovery_preview'] loop
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview');
  if r->>'page_count'<>'25' or r->>'has_more'<>'true' or r->>'dispatch_enabled'<>'false' or r::text like '%PRIVATE%' or r::text like '%'||current_setting('test.dispatch.foreign')||'%' then raise exception 'scope_bound_or_redaction_failed';end if;
  execute format('select public.%I($1)',f) into r2 using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview','after_id',r->>'next_after_id');
  if r2->>'page_count'<>'1' or r2->>'has_more'<>'false' or (r2#>>'{items,0,id}')::uuid<=(r->>'next_after_id')::uuid then raise exception 'pagination_failed';end if;
  execute format('select public.%I($1)',f) into r3 using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview');
  if r3<>r then raise exception 'preview_mutated_queue';end if;
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.dispatch.org'));
  if r->>'error'<>'connector_dispatch_verification_required' or r->>'executed'<>'false' then raise exception 'dispatch_enabled';end if;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.dispatch.other'),'mode','preview');raise exception 'foreign_org_accepted';exception when insufficient_privilege then null;end;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'connection_id',current_setting('test.dispatch.foreign'),'mode','preview');raise exception 'foreign_connection_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview');raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('test.dispatch.native'),true);
 end loop;
end $$;
reset role;
update tj.platform_connector_alert_deliveries set attempt_count=max_attempts where id=(select d.id from tj.platform_connector_alert_deliveries d join tj.platform_connector_alerts a on a.id=d.alert_id where a.connection_id=current_setting('test.dispatch.conn')::uuid and d.organization_id=current_setting('test.dispatch.org')::uuid order by d.id limit 1);
update tj.platform_connector_job_recovery_queue set available_at=now()+interval '1 day' where id=(select q.id from tj.platform_connector_job_recovery_queue q join tj.platform_sync_jobs j on j.id=q.failed_job_id and j.connection_id=q.connection_id where q.connection_id=current_setting('test.dispatch.conn')::uuid order by q.id limit 1);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_connector_alert_preview(jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview'));if r->>'page_count'<>'25' or r->>'has_more'<>'false' then raise exception 'exhausted_attempts_included';end if;
 r:=public.tj_connector_recovery_preview(jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview'));if r->>'page_count'<>'25' or r->>'has_more'<>'false' then raise exception 'future_retry_included';end if;
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.dispatch.org')::uuid and user_id=current_setting('test.dispatch.actor')::uuid;
set local role authenticated;
do $$declare f text;begin foreach f in array array['tj_connector_alert_preview','tj_connector_recovery_preview'] loop begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.dispatch.org'),'mode','preview');raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end loop;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_connector_alert_preview(jsonb)','public.tj_connector_recovery_preview(jsonb)','tj_private.connector_dispatch_preview(text,jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if exists(select 1 from tj.platform_connector_job_recovery_queue where connection_id=current_setting('test.dispatch.conn')::uuid and (status<>'pending' or attempt_count<>0)) or exists(select 1 from tj.platform_connector_alert_deliveries d join tj.platform_connector_alerts a on a.id=d.alert_id where a.connection_id=current_setting('test.dispatch.conn')::uuid and (d.status<>'pending' or d.sent_at is not null)) then raise exception 'queue_claimed_or_sent';end if;
 if (select count(*) from tj.organization_members where organization_id=current_setting('test.dispatch.org')::uuid)<>1 then raise exception 'bot_membership_created';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','bounded tenant connector dispatch previews','persisted_rows',0) verification;
