begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback MDF billing gate','rollback-mdf-billing-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign MDF billing gate','rollback-mdf-billing-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.chq.native',native::text,true);perform set_config('test.chq.actor',actor::text,true);perform set_config('test.chq.org',org::text,true);perform set_config('test.chq.other',other::text,true);
 perform set_config('test.chq.counts',(select jsonb_build_array((select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_organizations x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_subscription_tiers x),(select count(*) from tj.mdf_platform_users),(select count(*) from tj.mdf_brands))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));
 if r->>'ok'<>'true' or r->>'payment_enabled'<>'false' or r->>'webhook_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 r:=public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','get_status'));
 if r->>'ok'<>'true' or r ? 'usage' or r ? 'org' or r ? 'limits' then raise exception 'legacy_status_data_leak';end if;
 foreach a in array array['create_checkout','billing_portal','webhook'] loop
  r:=public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action',a));
  if r->>'processed'<>'false' or r->>'recorded'<>'false' or r->>'error'<>'mdf_billing_verification_required' or r->>'executed'<>'false' or r->>'provider_requests'<>'0' or r->>'payment_records_created'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','create_checkout','data',jsonb_build_object('org_id',gen_random_uuid(),'email','PRIVATE@invalid.test','type','checkout.session.completed')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['org_id','email','tier_id','billing_cycle','stripe_signature'] loop
  begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_payment_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.chq.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.chq.org')::uuid and user_id=current_setting('test.chq.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_mdf_billing_preflight(jsonb_build_object('organization_id',current_setting('test.chq.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_mdf_billing_preflight(jsonb)','tj_private.mdf_billing_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_organizations x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.mdf_subscription_tiers x),(select count(*) from tj.mdf_platform_users),(select count(*) from tj.mdf_brands))::text)<>current_setting('test.chq.counts') then raise exception 'mdf_billing_records_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','MDF billing gate','persisted_rows',0) verification;
