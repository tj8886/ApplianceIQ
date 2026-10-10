BEGIN;
SET LOCAL statement_timeout='25s';
DO $$
DECLARE actor uuid;native uuid;org uuid;body jsonb;r jsonb;pkg uuid;prod uuid;revised uuid;v integer;stamp timestamptz;bad jsonb;before_count bigint;catalog_id uuid;brand_id uuid;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,native FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'mapped identity missing';END IF;
 INSERT INTO tj.organizations(name,slug) VALUES('Spec technical rollback fixture','spec-technical-rollback-'||gen_random_uuid()) RETURNING id INTO org;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'owner','active');
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 body:=jsonb_build_object('action','save','organization_id',org,'request_id',gen_random_uuid(),'customer',jsonb_build_object('name','Fixture','project_name','Technical'),'package_name','Technical','include_pricing',true,'products',jsonb_build_array(jsonb_build_object('product_name','Manual','brand','Fixture','category','refrigerator','msrp','10.01','quantity',2,'technical',jsonb_build_object('finish','Steel','width_inches','30.125','height_inches','70','depth_inches',NULL,'electrical_requirements','120V user entry','specifications',jsonb_build_object('capacity','20 cu ft entered'),'docs',jsonb_build_array(jsonb_build_object('doc_type','spec_sheet','title','User supplied','file_url','https://example.invalid/spec.pdf'))))),'services','[]'::jsonb);
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'manual technical save failed %',r;END IF;pkg:=(r->>'package_id')::uuid;
 SELECT id INTO prod FROM tj.speciq_package_products WHERE package_id=pkg;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE id=prod AND width_inches=30.125 AND height_inches=70 AND depth_inches IS NULL AND finish='Steel' AND electrical_requirements='120V user entry' AND spec_snapshot->>'technical_state'='user_entry_unreviewed' AND specifications->>'capacity'='20 cu ft entered') OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg AND snapshot#>>'{products,0,spec_snapshot,technical,docs,0,file_url}'='https://example.invalid/spec.pdf') THEN RAISE EXCEPTION 'technical snapshot missing';END IF;
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'replayed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'technical replay failed';END IF;
 SELECT count(*) INTO before_count FROM tj.speciq_packages WHERE organization_id=org;
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(jsonb_build_object('width_inches','-1'),jsonb_build_object('height_inches','0'),jsonb_build_object('depth_inches','30.1234'),jsonb_build_object('product_image','javascript:alert(1)'),jsonb_build_object('docs',jsonb_build_array(jsonb_build_object('doc_type','spec_sheet','file_url','http://example.invalid/spec.pdf'))),jsonb_build_object('specifications',jsonb_build_object('nested',jsonb_build_object('invented','fact'))))) LOOP
 r:=public.tj_runtime_speciq_drafts(body||jsonb_build_object('request_id',gen_random_uuid(),'products',jsonb_build_array(body#>'{products,0}'||jsonb_build_object('technical',body#>'{products,0,technical}'||bad))));IF r->>'error' IS DISTINCT FROM 'invalid_request' THEN RAISE EXCEPTION 'invalid technical accepted %',r;END IF;
 END LOOP;
 IF (SELECT count(*) FROM tj.speciq_packages WHERE organization_id=org)<>before_count THEN RAISE EXCEPTION 'bad technical left rows';END IF;
 SELECT version,updated_at INTO v,stamp FROM tj.speciq_packages WHERE id=pkg;
 body:=body||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',pkg,'expected_version',v,'expected_updated_at',stamp,'products',jsonb_build_array((body#>'{products,0}')-'technical'));
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'error' IS DISTINCT FROM 'invalid_request' THEN RAISE EXCEPTION 'ambiguous old client erased metadata %',r;END IF;
 body:=body||jsonb_build_object('products',jsonb_build_array(body#>'{products,0}'||jsonb_build_object('previous_product_id',prod)));
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'prior product inherit failed %',r;END IF;revised:=(r->>'package_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=revised AND width_inches=30.125 AND spec_snapshot#>>'{technical,docs,0,title}'='User supplied') THEN RAISE EXCEPTION 'technical inheritance lost';END IF;
 SELECT id INTO prod FROM tj.speciq_package_products WHERE package_id=revised;SELECT version,updated_at INTO v,stamp FROM tj.speciq_packages WHERE id=revised;
 body:=body||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',revised,'expected_version',v,'expected_updated_at',stamp,'products',jsonb_build_array(body#>'{products,0}'||jsonb_build_object('previous_product_id',prod,'technical','{}'::jsonb)));
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=(r->>'package_id')::uuid AND width_inches IS NULL AND finish IS NULL) OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg AND snapshot#>>'{products,0,spec_snapshot,technical,finish}'='Steel') THEN RAISE EXCEPTION 'explicit clear/history failed %',r;END IF;
 INSERT INTO tj.brand_catalog(organization_id,brand_name,brand_tier,logo_url) VALUES(org,'Technical Fixture','mid','https://example.invalid/brand.png') RETURNING id INTO brand_id;
 INSERT INTO tj.aiq_products(organization_id,brand_id,manufacturer_name,brand_name,model,short_description,category,finish,width_inches,height_inches,voltage,amperage,specs_json) VALUES(org,brand_id,'Fixture Manufacturer','Technical Fixture','TECH-1','Stored catalog fixture','refrigerator','Canonical finish',29.75,69.5,'120',15,'{"capacity":"actual stored"}'::jsonb) RETURNING id INTO catalog_id;
 INSERT INTO tj.pim_product_documents(product_id,doc_type,title,file_url,approved,is_current,embargoed,audience_tiers) VALUES(catalog_id,'spec_sheet','Allowed','https://example.invalid/allowed.pdf',true,true,false,ARRAY['all']),(catalog_id,'installation_guide','Embargoed','https://example.invalid/hidden.pdf',true,true,true,ARRAY['all']),(catalog_id,'owners_manual','Unapproved','https://example.invalid/unapproved.pdf',false,true,false,ARRAY['all']),(catalog_id,'energy_guide','Expired','https://example.invalid/expired.pdf',true,false,false,ARRAY['all']);
 INSERT INTO tj.pim_product_images(product_id,file_url,approved,embargoed,audience_tiers,is_primary) VALUES(catalog_id,'https://example.invalid/product.png',true,false,ARRAY['all'],true);
 body:=body-'previous_package_id'-'expected_version'-'expected_updated_at';body:=body||jsonb_build_object('request_id',gen_random_uuid(),'products',jsonb_build_array(jsonb_build_object('aiq_product_id',catalog_id,'msrp','10.00','quantity',1,'technical',jsonb_build_object('finish','Spoofed','width_inches','99','docs',jsonb_build_array(jsonb_build_object('doc_type','spec_sheet','file_url','https://evil.invalid/forged.pdf'))))));
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'catalog technical failed %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=(r->>'package_id')::uuid AND finish='Canonical finish' AND width_inches=29.75 AND electrical_requirements='120V, 15A' AND specifications->>'capacity'='actual stored' AND image_url='https://example.invalid/product.png' AND spec_snapshot->>'technical_state'='stored_catalog_facts' AND jsonb_array_length(spec_snapshot#>'{technical,docs}')=1 AND spec_snapshot#>>'{technical,docs,0,file_url}'='https://example.invalid/allowed.pdf') THEN RAISE EXCEPTION 'catalog spoof/asset restriction failed';END IF;
 PERFORM set_config('test.technical.native',native::text,true);PERFORM set_config('test.technical.body',jsonb_set(body,'{request_id}',to_jsonb(gen_random_uuid()::text))::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.technical.native'),true);
 r:=public.tj_runtime_speciq_drafts(current_setting('test.technical.body')::jsonb);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'authenticated technical save failed %',r;END IF;
END $$;
ROLLBACK;
SELECT 'PASS: technical manual/catalog snapshots, canonical facts and approved current nonembargoed documents/images, spoof/type/dimension/URL denial, retry, inherited previous product, explicit clear and preserved history; authenticated wrapper; fixtures rolled back' result;
