begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;connector uuid;variant uuid;conn uuid;foreign_conn uuid;secret uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select p.id,v.id into connector,variant from tj.platform_connectors p join tj.platform_connector_variants v on v.connector_id=p.id where p.key='microsoft_dynamics_365' and v.key='business_central';
 if native is null or variant is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback BC','rollback-bc-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign BC','rollback-bc-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 secret:=vault.create_secret('PRIVATE SYNTHETIC TOKEN','rollback-bc-'||gen_random_uuid());
 insert into tj.platform_connector_connections(organization_id,connector_id,variant_id,display_name,created_by,status,auth_status,credential_ref,settings,auth_metadata)
 values(org,connector,variant,'PRIVATE BC',actor,'active','valid',secret::text,'{"destination_connection_verified":true,"environment":"Production","company_id":"22222222-2222-4222-8222-222222222222","company_name":"PRIVATE COMPANY"}','{"tenant_id":"11111111-1111-4111-8111-111111111111"}') returning id into conn;
 insert into tj.platform_connector_connections(organization_id,connector_id,variant_id,display_name,created_by) values(other,connector,variant,'PRIVATE FOREIGN',actor) returning id into foreign_conn;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.bc.native',native::text,true);perform set_config('test.bc.actor',actor::text,true);perform set_config('test.bc.org',org::text,true);perform set_config('test.bc.other',other::text,true);perform set_config('test.bc.conn',conn::text,true);perform set_config('test.bc.foreign',foreign_conn::text,true);perform set_config('test.bc.secret',secret::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'action','status'));
 if r->>'ok'<>'true' or r->>'sync_ready'<>'false' or r->>'destination_credential_recorded'<>'false' or r->>'destination_tenant_review_recorded'<>'false' or r::text like '%PRIVATE%' or r::text like '%'||current_setting('test.bc.secret')||'%' then raise exception 'imported_settings_or_secret_trusted';end if;
 foreach a in array array['sync','discover'] loop r:=public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'action',a));if r->>'error'<>'business_central_destination_verification_required' or r->>'executed'<>'false' or r->>'imported_records'<>'0' then raise exception 'provider_call_allowed';end if;end loop;
 begin perform public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.foreign'),'action','status'));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'organization_id',current_setting('test.bc.other')));raise exception 'foreign_org_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.bc.native'),true);
end $$;
reset role;
insert into tj_private.microsoft_oauth_review values(current_setting('test.bc.conn')::uuid,current_setting('test.bc.org')::uuid,'11111111-1111-4111-8111-111111111111',current_setting('test.bc.actor')::uuid,clock_timestamp()+interval '1 hour');
insert into tj_private.microsoft_credentials values(current_setting('test.bc.conn')::uuid,current_setting('test.bc.org')::uuid,current_setting('test.bc.secret')::uuid);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'action','status'));
 if r->>'destination_tenant_review_recorded'<>'true' or r->>'destination_credential_recorded'<>'true' or r->>'sync_ready'<>'false' or r->>'provider_verified'<>'false' then raise exception 'false_provider_readiness';end if;
 r:=public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'action','status','environment','https://attacker.example','company_id','bad'));
 if not (r->'blockers' ? 'business_central_environment_required') or not (r->'blockers' ? 'business_central_company_selection_required') then raise exception 'invalid_selection_trusted';end if;
end $$;
reset role;
update tj_private.microsoft_credentials set organization_id=current_setting('test.bc.other')::uuid where connection_id=current_setting('test.bc.conn')::uuid;
update tj_private.microsoft_oauth_review set expires_at=clock_timestamp()-interval '1 second' where connection_id=current_setting('test.bc.conn')::uuid;
set local role authenticated;
do $$declare r jsonb;begin r:=public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn'),'action','status'));if r->>'destination_credential_recorded'<>'false' or r->>'destination_tenant_review_recorded'<>'false' then raise exception 'expired_review_or_foreign_credential_trusted';end if;end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.bc.org')::uuid and user_id=current_setting('test.bc.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_business_central_preflight(jsonb_build_object('connection_id',current_setting('test.bc.conn')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_business_central_preflight(jsonb)','tj_private.business_central_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if exists(select 1 from tj.platform_sync_jobs where connection_id=current_setting('test.bc.conn')::uuid) or exists(select 1 from tj.platform_connector_connections where id=current_setting('test.bc.conn')::uuid and (last_sync_at is not null or last_success_at is not null or sync_cursor is distinct from '{}'::jsonb)) then raise exception 'sync_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','Business Central scoped readiness','persisted_rows',0) verification;
