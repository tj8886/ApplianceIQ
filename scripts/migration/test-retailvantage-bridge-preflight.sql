begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;connector uuid;variant uuid;conn uuid;foreign_conn uuid;secret uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select p.id into connector from tj.platform_connectors p where p.key='retailvantage';
 if native is null or connector is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback RV','rollback-rv-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign BC','rollback-rv-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 insert into tj.platform_connector_connections(organization_id,connector_id,variant_id,display_name,created_by,status,auth_status,credential_ref,settings,auth_metadata)
 values(org,connector,variant,'PRIVATE BC',actor,'active','valid','PRIVATE CREDENTIAL','{"destination_connection_verified":true,"environment":"Production","company_id":"22222222-2222-4222-8222-222222222222","company_name":"PRIVATE COMPANY"}','{"tenant_id":"11111111-1111-4111-8111-111111111111"}') returning id into conn;
 insert into tj.platform_connector_connections(organization_id,connector_id,variant_id,display_name,created_by) values(other,connector,variant,'PRIVATE FOREIGN',actor) returning id into foreign_conn;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.rv.native',native::text,true);perform set_config('test.rv.actor',actor::text,true);perform set_config('test.rv.org',org::text,true);perform set_config('test.rv.other',other::text,true);perform set_config('test.rv.conn',conn::text,true);perform set_config('test.rv.foreign',foreign_conn::text,true);perform set_config('test.rv.secret','PRIVATE CREDENTIAL',true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn'),'action','status'));
 if r->>'ok'<>'true' or r->>'bridge_enabled'<>'false'  or r::text like '%PRIVATE%' then raise exception 'imported_settings_or_secret_trusted';end if;
 foreach a in array array['bridge'] loop r:=public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn'),'action',a));if r->>'error'<>'retailvantage_bridge_verification_required' or r->>'executed'<>'false' or r->>'transactions_processed'<>'0' then raise exception 'provider_call_allowed';end if;end loop;
 begin perform public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.foreign'),'action','status'));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn'),'organization_id',current_setting('test.rv.other')));raise exception 'foreign_org_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn'),'payload',jsonb_build_object('total',0,'cost',0)));raise exception 'unverified_financial_payload_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.rv.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.rv.org')::uuid and user_id=current_setting('test.rv.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_retailvantage_bridge_preflight(jsonb_build_object('connection_id',current_setting('test.rv.conn')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_retailvantage_bridge_preflight(jsonb)','tj_private.retailvantage_bridge_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if exists(select 1 from tj.iq_pos_transactions where source_system='retailvantage') or exists(select 1 from tj.sales_transactions where metadata->>'source'='retailvantage') then raise exception 'financial_facts_written';end if;
 if exists(select 1 from tj.platform_sync_jobs where connection_id=current_setting('test.rv.conn')::uuid) or exists(select 1 from tj.platform_connector_connections where id=current_setting('test.rv.conn')::uuid and (last_sync_at is not null or last_success_at is not null or sync_cursor is distinct from '{}'::jsonb)) then raise exception 'sync_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','RetailVantage bridge readiness','persisted_rows',0) verification;
