begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback CHQ payment gate','rollback-chq-payment-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign CHQ payment gate','rollback-chq-payment-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.chq.native',native::text,true);perform set_config('test.chq.actor',actor::text,true);perform set_config('test.chq.org',org::text,true);perform set_config('test.chq.other',other::text,true);
 perform set_config('test.chq.counts',(select jsonb_build_array((select count(*) from tj.chq_bookings),(select count(*) from tj.chq_open_jobs),(select count(*) from tj.chq_open_job_notifications),(select count(*) from tj.chq_customers),(select count(*) from tj.chq_contractors))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));
 if r->>'ok'<>'true' or r->>'payment_enabled'<>'false' or r->>'payout_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 foreach a in array array['create_checkout','contractor_subscription','connect_onboarding','connect_status','process_payout','process_all_payouts'] loop
  r:=public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action',a,'booking_id',gen_random_uuid(),'contractor_id',gen_random_uuid(),'tier','PRIVATE UNVERIFIED'));
  if r->>'error'<>'chq_payment_verification_required' or r->>'executed'<>'false' or r->>'provider_requests'<>'0' or r->>'payment_records_created'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','create_checkout','booking',jsonb_build_object('retail_price',0,'customer_email','PRIVATE@invalid.test')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 begin perform public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.chq.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.chq.org')::uuid and user_id=current_setting('test.chq.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_chq_payment_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_chq_payment_preflight(jsonb)','tj_private.chq_payment_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select count(*) from tj.chq_bookings),(select count(*) from tj.chq_open_jobs),(select count(*) from tj.chq_open_job_notifications),(select count(*) from tj.chq_customers),(select count(*) from tj.chq_contractors))::text)<>current_setting('test.chq.counts') or exists(select 1 from tj.chq_payouts) then raise exception 'chq_payment_records_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','CHQ payment gate','persisted_rows',0) verification;
