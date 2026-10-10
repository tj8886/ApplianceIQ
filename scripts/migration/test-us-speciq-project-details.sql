BEGIN;
SET LOCAL statement_timeout='25s';
DO $$
DECLARE actor uuid;native uuid;org uuid;body jsonb;r jsonb;pkg uuid;revised uuid;stamp timestamptz;v integer;bad jsonb;before_count bigint;
BEGIN
 SELECT im.source_user_id,im.target_user_id INTO actor,native FROM tj.source_user_identity_map im JOIN auth.users u ON u.id=im.target_user_id WHERE tj_private.microsoft_actor(u.id)=im.source_user_id AND u.email_confirmed_at IS NOT NULL LIMIT 1;
 IF native IS NULL THEN RAISE EXCEPTION 'mapped identity missing';END IF;
 INSERT INTO tj.organizations(name,slug) VALUES('Spec details rollback fixture','spec-details-rollback-'||gen_random_uuid()) RETURNING id INTO org;
 INSERT INTO tj.organization_members(organization_id,user_id,role,status) VALUES(org,actor,'member','active');
 PERFORM set_config('request.jwt.claim.sub',native::text,true);
 body:=jsonb_build_object('action','save','organization_id',org,'request_id',gen_random_uuid(),'customer',jsonb_build_object('name','Fixture','project_name','Details','builder_name','Builder <script>','designer_name','Designer','expected_purchase_date','2027-01-02','delivery_date','2027-01-03','notes','Internal notes'),'package_name','Details','include_pricing',true,'products',jsonb_build_array(jsonb_build_object('product_name','Fixture refrigerator','brand','Fixture','category','refrigerator','msrp','10.01','quantity',2)),'services','[]'::jsonb);
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'details save failed %',r;END IF;pkg:=(r->>'package_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg AND snapshot#>>'{project,builder_name}'='Builder <script>' AND snapshot#>>'{project,designer_name}'='Designer' AND snapshot#>>'{project,expected_purchase_date}'='2027-01-02' AND snapshot#>>'{project,delivery_date}'='2027-01-03' AND snapshot#>>'{project,notes}'='Internal notes') THEN RAISE EXCEPTION 'complete metadata snapshot missing';END IF;
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'replayed' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'details replay failed';END IF;
 SELECT count(*) INTO before_count FROM tj.speciq_packages WHERE organization_id=org;
 FOR bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(jsonb_build_object('delivery_date','2027-02-30'),jsonb_build_object('expected_purchase_date','01/02/2027'),jsonb_build_object('builder_name',42),jsonb_build_object('designer_name',repeat('x',201)),jsonb_build_object('notes',repeat('x',4001)),jsonb_build_object('notes',jsonb_build_object('fake','object')))) LOOP
 r:=public.tj_runtime_speciq_drafts(body||jsonb_build_object('request_id',gen_random_uuid(),'customer',body->'customer'||bad));IF r->>'error' IS DISTINCT FROM 'invalid_request' THEN RAISE EXCEPTION 'invalid metadata allowed %',r;END IF;
 END LOOP;
 IF (SELECT count(*) FROM tj.speciq_packages WHERE organization_id=org)<>before_count THEN RAISE EXCEPTION 'invalid metadata left package rows';END IF;
 SELECT version,updated_at INTO v,stamp FROM tj.speciq_packages WHERE id=pkg;
 body:=body||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',pkg,'expected_version',v,'expected_updated_at',stamp,'customer',(body->'customer')-'builder_name'-'designer_name'-'expected_purchase_date'-'delivery_date'-'notes');
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'old client revision failed %',r;END IF;revised:=(r->>'package_id')::uuid;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=revised AND snapshot#>>'{project,builder_name}'='Builder <script>' AND snapshot#>>'{project,notes}'='Internal notes' AND snapshot#>>'{project,delivery_date}'='2027-01-03') THEN RAISE EXCEPTION 'omitted details erased';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE id=pkg AND status='archived' AND superseded_by=revised) THEN RAISE EXCEPTION 'prior draft not retained';END IF;
 SELECT version,updated_at INTO v,stamp FROM tj.speciq_packages WHERE id=revised;
 body:=body||jsonb_build_object('request_id',gen_random_uuid(),'previous_package_id',revised,'expected_version',v,'expected_updated_at',stamp,'customer',body->'customer'||jsonb_build_object('builder_name',NULL,'notes','','delivery_date',NULL,'designer_name','New designer'));
 r:=public.tj_runtime_speciq_drafts(body);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'explicit metadata clear failed %',r;END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=(r->>'package_id')::uuid AND snapshot#>>'{project,builder_name}' IS NULL AND snapshot#>>'{project,notes}' IS NULL AND snapshot#>>'{project,delivery_date}' IS NULL AND snapshot#>>'{project,expected_purchase_date}'='2027-01-02' AND snapshot#>>'{project,designer_name}'='New designer') THEN RAISE EXCEPTION 'clear/change/inherit snapshot failed';END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions WHERE package_id=pkg AND snapshot#>>'{project,notes}'='Internal notes') THEN RAISE EXCEPTION 'historical notes changed';END IF;
 PERFORM set_config('test.details.native',native::text,true);PERFORM set_config('test.details.body',jsonb_set(body-'previous_package_id'-'expected_version'-'expected_updated_at','{request_id}',to_jsonb(gen_random_uuid()::text))::text,true);
END $$;
SET LOCAL ROLE authenticated;
DO $$DECLARE r jsonb;BEGIN
 PERFORM set_config('request.jwt.claim.sub',current_setting('test.details.native'),true);
 r:=public.tj_runtime_speciq_drafts(current_setting('test.details.body')::jsonb);IF r->>'ok' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'authenticated details save failed %',r;END IF;
END $$;
ROLLBACK;
SELECT 'PASS: project facts saved in atomic draft/full snapshot, exact date/type/length validation, replay, old-client inheritance, explicit clear/change, retained historical project/snapshot and authenticated save; fixtures rolled back' result;
