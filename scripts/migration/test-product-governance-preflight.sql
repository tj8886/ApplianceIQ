begin;set local statement_timeout='30s';
do $$declare native uuid;actor uuid;org uuid;other uuid;begin
 select im.target_user_id,im.source_user_id into native,actor from tj.source_user_identity_map im join tj.organization_members m on m.user_id=im.source_user_id join tj.organizations o on o.id=m.organization_id where im.activation_status='activated' and m.status='active' and m.role in ('owner','admin') and o.status='active' and o.deleted_at is null limit 1;
 if native is null then raise exception 'missing_fixture';end if;
 insert into tj.organizations(name,slug) values('Rollback product governance gate','rollback-product-governance-gate-'||gen_random_uuid()) returning id into org;
 insert into tj.organizations(name,slug) values('Rollback foreign product governance gate','rollback-product-governance-gate-foreign-'||gen_random_uuid()) returning id into other;
 insert into tj.organization_members(organization_id,user_id,role,status) values(org,actor,'admin','active');
 perform set_config('request.jwt.claim.sub',native::text,true);perform set_config('test.gov.native',native::text,true);perform set_config('test.gov.actor',actor::text,true);perform set_config('test.gov.org',org::text,true);perform set_config('test.gov.other',other::text,true);
 perform set_config('test.gov.counts',(select jsonb_build_array((select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.aiq_products x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.product_iq_platform_roles x),(select count(*) from tj.product_iq_brand_scopes),(select count(*) from tj.product_iq_governance_audit_log))::text),true);
end $$;
set local role authenticated;
do $$declare r jsonb;a text;begin
 r:=public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org'),'action','status'));
 if r->>'ok'<>'true' or r->>'governance_enabled'<>'false' or r->>'global_publishing_enabled'<>'false' or r->>'provider_verified'<>'false' then raise exception 'unsafe_status';end if;
 foreach a in array array['search_relationship_products','create_product','update_product','validate_product','update_specifications','create_product_relationship','update_product_relationship','archive_product_relationship','restore_product_relationship','update_document_metadata','archive_document','restore_document','update_image_metadata','set_primary_image','archive_image','restore_image','reorder_images'] loop
  r:=public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org'),'action',a));
  if r->>'error'<>'product_governance_verification_required' or r->>'executed'<>'false' or r->>'provider_requests'<>'0' or r->>'products_updated'<>'0' or r::text like '%PRIVATE%' then raise exception 'payment_execution_or_leak';end if;
 end loop;
 begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.other')));raise exception 'foreign_accepted';exception when insufficient_privilege then null;end;
 begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org'),'action','update_product','data',jsonb_build_object('brand','LG','url','https://PRIVATE.invalid')));raise exception 'client_price_accepted';exception when invalid_parameter_value then null;end;
 foreach a in array array['productId','originalVersion','changes','role','decision','assetId','orderedAssetIds','relationshipId','query'] loop
  begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org'),a,'PRIVATE UNVERIFIED'));raise exception 'legacy_payment_input_accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org'),'action','unknown'));raise exception 'unknown_action_accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org')));raise exception 'unmapped_accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',current_setting('test.gov.native'),true);
end $$;
reset role;
update tj.organization_members set role='member' where organization_id=current_setting('test.gov.org')::uuid and user_id=current_setting('test.gov.actor')::uuid;
set local role authenticated;
do $$begin begin perform public.tj_product_governance_preflight(jsonb_build_object('organization_id',current_setting('test.gov.org')));raise exception 'nonadmin_accepted';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare f text;r text;begin
 foreach f in array array['public.tj_product_governance_preflight(jsonb)','tj_private.product_governance_preflight(jsonb)'] loop foreach r in array array['anon','service_role'] loop if has_function_privilege(r,f,'EXECUTE') then raise exception 'unsafe_grants';end if;end loop;end loop;
 if (select jsonb_build_array((select md5(string_agg(md5(to_jsonb(x)::text),'' order by id)) from tj.aiq_products x),(select md5(coalesce(jsonb_agg(x order by id)::text,'')) from tj.product_iq_platform_roles x),(select count(*) from tj.product_iq_brand_scopes),(select count(*) from tj.product_iq_governance_audit_log))::text)<>current_setting('test.gov.counts') then raise exception 'pim_products_mutated';end if;
end $$;
rollback;
select jsonb_build_object('passed',true,'fixture','product governance gate','persisted_rows',0) verification;
