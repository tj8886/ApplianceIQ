begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;connector uuid;conn uuid;begin
 select im.target_user_id,im.source_user_id,m.organization_id into native,actor,org from tj.source_user_identity_map im
 join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id
 where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 select id into connector from tj.platform_connectors where key='shopify';if native is null or connector is null then raise exception 'missing_fixture';end if;
 insert into tj.platform_connector_connections(organization_id,connector_id,display_name,created_by,credential_ref,settings,external_account_id) values(org,connector,'Rollback Shopify preflight',actor,'PRIVATE-CREDENTIAL-REF','{"private":"NEVER-RETURN","destination_connection_verified":true}',gen_random_uuid()::text) returning id into conn;
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.shopify.native',native::text,true);perform set_config('test.shopify.actor',actor::text,true);perform set_config('test.shopify.org',org::text,true);perform set_config('test.shopify.connection',conn::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection'),'action','status'));
 if r->>'ok'<>'true' or r->>'sync_ready'<>'false' or r->>'linked_store'<>'false' or not (r->'blockers' ? 'shopify_store_link_missing') or r::text like '%PRIVATE%' or r::text like '%NEVER-RETURN%' then raise exception 'missing_store_or_privacy_failed';end if;
 r:=public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection')));if r->>'ok'<>'false' or r->>'executed'<>'false' or r->>'imported_records'<>'0' then raise exception 'false_sync_success';end if;
 begin perform public.tj_shopify_initial_sync(jsonb_build_object('connection_id',gen_random_uuid(),'action','status'));raise exception 'foreign_connection_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection'),'access_token','forbidden'));raise exception 'caller_token_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);begin perform public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.shopify.native'),true);
end $$;
reset role;
insert into tj.shopify_stores(organization_id,platform_connection_id,shop_domain,access_token,scopes,metadata,initial_sync_stats) values(current_setting('test.shopify.org')::uuid,current_setting('test.shopify.connection')::uuid,'rollback-'||gen_random_uuid()||'.myshopify.com','PRIVATE-LEGACY-TOKEN','read_all_orders,read_users','{"private":"NEVER-RETURN"}','{"private":"NEVER-RETURN"}');
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection'),'action','status'));
 if r->>'linked_store'<>'true' or r->>'sync_ready'<>'false' or r#>>'{recorded_scope_flags,read_all_orders}'<>'true' or r#>>'{recorded_scope_flags,provider_verified}'<>'false' or r::text like '%PRIVATE%' or r::text like '%NEVER-RETURN%' then raise exception 'legacy_token_or_settings_false_ready';end if;
end $$;
reset role;
update tj.shopify_stores set shop_domain='localhost/unsafe',uninstalled_at=now() where platform_connection_id=current_setting('test.shopify.connection')::uuid;
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection'),'action','status'));
 if not(r->'blockers' ? 'shopify_domain_invalid') or not(r->'blockers' ? 'shopify_store_inactive') then raise exception 'unsafe_domain_or_uninstall_ignored';end if;
end $$;
reset role;
update tj.organization_members set role='member' where user_id=current_setting('test.shopify.actor')::uuid and organization_id=current_setting('test.shopify.org')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_shopify_initial_sync(jsonb_build_object('connection_id',current_setting('test.shopify.connection'),'action','status'));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_shopify_initial_sync(jsonb)','tj_private.shopify_initial_sync(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if exists(select 1 from tj.platform_sync_jobs where connection_id=current_setting('test.shopify.connection')::uuid) then raise exception 'premature_job';end if;
 if exists(select 1 from tj.platform_connector_connections where id=current_setting('test.shopify.connection')::uuid and (status<>'pending' or initial_sync_completed_at is not null or last_sync_at is not null)) then raise exception 'false_activation';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','shopify preflight','persisted_rows',0) verification;
