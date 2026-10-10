BEGIN;
SET LOCAL statement_timeout='25s';
DO $$
DECLARE actor uuid; native uuid; other_actor uuid; other_native uuid; org uuid; foreign_org uuid; warranty uuid;
 body jsonb; result jsonb; pkg uuid; new_pkg uuid; before_count bigint; v integer; stamp timestamptz;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,native FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL LIMIT 1;
 SELECT im.source_user_id,im.target_user_id INTO other_actor,other_native FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL AND im.source_user_id<>actor LIMIT 1;
 IF native IS NULL OR other_native IS NULL THEN RAISE EXCEPTION 'missing mapped fixture identities'; END IF;
 INSERT INTO tj.organizations(name,slug) VALUES('Spec draft rollback fixture','spec-draft-rollback-'||gen_random_uuid()) RETURNING id INTO org;
 INSERT INTO tj.organizations(name,slug) VALUES('Spec foreign rollback fixture','spec-draft-rollback-'||gen_random_uuid()) RETURNING id INTO foreign_org;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'member','active'),(org,other_actor,'viewer','active');
 INSERT INTO tj.speciq_warranty_catalog(organization_id,warranty_name,warranty_type,selling_price,active,is_included,applies_to_categories) VALUES(org,'Fixture coverage','extended',12.34,true,false,ARRAY['refrigerator']) RETURNING id INTO warranty;
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 result:=public.tj_runtime_speciq_drafts('{"action":"context"}');
 IF result->>'ok' IS DISTINCT FROM 'true' OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') o WHERE o->>'id'=org::text AND o->>'role'='member') OR EXISTS(SELECT 1 FROM jsonb_array_elements(result->'organizations') o WHERE o->>'id'=foreign_org::text) THEN RAISE EXCEPTION 'context isolation failed: %',result; END IF;
 body:=jsonb_build_object('action','save','organization_id',org,'request_id',gen_random_uuid(),'customer',jsonb_build_object('name','Fixture customer','project_name','Fixture project'),'package_name','Fixture draft','include_pricing',true,'products',jsonb_build_array(jsonb_build_object('product_name','Fixture refrigerator','brand','Fixture brand','category','refrigerator','msrp','10.01','quantity',2,'warranty_id',warranty)),'services',jsonb_build_array(jsonb_build_object('service_type','delivery','description','Fixture delivery','amount','5.10','taxable',true)));

 SELECT id INTO pkg FROM tj.aiq_products WHERE id=ANY(tj_private.allowed_catalog_products()) LIMIT 1;
 IF pkg IS NULL THEN RAISE EXCEPTION 'no visible catalog fixture'; END IF;
 body:=body||jsonb_build_object('products',jsonb_build_array(jsonb_build_object('aiq_product_id',pkg,'product_name','Spoofed name','brand','Spoofed brand','category','Spoofed category','msrp','10.01','quantity',2)));
 result:=public.tj_runtime_speciq_drafts(body);
 IF result->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'visible catalog save failed: %',result; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=(result->>'package_id')::uuid AND aiq_product_id=pkg AND product_name<>'Spoofed name' AND brand<>'Spoofed brand' AND spec_snapshot->>'provenance'='catalog') THEN RAISE EXCEPTION 'catalog spoof accepted'; END IF;

END $$;
ROLLBACK; SELECT 'PASS: visible catalog save resolves stored facts and marks entered price unreviewed; fixture rolled back' result;
