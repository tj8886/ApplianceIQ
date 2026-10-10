begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback CHQ gate','rollback-chq-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign CHQ gate','rollback-chq-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.chq.native',native::text,true);perform set_config('test.chq.actor',actor::text,true);perform set_config('test.chq.org',org::text,true);perform set_config('test.chq.other',other::text,true);
 perform set_config('test.chq.counts',(select jsonb_build_array((select count(*) from tj.chq_bookings),(select count(*) from tj.chq_open_jobs),(select count(*) from tj.chq_open_job_notifications),(select count(*) from tj.chq_customers),(select count(*) from tj.chq_contractors))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;w text;f text;begin
 foreach w in array array['booking','contractor','reminders'] loop
  f:='tj_chq_'||w||'_preflight';
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','status');
  if r->>'ok'<>'true' or r->>'workflow'<>w or r->>'notification_enabled'<>'false' or r->>'recipient_selection_enabled'<>'false' or r->>'scheduler_enabled'<>'false' then raise exception 'unsafe_status';end if;
  if not(r->'blockers' ? 'chq_explicit_record_tenant_ownership_required') then raise exception 'legacy_ownership_inferred';end if;
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.chq.org'));
  if r->>'error'<>'chq_notification_verification_required' or r->>'executed'<>'false' or r->>'sent'<>'0' or r->>'delivery_attempts'<>'0' or r->>'notification_records_created'<>'0' then raise exception 'notification_executed';end if;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.chq.other'));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.chq.org'),'record',jsonb_build_object('email','PRIVATE@invalid.test'),'type','INSERT');raise exception 'spoofed_webhook_accepted';exception when invalid_parameter_value then null;end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.chq.org'));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('test.chq.native'),true);
 end loop;
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.chq.org')::uuid and user_id=current_setting('test.chq.actor')::uuid;
set local role authenticated;
do $$declare f text;begin foreach f in array array['tj_chq_booking_preflight','tj_chq_contractor_preflight','tj_chq_reminders_preflight'] loop begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.chq.org'));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end loop;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_chq_booking_preflight(jsonb)','public.tj_chq_contractor_preflight(jsonb)','public.tj_chq_reminders_preflight(jsonb)','tj_private.chq_notification_preflight(text,jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select count(*) from tj.chq_bookings),(select count(*) from tj.chq_open_jobs),(select count(*) from tj.chq_open_job_notifications),(select count(*) from tj.chq_customers),(select count(*) from tj.chq_contractors))::text)<>current_setting('test.chq.counts') then raise exception 'chq_records_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','CHQ notification gates','persisted_rows',0) verification;
