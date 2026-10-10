-- Snapshot technical facts and accessible document metadata; no provider/file fetch.
CREATE FUNCTION tj_private.speciq_https_url(p_url text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT p_url IS NOT NULL AND length(p_url)<=2000 AND p_url ~ '^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?([/?#][^[:space:]<>"'']*)?$';
$$;
REVOKE ALL ON FUNCTION tj_private.speciq_https_url(text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.speciq_drafts(p_body jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE
 n uuid:=auth.uid(); actor uuid; org uuid; role_name text; req uuid; old_id uuid;
 contact_link uuid; deal_link uuid; contact_row tj.contacts%ROWTYPE; checked_deal uuid;
 prior tj.speciq_packages%ROWTYPE; prior_project tj.speciq_projects%ROWTYPE; field_name text; field_value text; replay tj_private.speciq_draft_requests%ROWTYPE;
 pkg uuid:=gen_random_uuid(); proj uuid:=gen_random_uuid(); product uuid; warranty uuid;
 p jsonb; s jsonb; tech jsonb; doc jsonb; prev_product tj.speciq_package_products%ROWTYPE; tech_key text; tech_value text; catalog tj.aiq_products%ROWTYPE; w tj.speciq_warranty_catalog%ROWTYPE;
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
 IF req IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','request_id','previous_package_id','expected_version','expected_updated_at','customer','package_name','include_pricing','products','services','contact_id','deal_id','salesperson_name')) THEN
 RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));
 contact_link:=nullif(p_body->>'contact_id','')::uuid;deal_link:=nullif(p_body->>'deal_id','')::uuid;
 IF deal_link IS NOT NULL AND contact_link IS NULL THEN RETURN jsonb_build_object('ok',false,'error','crm_link_unavailable'); END IF;
 IF contact_link IS NOT NULL THEN
 SELECT * INTO contact_row FROM tj.contacts WHERE id=contact_link AND organization_id=org AND deleted_at IS NULL FOR SHARE;
 IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'error','crm_link_unavailable'); END IF;
 END IF;
 IF deal_link IS NOT NULL THEN
 SELECT id INTO checked_deal FROM tj.crm_deals WHERE id=deal_link AND organization_id=org AND contact_id=contact_link AND deleted_at IS NULL AND closed_at IS NULL AND NOT coalesce(is_archived,false) AND tj.aiq_scope_allows(org,owner_user_id) AND tj.aiq_store_allows(org,location_id) FOR SHARE;
 IF checked_deal IS NULL THEN RETURN jsonb_build_object('ok',false,'error','crm_link_unavailable'); END IF;
 END IF;
 IF length(coalesce(p_body->>'salesperson_name',''))>200 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 SELECT * INTO replay FROM tj_private.speciq_draft_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
 RETURN jsonb_build_object('ok',true,'package_id',replay.package_id,'replayed',true,'pricing_state','draft_tax_unreviewed'); END IF;
 old_id:=nullif(p_body->>'previous_package_id','')::uuid;
 IF old_id IS NOT NULL THEN
 SELECT * INTO prior FROM tj.speciq_packages WHERE id=old_id AND organization_id=org FOR UPDATE;
 IF NOT FOUND OR (prior.created_by IS DISTINCT FROM actor AND role_name NOT IN('owner','admin','manager')) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable'); END IF;
 IF (prior.contact_id IS NOT NULL OR prior.deal_id IS NOT NULL) AND (NOT (p_body ? 'contact_id') OR NOT (p_body ? 'deal_id')) THEN RETURN jsonb_build_object('ok',false,'error','crm_link_unavailable'); END IF;
 IF prior.deleted_at IS NOT NULL OR prior.superseded_by IS NOT NULL OR prior.locked IS TRUE OR prior.status NOT IN('draft','in_progress') OR coalesce(prior.approval_status,'unknown') NOT IN('not_required','returned') OR prior.sent_at IS NOT NULL OR prior.approved_at IS NOT NULL OR prior.shopify_pushed_at IS NOT NULL THEN
 RETURN jsonb_build_object('ok',false,'error','package_not_editable'); END IF;
 IF (p_body->>'expected_version')::integer IS DISTINCT FROM prior.version OR (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM prior.updated_at THEN
 RETURN jsonb_build_object('ok',false,'error','revision_conflict'); END IF;
 SELECT * INTO prior_project FROM tj.speciq_projects WHERE id=prior.project_id AND organization_id=org;
 ver:=prior.version+1;
 END IF;
 IF jsonb_typeof(p_body->'customer') IS DISTINCT FROM 'object' OR jsonb_typeof(p_body->'products') IS DISTINCT FROM 'array' OR jsonb_typeof(p_body->'services') IS DISTINCT FROM 'array' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF jsonb_array_length(p_body->'products') NOT BETWEEN 1 AND 50 OR jsonb_array_length(p_body->'services')>50 OR length(btrim(coalesce(p_body->>'package_name',''))) NOT BETWEEN 1 AND 200 OR jsonb_typeof(p_body->'include_pricing') IS DISTINCT FROM 'boolean' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_body->'customer') k WHERE k NOT IN('name','email','phone','project_name','address','room','builder_name','designer_name','expected_purchase_date','delivery_date','notes')) OR length(btrim(coalesce(p_body#>>'{customer,name}',''))) NOT BETWEEN 1 AND 200 OR length(btrim(coalesce(p_body#>>'{customer,project_name}',''))) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF length(coalesce(p_body#>>'{customer,email}',''))>254 OR length(coalesce(p_body#>>'{customer,phone}',''))>50 OR length(coalesce(p_body#>>'{customer,address}',''))>1000 OR length(coalesce(p_body#>>'{customer,room}',''))>100 OR (coalesce(p_body#>>'{customer,email}','')<>'' AND p_body#>>'{customer,email}' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 FOR field_name IN SELECT unnest(ARRAY['builder_name','designer_name','expected_purchase_date','delivery_date','notes']) LOOP
 IF p_body->'customer' ? field_name THEN
 IF jsonb_typeof(p_body->'customer'->field_name) NOT IN('string','null') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 field_value:=nullif(p_body->'customer'->>field_name,'');
 IF length(coalesce(field_value,''))>(CASE field_name WHEN 'notes' THEN 4000 WHEN 'expected_purchase_date' THEN 10 WHEN 'delivery_date' THEN 10 ELSE 200 END) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF field_name IN('expected_purchase_date','delivery_date') AND field_value IS NOT NULL THEN
 IF field_value !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR field_value::date::text<>field_value THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END IF;
 END IF;
 END LOOP;
 INSERT INTO tj.speciq_projects(id,organization_id,customer_name,project_name,customer_email,customer_phone,property_address,room_name,created_by,contact_id,deal_id,builder_name,designer_name,expected_purchase_date,delivery_date,notes)
 VALUES(proj,org,CASE WHEN contact_link IS NOT NULL THEN btrim(contact_row.first_name||' '||coalesce(contact_row.last_name,'')) ELSE btrim(p_body#>>'{customer,name}') END,btrim(p_body#>>'{customer,project_name}'),CASE WHEN contact_link IS NOT NULL THEN contact_row.email ELSE nullif(p_body#>>'{customer,email}','') END,CASE WHEN contact_link IS NOT NULL THEN coalesce(contact_row.phone,contact_row.mobile_phone) ELSE nullif(p_body#>>'{customer,phone}','') END,nullif(p_body#>>'{customer,address}',''),nullif(p_body#>>'{customer,room}',''),actor,contact_link,deal_link,
 CASE WHEN p_body->'customer' ? 'builder_name' THEN nullif(p_body#>>'{customer,builder_name}','') ELSE prior_project.builder_name END,
 CASE WHEN p_body->'customer' ? 'designer_name' THEN nullif(p_body#>>'{customer,designer_name}','') ELSE prior_project.designer_name END,
 CASE WHEN p_body->'customer' ? 'expected_purchase_date' THEN nullif(p_body#>>'{customer,expected_purchase_date}','')::date ELSE prior_project.expected_purchase_date END,
 CASE WHEN p_body->'customer' ? 'delivery_date' THEN nullif(p_body#>>'{customer,delivery_date}','')::date ELSE prior_project.delivery_date END,
 CASE WHEN p_body->'customer' ? 'notes' THEN nullif(p_body#>>'{customer,notes}','') ELSE prior_project.notes END);
 INSERT INTO tj.speciq_packages(id,organization_id,project_id,package_name,version,quote_version,status,approval_status,include_pricing,created_by,updated_by,supersedes,total_promo,total_negotiated,total_tax,total_final,total_savings,volume_discount,contact_id,deal_id,salesperson_name)
 VALUES(pkg,org,proj,btrim(p_body->>'package_name'),ver,ver,'draft','not_required',(p_body->>'include_pricing')::boolean,actor,actor,old_id,NULL,NULL,NULL,NULL,NULL,NULL,contact_link,deal_link,nullif(btrim(p_body->>'salesperson_name'),''));
 FOR p IN SELECT value FROM jsonb_array_elements(p_body->'products') LOOP
 IF jsonb_typeof(p)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(p) k WHERE k NOT IN('aiq_product_id','product_name','brand','model_number','category','msrp','quantity','warranty_id','technical','previous_product_id')) OR coalesce(p->>'msrp','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' OR coalesce(p->>'quantity','') !~ '^[0-9]{1,2}$' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 tech:=p->'technical';prev_product:=NULL;
 IF nullif(p->>'previous_product_id','') IS NOT NULL THEN
 SELECT * INTO prev_product FROM tj.speciq_package_products WHERE id=(p->>'previous_product_id')::uuid AND package_id=old_id AND organization_id=org FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'invalid prior product' USING ERRCODE='22023';END IF;
 END IF;
 IF NOT(p ? 'technical') THEN
 IF prev_product.id IS NOT NULL AND prev_product.aiq_product_id IS NULL THEN tech:=prev_product.spec_snapshot->'technical';
 ELSIF old_id IS NOT NULL AND EXISTS(SELECT 1 FROM tj.speciq_package_products oldp WHERE oldp.package_id=old_id AND oldp.aiq_product_id IS NULL AND (EXISTS(SELECT 1 FROM jsonb_each(coalesce(oldp.spec_snapshot->'technical','{}'::jsonb)) item WHERE item.key<>'docs' AND item.value<>'null'::jsonb) OR jsonb_array_length(coalesce(oldp.spec_snapshot#>'{technical,docs}','[]'::jsonb))>0)) THEN
 RAISE EXCEPTION 'technical details must be explicit in revision' USING ERRCODE='22023';
 END IF;
 END IF;
 tech:=coalesce(tech,'{}'::jsonb);
 IF jsonb_typeof(tech) IS DISTINCT FROM 'object' OR octet_length(tech::text)>16384 OR EXISTS(SELECT 1 FROM jsonb_object_keys(tech) AS keys(key_name) WHERE key_name NOT IN('finish','width_inches','height_inches','depth_inches','electrical_requirements','product_image','brand_logo','docs','specifications')) THEN RAISE EXCEPTION 'invalid technical metadata' USING ERRCODE='22023';END IF;
 FOR tech_key,tech_value IN SELECT key,value #>> '{}' FROM jsonb_each(tech) WHERE key NOT IN('docs','specifications') LOOP
 IF tech_key IN('width_inches','height_inches','depth_inches') THEN
 IF tech_value IS NOT NULL AND (jsonb_typeof(tech->tech_key) NOT IN('string','number') OR tech_value !~ '^[0-9]{1,3}(\.[0-9]{1,3})?$' OR tech_value::numeric<=0 OR tech_value::numeric>999.999) THEN RAISE EXCEPTION 'invalid dimension' USING ERRCODE='22023';END IF;
 ELSE
 IF jsonb_typeof(tech->tech_key) NOT IN('string','null') OR length(coalesce(tech_value,''))>(CASE tech_key WHEN 'finish' THEN 200 WHEN 'electrical_requirements' THEN 1000 ELSE 2000 END) OR (tech_key IN('product_image','brand_logo') AND tech_value IS NOT NULL AND NOT tj_private.speciq_https_url(tech_value)) THEN RAISE EXCEPTION 'invalid metadata' USING ERRCODE='22023';END IF;
 END IF;
 END LOOP;
 IF tech ? 'specifications' AND tech->'specifications'<>'null'::jsonb THEN
 IF jsonb_typeof(tech->'specifications')<>'object' OR (SELECT count(*) FROM jsonb_object_keys(tech->'specifications'))>50 OR EXISTS(SELECT 1 FROM jsonb_each(tech->'specifications') item WHERE length(item.key)>100 OR jsonb_typeof(item.value) NOT IN('string','number','boolean','null') OR length(item.value::text)>1000) THEN RAISE EXCEPTION 'invalid specifications' USING ERRCODE='22023';END IF;
 END IF;
 IF tech ? 'docs' THEN
 IF jsonb_typeof(tech->'docs') IS DISTINCT FROM 'array' OR jsonb_array_length(tech->'docs')>25 THEN RAISE EXCEPTION 'invalid docs' USING ERRCODE='22023';END IF;
 FOR doc IN SELECT value FROM jsonb_array_elements(tech->'docs') LOOP
 IF jsonb_typeof(doc)<>'object' OR EXISTS(SELECT 1 FROM jsonb_object_keys(doc) AS keys(key_name) WHERE key_name NOT IN('doc_type','title','file_url')) OR jsonb_typeof(doc->'doc_type') IS DISTINCT FROM 'string' OR length(coalesce(doc->>'doc_type','')) NOT BETWEEN 1 AND 100 OR jsonb_typeof(doc->'title') NOT IN('string','null') OR length(coalesce(doc->>'title',''))>500 OR jsonb_typeof(doc->'file_url') IS DISTINCT FROM 'string' OR NOT tj_private.speciq_https_url(doc->>'file_url') THEN RAISE EXCEPTION 'invalid doc' USING ERRCODE='22023';END IF;
 END LOOP;
 END IF;
 price:=(p->>'msrp')::numeric; qty:=(p->>'quantity')::integer;
 IF qty NOT BETWEEN 1 AND 99 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 IF nullif(p->>'aiq_product_id','') IS NOT NULL THEN
 IF NOT coalesce((p->>'aiq_product_id')::uuid=ANY(tj_private.allowed_catalog_products()),false) THEN RAISE EXCEPTION 'catalog unavailable' USING ERRCODE='22023'; END IF;
 SELECT * INTO catalog FROM tj.aiq_products WHERE id=(p->>'aiq_product_id')::uuid;
 IF NOT FOUND THEN RAISE EXCEPTION 'catalog unavailable' USING ERRCODE='22023'; END IF;
 pname:=coalesce(nullif(catalog.short_description,''),catalog.model); brand:=catalog.brand_name; model:=catalog.model; cat:=catalog.category;
 tech:=jsonb_build_object('finish',catalog.finish,'width_inches',catalog.width_inches,'height_inches',catalog.height_inches,'depth_inches',catalog.depth_inches,'electrical_requirements',nullif(concat_ws(', ',CASE WHEN catalog.voltage IS NOT NULL THEN catalog.voltage||'V' END,CASE WHEN catalog.amperage IS NOT NULL THEN catalog.amperage::text||'A' END),''),
 'product_image',(SELECT coalesce(img.cdn_url,img.file_url) FROM tj.pim_product_images img WHERE img.product_id=catalog.id AND img.approved IS TRUE AND tj_private.catalog_asset_allowed(img.available_from,img.available_until,img.embargoed,img.audience_tiers,img.exclusive_codes) AND tj_private.speciq_https_url(coalesce(img.cdn_url,img.file_url)) ORDER BY img.is_primary DESC NULLS LAST,img.display_order NULLS LAST,img.id LIMIT 1),
 'specifications',catalog.specs_json,
 'brand_logo',(SELECT b.logo_url FROM tj.brand_catalog b WHERE b.id=catalog.brand_id AND b.organization_id=catalog.organization_id AND tj_private.speciq_https_url(b.logo_url)),
 'docs',coalesce((SELECT jsonb_agg(jsonb_build_object('doc_type',r.doc_type,'title',r.title,'file_url',r.file_url)) FROM (SELECT pd.doc_type,pd.title,pd.file_url FROM tj.pim_product_documents pd WHERE pd.product_id=catalog.id AND pd.approved IS TRUE AND pd.is_current IS TRUE AND (pd.expiry_date IS NULL OR pd.expiry_date>=current_date) AND tj_private.catalog_asset_allowed(pd.available_from,pd.available_until,pd.embargoed,pd.audience_tiers,pd.exclusive_codes) AND tj_private.speciq_https_url(pd.file_url) ORDER BY pd.created_at DESC,pd.id LIMIT 25) r),'[]'::jsonb));
 snapshot:=jsonb_build_object('provenance','catalog','catalog_product_id',catalog.id,'catalog_msrp',catalog.msrp,'draft_entered_price',price,'pricing_state','user_quote_unreviewed');
 ELSE
 pname:=btrim(p->>'product_name'); brand:=p->>'brand'; model:=p->>'model_number'; cat:=p->>'category';
 snapshot:=jsonb_build_object('provenance','user_entry','draft_entered_price',price,'pricing_state','user_quote_unreviewed');
 END IF;
 snapshot:=snapshot||jsonb_build_object('technical',tech,'technical_state',CASE WHEN nullif(p->>'aiq_product_id','') IS NULL THEN 'user_entry_unreviewed' ELSE 'stored_catalog_facts' END);
 IF pname IS NULL OR length(pname) NOT BETWEEN 1 AND 500 OR length(coalesce(brand,''))>200 OR length(coalesce(model,''))>200 OR length(coalesce(cat,''))>200 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
 product:=gen_random_uuid();
 INSERT INTO tj.speciq_package_products(id,package_id,organization_id,product_name,brand,model_number,category,msrp,quantity,aiq_product_id,spec_snapshot,sort_order,finish,width_inches,height_inches,depth_inches,electrical_requirements,image_url,specifications)
 VALUES(product,pkg,org,pname,brand,model,cat,price,qty,nullif(p->>'aiq_product_id','')::uuid,snapshot,i,tech->>'finish',(tech->>'width_inches')::numeric,(tech->>'height_inches')::numeric,(tech->>'depth_inches')::numeric,tech->>'electrical_requirements',tech->>'product_image',nullif(tech->'specifications','null'::jsonb));
 product_total:=product_total+price*qty;
 IF nullif(p->>'warranty_id','') IS NOT NULL THEN
 SELECT * INTO w FROM tj.speciq_warranty_catalog WHERE id=(p->>'warranty_id')::uuid AND organization_id=org AND active IS TRUE FOR SHARE;
 IF NOT FOUND OR (cardinality(w.applies_to_categories)>0 AND NOT coalesce(cat=ANY(w.applies_to_categories),false)) OR (w.is_included IS NOT TRUE AND (w.selling_price IS NULL OR w.selling_price<0)) THEN RAISE EXCEPTION 'invalid warranty' USING ERRCODE='22023'; END IF;
 warranty:=gen_random_uuid();
 INSERT INTO tj.speciq_product_warranties(id,package_id,package_product_id,organization_id,warranty_catalog_id,warranty_name,warranty_type,warranty_provider,coverage_length_months,coverage_label,parts_coverage,labour_coverage,designation,registration_required,transferable,coverage_summary,exclusions,customer_facing_notes,internal_notes,selling_price,cost,taxable,is_included,selected_by,selection_status)
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
 INSERT INTO tj.speciq_package_events(package_id,event_type,event_data) VALUES(pkg,'created',jsonb_build_object('draft_action',CASE WHEN old_id IS NULL THEN 'draft_created' ELSE 'draft_revision' END,'source_actor',actor,'previous_package_id',old_id,'request_id',req));
 INSERT INTO tj_private.speciq_draft_requests(organization_id,native_actor,request_id,body,package_id) VALUES(org,n,req,p_body,pkg);
 RETURN jsonb_build_object('ok',true,'package_id',pkg,'version',ver,'replayed',false,'pricing_state','draft_tax_unreviewed','subtotal',product_total+service_total+war_total);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR check_violation OR not_null_violation OR foreign_key_violation OR numeric_value_out_of_range OR datetime_field_overflow OR invalid_datetime_format THEN
 RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$$;
NOTIFY pgrst,'reload schema';
