begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback MDF email gate','rollback-mdf-email-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign MDF email gate','rollback-mdf-email-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.mdfemail.native',native::text,true);perform set_config('test.mdfemail.actor',actor::text,true);perform set_config('test.mdfemail.org',org::text,true);perform set_config('test.mdfemail.other',other::text,true);
 perform set_config('test.mdfemail.counts',(select jsonb_build_array((select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_email_queue x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_alerts x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_mdf_funds x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_brand_contracts x))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),'action','status'));
 if r->>'ok'<>'true' or r->>'notification_enabled'<>'false' or r->>'expiry_updates_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 r:=public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),'action','test'));
 if r->>'ok'<>'true' or r ? 'has_resend_key' or r ? 'from_email' or r ? 'service_key' then raise exception 'legacy_status_data_leak';end if;
 r:=public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org')));
 if r->>'ok'<>'false' or r->>'sent'<>'0' or r->>'queued'<>'0' then raise exception 'default_send_executed';end if;
 foreach a in array array['send','send_test','process_queue','check_expiry'] loop
  r:=public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),'action',a));
  if r->>'processed'<>'0' or r->>'queued'<>'0' or r->>'sent'<>'0' or r->>'expiry_alerts_created'<>'0' or r->>'funds_expired'<>'0' or r->>'error'<>'mdf_email_verification_required' or r->>'executed'<>'false' or r->>'delivery_attempts'<>'0' or r->>'notification_records_created'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),'action','send','data',jsonb_build_object('to','PRIVATE@invalid.test','subject','PRIVATE','html','<b>PRIVATE</b>')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['to','subject','html','related_entity','related_id','queue_id','org_id'] loop
  begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_email_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.mdfemail.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.mdfemail.org')::uuid and user_id=current_setting('test.mdfemail.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_mdf_email_preflight(jsonb_build_object('organization_id',current_setting('test.mdfemail.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_mdf_email_preflight(jsonb)','tj_private.mdf_email_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_email_queue x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_alerts x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_mdf_funds x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_brand_contracts x))::text)<>current_setting('test.mdfemail.counts') then raise exception 'mdf_email_or_expiry_records_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','MDF email gate','persisted_rows',0) verification;
