-- Every fixture and source-user role change is rolled back by the caller.
DO $$
DECLARE actor uuid; native uuid; org uuid; sid uuid:=gen_random_uuid(); keep uuid:=gen_random_uuid();
 contact uuid; deal uuid; keepdeal uuid; pkg uuid; keeppkg uuid; proj uuid; standalone uuid; independent uuid;
 warranty uuid;
 payload jsonb; keeppayload jsonb; request jsonb; projectrequest jsonb; r jsonb; stamp timestamptz; ver int;
 preserved text; tab text; n bigint; replay jsonb;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,native FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id
 WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL AND NOT EXISTS(SELECT 1 FROM tj.platform_admins p WHERE p.user_id=im.source_user_id) LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'mapped fixture identity unavailable';END IF;
 INSERT INTO tj.organizations(name,slug) VALUES('Store scope rollback fixture','spec-store-rollback-'||gen_random_uuid()) RETURNING id INTO org;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status,visibility_scope) VALUES(org,actor,'owner','active','all');
 INSERT INTO tj.org_locations(id,organization_id,location_type,name) VALUES(sid,org,'store','Revoked fixture store'),(keep,org,'store','Retained fixture store');
 INSERT INTO tj.org_location_members(organization_id,location_id,user_id,is_primary) VALUES(org,sid,actor,true),(org,keep,actor,false);
 INSERT INTO tj.contacts(organization_id,first_name,email) VALUES(org,'Rollback Fixture','rollback@example.test') RETURNING id INTO contact;
 INSERT INTO tj.crm_deals(organization_id,contact_id,owner_user_id,title,location_id,value_amount) VALUES(org,contact,actor,'Revoked store fixture deal',sid,123.45) RETURNING id INTO deal;
 INSERT INTO tj.crm_deals(organization_id,contact_id,owner_user_id,title,location_id,value_amount) VALUES(org,contact,actor,'Retained store fixture deal',keep,234.56) RETURNING id INTO keepdeal;
 INSERT INTO tj.speciq_warranty_catalog(organization_id,warranty_name,warranty_type,selling_price,active,is_included,applies_to_categories) VALUES(org,'Fixture coverage','extended',12.34,true,false,ARRAY['refrigerator']) RETURNING id INTO warranty;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 payload:=jsonb_build_object('action','save','organization_id',org,'request_id',gen_random_uuid(),'contact_id',contact,'deal_id',deal,'customer',jsonb_build_object('name','Rollback Fixture','project_name','Rollback Project'),'package_name','Rollback linked package','include_pricing',true,'products',jsonb_build_array(jsonb_build_object('product_name','Fixture appliance','brand','Fixture','category','refrigerator','msrp','10.01','quantity',2,'warranty_id',warranty)),'services',jsonb_build_array(jsonb_build_object('service_type','delivery','description','Fixture delivery','amount','5.10','taxable',true)));
 r:=public.tj_runtime_speciq_drafts(payload);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'fixture draft: %',r;END IF;pkg:=(r->>'package_id')::uuid;
 SELECT project_id INTO proj FROM tj.speciq_packages WHERE id=pkg;
 keeppayload:=payload||jsonb_build_object('request_id',gen_random_uuid(),'deal_id',keepdeal);
 r:=public.tj_runtime_speciq_drafts(keeppayload);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'retained-store fixture draft: %',r;END IF;keeppkg:=(r->>'package_id')::uuid;
 projectrequest:=jsonb_build_object('action','create','organization_id',org,'request_id',gen_random_uuid(),'project',jsonb_build_object('project_name','Fixture standalone','customer_name','Fixture'));
 r:=public.tj_runtime_speciq_projects(projectrequest);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'project fixture: %',r;END IF;standalone:=(r->>'project_id')::uuid;
 r:=public.tj_runtime_speciq_projects(projectrequest||jsonb_build_object('request_id',gen_random_uuid()));independent:=(r->>'project_id')::uuid;
 -- This isolated project allows testing an old project-create replay after a store link is added.
 UPDATE tj.speciq_projects SET deal_id=deal WHERE id=standalone;
 SELECT jsonb_build_object('action','submit','organization_id',org,'package_id',id,'expected_version',version,'expected_updated_at',updated_at,'request_id',gen_random_uuid()) INTO request FROM tj.speciq_packages WHERE id=pkg;
 r:=public.tj_runtime_speciq_workflow(request);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'submit fixture: %',r;END IF;
 INSERT INTO tj.speciq_extension_requests(organization_id,package_id,existing_expiry,requested_expiry,reason) VALUES(org,pkg,current_date,current_date+7,'Rollback evidence');
 SELECT version,updated_at INTO ver,stamp FROM tj.speciq_packages WHERE id=pkg;
 SELECT md5(jsonb_build_object('package',to_jsonb(k),'project',(SELECT to_jsonb(p) FROM tj.speciq_projects p WHERE p.id=proj),'products',(SELECT jsonb_agg(to_jsonb(p)) FROM tj.speciq_package_products p WHERE p.package_id=pkg),'versions',(SELECT jsonb_agg(to_jsonb(v)) FROM tj.speciq_package_versions v WHERE v.package_id=pkg),'history',(SELECT jsonb_agg(to_jsonb(h)) FROM tj.speciq_approval_history h WHERE h.package_id=pkg))::text) INTO preserved FROM tj.speciq_packages k WHERE k.id=pkg;
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOREACH tab IN ARRAY ARRAY['speciq_package_products','speciq_package_services','speciq_package_events','speciq_package_versions','speciq_product_warranties','speciq_approval_history','speciq_extension_requests'] LOOP
 EXECUTE format('SELECT count(*) FROM tj.%I WHERE package_id=$1',tab) INTO n USING pkg;IF n=0 THEN RAISE EXCEPTION 'missing pre-revocation child fixture: %',tab;END IF;END LOOP;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id=pkg) OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg) THEN RAISE EXCEPTION 'active access missing';END IF;
 r:=public.tj_runtime_up_administration(jsonb_build_object('organization_id',org,'store_id',sid,'action','revoke_store','member_id',(SELECT id FROM tj.organization_members WHERE organization_id=org AND user_id=actor)));
 IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'revocation: %',r;END IF;
 IF EXISTS(SELECT 1 FROM tj.speciq_projects WHERE id IN(proj,standalone)) OR EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id=pkg) THEN RAISE EXCEPTION 'revoked project/package leaked';END IF;
 FOREACH tab IN ARRAY ARRAY['speciq_package_products','speciq_package_services','speciq_package_events','speciq_package_versions','speciq_product_warranties','speciq_approval_history','speciq_extension_requests'] LOOP
 EXECUTE format('SELECT count(*) FROM tj.%I WHERE package_id=$1',tab) INTO n USING pkg;
 IF n<>0 THEN RAISE EXCEPTION 'revoked child leaked: %',tab;END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id=keeppkg) OR NOT EXISTS(SELECT 1 FROM tj.speciq_projects WHERE id=independent) THEN RAISE EXCEPTION 'other-store or organization-wide access lost';END IF;
 r:=public.tj_runtime_speciq_projects(jsonb_build_object('action','list','organization_id',org));
 IF r->>'ok' IS DISTINCT FROM 'true' OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'projects') p WHERE p->>'id' IN(proj::text,standalone::text)) THEN RAISE EXCEPTION 'project list leaked';END IF;
 r:=public.tj_runtime_speciq_workflow(jsonb_build_object('action','list','organization_id',org));
 IF r->>'ok' IS DISTINCT FROM 'true' OR EXISTS(SELECT 1 FROM jsonb_array_elements(r->'packages') p WHERE p->>'id'=pkg::text) OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(r->'packages') p WHERE p->>'id'=keeppkg::text) THEN RAISE EXCEPTION 'workflow list leaked or other store lost';END IF;
 FOREACH tab IN ARRAY ARRAY['get','submit','decide','archive'] LOOP
 r:=public.tj_runtime_speciq_workflow(request||jsonb_build_object('action',tab,'decision','approved'));
 IF r->>'error' IS DISTINCT FROM 'package_unavailable' THEN RAISE EXCEPTION 'revoked workflow or replay allowed: % %',tab,r;END IF;
 END LOOP;
 BEGIN PERFORM public.tj_runtime_speciq_add_comparison_winner(pkg,gen_random_uuid());RAISE EXCEPTION 'revoked comparison write allowed';EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'package_access_denied' THEN RAISE;END IF;END;
 EXECUTE 'RESET ROLE';EXECUTE 'SET LOCAL ROLE service_role';
 FOREACH tab IN ARRAY ARRAY['prepare','start','status'] LOOP
 BEGIN PERFORM public.aiq_shopify_draft_attempt(native,jsonb_build_object('organization_id',org,'package_id',pkg,'action',tab,'connection_id',gen_random_uuid()));RAISE EXCEPTION 'revoked service worker access allowed';EXCEPTION WHEN insufficient_privilege THEN IF SQLERRM<>'package_access_denied' THEN RAISE;END IF;END;
 END LOOP;
 EXECUTE 'RESET ROLE';EXECUTE 'SET LOCAL ROLE authenticated';
 BEGIN PERFORM public.tj_shopify_draft_order(jsonb_build_object('organization_id',org,'package_id',pkg,'action','preview'));RAISE EXCEPTION 'revoked Shopify preview allowed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 r:=public.tj_runtime_speciq_drafts(payload);IF r->>'ok'='true' THEN RAISE EXCEPTION 'draft create replay bypassed revocation';END IF;
 r:=public.tj_runtime_speciq_drafts(payload||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',pkg,'expected_version',ver,'expected_updated_at',stamp,'contact_id',NULL,'deal_id',NULL));
 IF r->>'error' IS DISTINCT FROM 'package_unavailable' THEN RAISE EXCEPTION 'draft link clearing bypassed revocation: %',r;END IF;
 r:=public.tj_runtime_speciq_drafts(payload||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',pkg,'expected_version',ver,'expected_updated_at',stamp,'deal_id',keepdeal));
 IF r->>'error' IS DISTINCT FROM 'package_unavailable' THEN RAISE EXCEPTION 'moving revoked draft to allowed store bypassed revocation';END IF;
 r:=public.tj_runtime_speciq_projects(projectrequest);IF r->>'error' IS DISTINCT FROM 'project_unavailable' THEN RAISE EXCEPTION 'project replay bypassed revocation';END IF;
 r:=public.tj_runtime_speciq_projects(jsonb_build_object('action','archive','organization_id',org,'project_id',standalone,'request_id',gen_random_uuid()));
 IF r->>'error' IS DISTINCT FROM 'project_unavailable' THEN RAISE EXCEPTION 'project archive bypassed revocation';END IF;
 r:=public.tj_runtime_speciq_workflow(jsonb_build_object('action','get','organization_id',org,'package_id',keeppkg));IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'retained workflow denied';END IF;
 r:=public.tj_runtime_up_administration(jsonb_build_object('organization_id',org,'store_id',sid,'action','assign_store','member_id',(SELECT id FROM tj.organization_members WHERE organization_id=org AND user_id=actor)));
 IF r->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id=pkg) OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg) THEN RAISE EXCEPTION 'restore read failed';END IF;
 r:=public.tj_runtime_speciq_workflow(request);IF r->>'replayed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'restored workflow replay failed';END IF;
 r:=public.tj_runtime_speciq_projects(projectrequest);IF r->>'replayed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'restored project replay failed';END IF;
 EXECUTE 'RESET ROLE';
 IF preserved IS DISTINCT FROM (SELECT md5(jsonb_build_object('package',to_jsonb(k),'project',(SELECT to_jsonb(p) FROM tj.speciq_projects p WHERE p.id=proj),'products',(SELECT jsonb_agg(to_jsonb(p)) FROM tj.speciq_package_products p WHERE p.package_id=pkg),'versions',(SELECT jsonb_agg(to_jsonb(v)) FROM tj.speciq_package_versions v WHERE v.package_id=pkg),'history',(SELECT jsonb_agg(to_jsonb(h)) FROM tj.speciq_approval_history h WHERE h.package_id=pkg))::text) FROM tj.speciq_packages k WHERE k.id=pkg) THEN RAISE EXCEPTION 'revocation altered business evidence';END IF;
 IF has_function_privilege('authenticated','tj_private.speciq_deal_store_allows_as(uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('anon','tj_private.speciq_package_store_allows(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'helper grants too broad';END IF;
END $$;
SELECT jsonb_build_object('passed',true,'persisted_fixture_rows',0,'tests','authenticated RLS across projects/packages/seven child tables; list/get/edit/archive/submit/decide/revision/replay denial; other store and unlinked project retained; restore; unchanged package/project/product/snapshot/approval evidence') verification;
