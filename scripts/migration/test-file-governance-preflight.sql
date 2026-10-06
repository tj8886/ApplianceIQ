begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback file gate','rollback-file-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign file gate','rollback-file-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.file.native',native::text,true);perform set_config('test.file.actor',actor::text,true);perform set_config('test.file.org',org::text,true);perform set_config('test.file.other',other::text,true);
end $$;
set local role authenticated;
do $$declare r jsonb;f text;k text;begin
 foreach f in array array['tj_file_scan_preflight','tj_file_url_preflight'] loop
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.file.org'),'action','status');
  if r->>'ok'<>'true' or r->>'scan_enabled'<>'false' or r->>'url_issuance_enabled'<>'false' or r->>'storage_verified'<>'false' then raise exception 'unsafe_file_status';end if;
  execute format('select public.%I($1)',f) into r using jsonb_build_object('organization_id',current_setting('test.file.org'));
  if r->>'error'<>'file_governance_verification_required' or r->>'files_processed'<>'0' or r->>'nonces_consumed'<>'0' or r->>'urls_issued'<>'0' then raise exception 'file_operation_enabled';end if;
  foreach k in array array['nonce','bucket','path','file_asset_id'] loop
   begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.file.org'),k,'PRIVATE UNVERIFIED');raise exception 'legacy_file_authority_accepted';exception when invalid_parameter_value then null;end;
  end loop;
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.file.other'));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.file.org'));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claim.sub',current_setting('test.file.native'),true);
 end loop;
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.file.org')::uuid and user_id=current_setting('test.file.actor')::uuid;
set local role authenticated;
do $$declare f text;begin foreach f in array array['tj_file_scan_preflight','tj_file_url_preflight'] loop begin execute format('select public.%I($1)',f) using jsonb_build_object('organization_id',current_setting('test.file.org'));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end loop;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_file_scan_preflight(jsonb)','public.tj_file_url_preflight(jsonb)','tj_private.file_governance_preflight(text,jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','file scan and URL gates','persisted_rows',0) verification;
