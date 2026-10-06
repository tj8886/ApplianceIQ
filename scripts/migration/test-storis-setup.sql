begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;connector uuid;conn uuid;begin
 select im.target_user_id,im.source_user_id,m.organization_id into native,actor,org from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select id into connector from tj.platform_connectors where key='storis';if native is null or connector is null then raise exception 'missing_fixture';end if;
 insert into tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,external_account_id,credential_ref,settings) values(org,connector,'Rollback STORIS setup',actor,gen_random_uuid()::text,'IMPORTED-REF','{"private":"NEVER-RETURN"}') returning id into conn;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.storis.native',native::text,true);perform set_config('test.storis.actor',actor::text,true);perform set_config('test.storis.org',org::text,true);perform set_config('test.storis.connection',conn::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;bad jsonb;conn text:=current_setting('test.storis.connection');begin
 r:=public.tj_storis_setup(jsonb_build_object('connection_id',conn));if r->>'credential_stored'<>'false' or r->>'sync_ready'<>'false' or r::text like '%NEVER-RETURN%' or r::text like '%IMPORTED-REF%' then raise exception 'legacy_ref_accepted_or_leaked';end if;
 begin perform public.tj_storis_setup(jsonb_build_object('connection_id',gen_random_uuid()));raise exception 'foreign_connection_accepted';exception when insufficient_privilege then null;end;
 for bad in select value from jsonb_array_elements('[{"base_url":"http://storis.example"},{"base_url":"https://storis.example/a/../secret"},{"base_url":"https://storis.example/a/./secret"},{"base_url":"https://storis.example?token=secret"},{"base_url":"https://localhost/api"},{"base_url":"https://127.0.0.1/api"},{"endpoints":{"customers":"https://evil.example"}},{"endpoints":{"unknown":"customers"}},{"endpoints":{"customers":1}},{"api_key_header":"Host"},{"credential":{"token":"synthetic","password":"wrong"}},{"credential":{"token":1}},{"credential":{"token":""}},{"test_path":"../secrets"}]') loop
  begin perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','endpoints',jsonb_build_object('customers','customers'),'credential',jsonb_build_object('token','synthetic'))||bad);raise exception 'unsafe_config_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 r:=public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','endpoints',jsonb_build_object('customers','customers'),'credential',jsonb_build_object('token','rollback-synthetic-one')));if r->>'credential_stored'<>'true' or r->>'sync_ready'<>'false' or r->>'provider_verified'<>'false' then raise exception 'configure_failed_or_false_ready';end if;
 r:=public.tj_storis_setup(jsonb_build_object('connection_id',conn));if r::text like '%rollback-synthetic%' or r#>>'{configuration,configured}'<>'true' then raise exception 'credential_leak_or_missing';end if;
 begin perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','auth_type','basic','endpoints',jsonb_build_object('customers','customers')));raise exception 'auth_change_kept_wrong_credential';exception when invalid_parameter_value then null;end;
 perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','auth_type','basic','endpoints',jsonb_build_object('customers','customers'),'credential',jsonb_build_object('username','synthetic-user','password','rollback-synthetic-two')));
 perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','auth_type','api_key','api_key_header','X-STORIS-Key','test_path','health','endpoints',jsonb_build_object('customers','customers'),'credential',jsonb_build_object('api_key','rollback-synthetic-three')));
 perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',conn,'base_url','https://storis.example/api','auth_type','api_key','endpoints',jsonb_build_object('customers','customers')));
 r:=public.tj_storis_setup(jsonb_build_object('action','test','connection_id',conn));if r->>'error'<>'storis_provider_verification_required' or r->>'executed'<>'false' then raise exception 'provider_test_accepted';end if;
 r:=public.tj_storis_setup(jsonb_build_object('action','sync','connection_id',conn));if r->>'error'<>'storis_import_verification_required' or r->>'processed'<>'0' then raise exception 'sync_false_success';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);begin perform public.tj_storis_setup(jsonb_build_object('connection_id',conn));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;perform set_config('request.jwt.claim.sub',current_setting('test.storis.native'),true);
end $$;
reset role;
do $$declare c tj_private.storis_credentials%rowtype;begin
 select * into c from tj_private.storis_credentials where connection_id=current_setting('test.storis.connection')::uuid;
 if c.organization_id<>current_setting('test.storis.org')::uuid or c.auth_type<>'api_key' or not exists(select 1 from vault.decrypted_secrets where id=c.secret_id and decrypted_secret::jsonb->>'api_key'='rollback-synthetic-three') then raise exception 'rotation_or_scope_failed';end if;
 if exists(select 1 from tj.platform_connector_connections where id=c.connection_id and (status<>'pending' or auth_status<>'not_configured' or settings->>'destination_connection_verified'<>'false' or settings::text like '%rollback-synthetic%')) then raise exception 'activation_or_settings_credential_leak';end if;
 if exists(select 1 from tj.platform_sync_jobs where connection_id=c.connection_id) then raise exception 'premature_job';end if;
 update tj.platform_connector_connections set status='paused' where id=c.connection_id;
end $$;
set local role authenticated;
do $$begin begin perform public.tj_storis_setup(jsonb_build_object('action','configure','connection_id',current_setting('test.storis.connection'),'base_url','https://storis.example/api','endpoints',jsonb_build_object('customers','customers')));raise exception 'paused_config_accepted';exception when serialization_failure then null;end;end $$;
reset role;
update tj.organization_members set role='member' where user_id=current_setting('test.storis.actor')::uuid and organization_id=current_setting('test.storis.org')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_storis_setup(jsonb_build_object('connection_id',current_setting('test.storis.connection')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_storis_setup(jsonb)','tj_private.storis_setup(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if has_table_privilege('authenticated','tj_private.storis_credentials','SELECT,INSERT,UPDATE,DELETE') or has_table_privilege('service_role','tj_private.storis_credentials','SELECT,INSERT,UPDATE,DELETE') then raise exception 'direct_credential_access';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','STORIS setup and rotation','persisted_rows',0) verification;
