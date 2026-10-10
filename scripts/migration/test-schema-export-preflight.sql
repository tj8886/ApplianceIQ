begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback schema export gate','rollback-schema-export-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign schema export gate','rollback-schema-export-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.export.native',native::text,true);perform set_config('test.export.actor',actor::text,true);perform set_config('test.export.org',org::text,true);perform set_config('test.export.other',other::text,true);
 perform set_config('test.export.counts',(select (select jsonb_build_array((select count(*) from information_schema.tables where table_schema in ('tj','public','tj_private')),(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('tj','public','tj_private'))))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org'),'action','status'));
 if r->>'ok'<>'true' or r->>'export_enabled'<>'false' or r->>'operator_authority_verified'<>'false' or r->>'snapshot_verified'<>'false' then raise exception 'unsafe_status';end if;
 r:=public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org')));
 if r->>'ok'<>'false' or r->>'bytes_exported'<>'0' then raise exception 'default_enrich_executed';end if;
 foreach a in array array['export'] loop
  r:=public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org'),'action',a));
  if r->>'error'<>'schema_export_verification_required' or r->>'executed'<>'false' or r->>'ddl_sections_read'<>'0' or r->>'bytes_exported'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org'),'action','export','data',jsonb_build_object('brand','LG','url','https://PRIVATE.invalid')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['key','schema','section','table','ddl','query','operator_role'] loop
  begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_payment_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.export.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.export.org')::uuid and user_id=current_setting('test.export.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_schema_export_preflight(jsonb_build_object('organization_id',current_setting('test.export.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_schema_export_preflight(jsonb)','tj_private.schema_export_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select (select jsonb_build_array((select count(*) from information_schema.tables where table_schema in ('tj','public','tj_private')),(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('tj','public','tj_private'))))::text)<>current_setting('test.export.counts') then raise exception 'catalog_counts_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','schema export gate','persisted_rows',0) verification;
