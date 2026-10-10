begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback push delivery gate','rollback-push-delivery-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign push delivery gate','rollback-push-delivery-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.push.native',native::text,true);perform set_config('test.push.actor',actor::text,true);perform set_config('test.push.org',org::text,true);perform set_config('test.push.other',other::text,true);
 perform set_config('test.push.counts',(select (select jsonb_build_array((select count(*) from information_schema.tables where table_schema in ('tj','public','tj_private')),(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('tj','public','tj_private'))))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org'),'action','status'));
 if r->>'ok'<>'true' or r->>'push_enabled'<>'false' or r->>'recipient_selection_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 r:=public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org')));
 if r->>'ok'<>'false' or r->>'sent'<>'0' then raise exception 'default_enrich_executed';end if;
 foreach a in array array['send'] loop
  r:=public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org'),'action',a));
  if r->>'error'<>'push_delivery_verification_required' or r->>'executed'<>'false' or r->>'attempted'<>'0' or r->>'sent'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org'),'action','send','data',jsonb_build_object('brand','LG','url','https://PRIVATE.invalid')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['recipient_user_id','notification_id','app_key','title','body','url','tag','endpoint','p256dh','auth_secret'] loop
  begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_payment_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.push.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.push.org')::uuid and user_id=current_setting('test.push.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_push_delivery_preflight(jsonb_build_object('organization_id',current_setting('test.push.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_push_delivery_preflight(jsonb)','tj_private.push_delivery_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select (select jsonb_build_array((select count(*) from information_schema.tables where table_schema in ('tj','public','tj_private')),(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('tj','public','tj_private'))))::text)<>current_setting('test.push.counts') then raise exception 'catalog_counts_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','push delivery gate','persisted_rows',0) verification;
