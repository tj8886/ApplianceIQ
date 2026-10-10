-- Native draft creation/revision only. Historical rows and files are retained.
CREATE TABLE tj_private.speciq_draft_requests (
 organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 native_actor uuid NOT NULL REFERENCES auth.users(id),
 request_id uuid NOT NULL, body jsonb NOT NULL,
 package_id uuid NOT NULL REFERENCES tj.speciq_packages(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(organization_id,native_actor,request_id)
);
ALTER TABLE tj_private.speciq_draft_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.speciq_draft_requests FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX speciq_draft_requests_native_idx ON tj_private.speciq_draft_requests(native_actor);
CREATE INDEX speciq_draft_requests_package_idx ON tj_private.speciq_draft_requests(package_id);

CREATE FUNCTION tj_private.speciq_actor_role(p_org uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT m.role FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id
 JOIN auth.users u ON u.id=(SELECT auth.uid())
 WHERE m.organization_id=p_org AND m.user_id=tj_private.microsoft_actor(u.id)
 AND m.status='active' AND o.status='active' AND o.deleted_at IS NULL
 AND u.email_confirmed_at IS NOT NULL LIMIT 1;
$$;
CREATE FUNCTION tj_private.speciq_drafts(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 n uuid:=auth.uid(); actor uuid; org uuid; role_name text; req uuid; old_id uuid;
 prior tj.speciq_packages%ROWTYPE; replay tj_private.speciq_draft_requests%ROWTYPE;
 pkg uuid:=gen_random_uuid(); proj uuid:=gen_random_uuid(); product uuid; warranty uuid;
 p jsonb; s jsonb; catalog tj.aiq_products%ROWTYPE; w tj.speciq_warranty_catalog%ROWTYPE;
 pname text; brand text; model text; cat text; price numeric; qty integer; ver integer:=1;
 product_total numeric:=0; service_total numeric:=0; war_total numeric:=0;
 i integer:=0; j integer:=0; snapshot jsonb;
BEGIN
 IF n IS NULL THEN RETURN jsonb_build_object('ok',false,'error','authentication_required'); END IF;
 actor:=tj_private.microsoft_actor(n);
 IF actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required'); END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=n AND email_confirmed_at IS NOT NULL) THEN
 RETURN jsonb_build_object('ok',false,'error','email_confirmation_required'); END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>131072 THEN
 RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 IF p_body->>'action'='context' THEN
 RETURN jsonb_build_object('ok',true,'organizations',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'name',o.name,'role',tj_private.speciq_actor_role(o.id)) ORDER BY o.created_at,o.id)
 FROM tj.organizations o WHERE tj_private.speciq_actor_role(o.id) IS NOT NULL),'[]'::jsonb)); END IF;
 IF p_body->>'action'<>'save' OR p_body->>'action' IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 org:=(p_body->>'organization_id')::uuid; req:=(p_body->>'request_id')::uuid;
 role_name:=tj_private.speciq_actor_role(org);
 IF role_name IS NULL OR role_name NOT IN('owner','admin','manager','member') THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required'); END IF;
 IF req IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','request_id','previous_package_id','expected_version','expected_updated_at','customer','package_name','include_pricing','products','services')) THEN
 RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));
 SELECT * INTO replay FROM tj_private.speciq_draft_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
 RETURN jsonb_build_object('ok',true,'package_id',replay.package_id,'replayed',true,'pricing_state','draft_tax_unreviewed'); END IF;
 old_id:=nullif(p_body->>'previous_package_id','')::uuid;
 IF old_id IS NOT NULL THEN
 SELECT * INTO prior FROM tj.speciq_packages WHERE id=old_id AND organization_id=org FOR UPDATE;
 IF NOT FOUND OR (prior.created_by IS DISTINCT FROM actor AND role_name NOT IN('owner','admin','manager')) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable'); END IF;
 IF prior.deleted_at IS NOT NULL OR prior.superseded_by IS NOT NULL OR prior.locked IS TRUE OR prior.status NOT IN('draft','in_progress') OR prior.approval_status NOT IN('not_required','returned') OR prior.sent_at IS NOT NULL OR prior.approved_at IS NOT NULL OR prior.shopify_pushed_at IS NOT NULL THEN
 RETURN jsonb_build_object('ok',false,'error','package_not_editable'); END IF;
 IF (p_body->>'expected_version')::integer IS DISTINCT FROM prior.version OR (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM prior.updated_at THEN
 RETURN jsonb_build_object('ok',false,'error','revision_conflict'); END IF;
 ver:=prior.version+1;
 END IF;
 IF jsonb_typeof(p_body->'customer') IS DISTINCT FROM 'object' OR jsonb_typeof(p_body->'products') IS DISTINCT FROM 'array' OR jsonb_typeof(p_body->'services') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_body->'products') NOT BETWEEN 1 AND 50 OR jsonb_array_length(p_body->'services')>50 OR length(btrim(coalesce(p_body->>'package_name',''))) NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_body->'include_pricing') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_body->'customer') k WHERE k NOT IN('name','email','phone','project_name','address','room')) OR length(btrim(coalesce(p_body#>>'{customer,name}',''))) NOT BETWEEN 1 AND 200 OR length(btrim(coalesce(p_body#>>'{customer,project_name}',''))) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF length(coalesce(p_body#>>'{customer,email}',''))>254 OR length(coalesce(p_body#>>'{customer,phone}',''))>50 OR length(coalesce(p_body#>>'{customer,address}',''))>1000 OR length(coalesce(p_body#>>'{customer,room}',''))>100 OR (coalesce(p_body#>>'{customer,email}','')<>'' AND p_body#>>'{customer,email}' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 INSERT INTO tj.speciq_projects(id,organization_id,customer_name,project_name,customer_email,customer_phone,property_address,room_name,created_by)
 VALUES(proj,org,btrim(p_body#>>'{customer,name}'),btrim(p_body#>>'{customer,project_name}'),nullif(p_body#>>'{customer,email}',''),nullif(p_body#>>'{customer,phone}',''),nullif(p_body#>>'{customer,address}',''),nullif(p_body#>>'{customer,room}',''),actor);
 INSERT INTO tj.speciq_packages(id,organization_id,project_id,package_name,version,quote_version,status,approval_status,include_pricing,created_by,updated_by,supersedes,total_promo,total_negotiated,total_tax,total_final,total_savings,volume_discount)
 VALUES(pkg,org,proj,btrim(p_body->>'package_name'),ver,ver,'draft','not_required',(p_body->>'include_pricing')::boolean,actor,actor,old_id,NULL,NULL,NULL,NULL,NULL,NULL);
 FOR p IN SELECT value FROM jsonb_array_elements(p_body->'products') LOOP
 IF jsonb_typeof(p)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN('aiq_product_id','product_name','brand','model_number','category','msrp','quantity','warranty_id')) OR coalesce(p->>'msrp','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR coalesce(p->>'quantity','') !~ '^[0-9]{1,2}$' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 price:=(p->>'msrp')::numeric; qty:=(p->>'quantity')::integer;
 IF qty NOT BETWEEN 1 AND 99 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF nullif(p->>'aiq_product_id','') IS NOT NULL THEN
 IF NOT coalesce((p->>'aiq_product_id')::uuid=ANY(tj_private.allowed_catalog_products()),false) THEN RAISE EXCEPTION 'catalog unavailable' USING ERRCODE='22023'; END IF;
 SELECT * INTO catalog FROM tj.aiq_products WHERE id=(p->>'aiq_product_id')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'catalog unavailable' USING ERRCODE='22023'; END IF;
 pname:=coalesce(nullif(catalog.short_description,''),catalog.model_number); brand:=catalog.brand_name; model:=catalog.model_number; cat:=catalog.category;
 snapshot:=jsonb_build_object('provenance','catalog','catalog_product_id',catalog.id,'catalog_msrp',catalog.msrp,'draft_entered_price',price,'pricing_state','user_quote_unreviewed');
 ELSE
 pname:=btrim(p->>'product_name'); brand:=p->>'brand'; model:=p->>'model_number'; cat:=p->>'category';
 snapshot:=jsonb_build_object('provenance','user_entry','draft_entered_price',price,'pricing_state','user_quote_unreviewed');
 END IF;
 IF pname IS NULL OR length(pname) NOT BETWEEN 1 AND 500 OR length(coalesce(brand,''))>200 OR length(coalesce(model,''))>200 OR length(coalesce(cat,''))>200 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 product:=gen_random_uuid();
 INSERT INTO tj.speciq_package_products(id,package_id,organization_id,product_name,brand,model_number,category,msrp,quantity,extended_msrp,aiq_product_id,spec_snapshot,sort_order)
 VALUES(product,pkg,org,pname,brand,model,cat,price,qty,price*qty,nullif(p->>'aiq_product_id','')::uuid,snapshot,i);
 product_total:=product_total+price*qty;
 IF nullif(p->>'warranty_id','') IS NOT NULL THEN
 SELECT * INTO w FROM tj.speciq_warranty_catalog WHERE id=(p->>'warranty_id')::uuid AND organization_id=org AND active IS TRUE FOR SHARE;
 IF NOT FOUND OR (cardinality(w.applies_to_categories)>0 AND NOT coalesce(cat=ANY(w.applies_to_categories),false)) OR (w.is_included IS NOT TRUE AND (w.selling_price IS NULL OR w.selling_price<0)) THEN RAISE EXCEPTION 'invalid warranty' USING ERRCODE='22023'; END IF;
 warranty:=gen_random_uuid();
 INSERT INTO tj.speciq_product_warranties(id,package_id,package_product_id,organization_id,warranty_catalog_id,warranty_name,warranty_type,warranty_provider,coverage_months,coverage_label,parts_coverage,labour_coverage,designation,registration_required,transferable,coverage_summary,exclusions,customer_facing_notes,internal_notes,selling_price,cost,taxable,is_included,selected_by,selection_status)
 VALUES(warranty,pkg,product,org,w.id,w.warranty_name,w.warranty_type,w.warranty_provider,w.coverage_length_months,w.coverage_label,w.parts_coverage,w.labour_coverage,w.designation,w.registration_required,w.transferable,w.coverage_summary,w.exclusions,w.customer_facing_notes,w.internal_notes,CASE WHEN w.is_included THEN 0 ELSE w.selling_price END,NULL,w.taxable,w.is_included,actor,'selected');
 UPDATE tj.speciq_package_products SET selected_warranty_id=warranty,warranty_snapshot=jsonb_build_object('catalog_id',w.id,'price',CASE WHEN w.is_included THEN 0 ELSE w.selling_price END,'quantity',qty,'included',w.is_included) WHERE id=product;
 war_total:=war_total+(CASE WHEN w.is_included THEN 0 ELSE w.selling_price END)*qty;
 END IF;
 i:=i+1;
 END LOOP;
 FOR s IN SELECT value FROM jsonb_array_elements(p_body->'services') LOOP
 IF jsonb_typeof(s)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(s) k WHERE k NOT IN('service_type','description','amount','taxable')) OR s->>'service_type' IS NULL OR s->>'service_type' NOT IN('delivery','installation','haul_away','accessories','environmental_fee','other') OR coalesce(s->>'amount','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR length(coalesce(s->>'description',''))>1000 OR jsonb_typeof(s->'taxable') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 INSERT INTO tj.speciq_package_services(package_id,organization_id,service_type,description,amount,taxable,sort_order,cost,gross_margin)
 VALUES(pkg,org,s->>'service_type',s->>'description',(s->>'amount')::numeric,(s->>'taxable')::boolean,j,NULL,NULL);
 service_total:=service_total+(s->>'amount')::numeric; j:=j+1;
 END LOOP;
 UPDATE tj.speciq_packages SET total_msrp=product_total,total_services=service_total,warranty_total=war_total WHERE id=pkg;
 IF old_id IS NOT NULL THEN UPDATE tj.speciq_packages SET superseded_by=pkg,status='archived',updated_by=actor,updated_at=now() WHERE id=old_id; END IF;
 SELECT jsonb_build_object('package',to_jsonb(k),'project',(SELECT to_jsonb(r) FROM tj.speciq_projects r WHERE r.id=proj),'products',(SELECT jsonb_agg(to_jsonb(r) ORDER BY sort_order) FROM tj.speciq_package_products r WHERE r.package_id=pkg),'services',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY sort_order) FROM tj.speciq_package_services r WHERE r.package_id=pkg),'[]'::jsonb),'warranties',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM tj.speciq_product_warranties r WHERE r.package_id=pkg),'[]'::jsonb),'pricing_state','draft_tax_unreviewed') INTO snapshot FROM tj.speciq_packages k WHERE k.id=pkg;
 INSERT INTO tj.speciq_package_versions(package_id,version_number,snapshot,created_by) VALUES(pkg,ver,snapshot,actor);
 INSERT INTO tj.speciq_package_events(package_id,event_type,event_data) VALUES(pkg,CASE WHEN old_id IS NULL THEN 'draft_created' ELSE 'draft_revision' END,jsonb_build_object('source_actor',actor,'previous_package_id',old_id,'request_id',req));
 INSERT INTO tj_private.speciq_draft_requests(organization_id,native_actor,request_id,body,package_id) VALUES(org,n,req,p_body,pkg);
 RETURN jsonb_build_object('ok',true,'package_id',pkg,'version',ver,'replayed',false,'pricing_state','draft_tax_unreviewed','subtotal',product_total+service_total+war_total);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR check_violation OR not_null_violation OR foreign_key_violation OR numeric_value_out_of_range OR datetime_field_overflow THEN
 RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
CREATE FUNCTION public.tj_runtime_speciq_drafts(p_body jsonb)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.speciq_drafts(p_body); $$;
REVOKE ALL ON FUNCTION tj_private.speciq_actor_role(uuid),tj_private.speciq_drafts(jsonb),public.tj_runtime_speciq_drafts(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_drafts(jsonb),public.tj_runtime_speciq_drafts(jsonb) TO authenticated;
NOTIFY pgrst,'reload schema';
