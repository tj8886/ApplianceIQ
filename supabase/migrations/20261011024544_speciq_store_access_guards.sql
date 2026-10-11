-- Internal actor lookup is deliberately not executable by clients. It is also used
-- by the fenced service worker, whose verified actor is explicit rather than auth.uid().
CREATE FUNCTION tj_private.speciq_deal_store_allows_as(p_org uuid,p_deal uuid,p_actor uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE m tj.organization_members; sid uuid;
BEGIN
 IF p_actor IS NULL THEN RETURN false;END IF;
 SELECT * INTO m FROM tj.organization_members WHERE organization_id=p_org AND user_id=p_actor AND status='active';
 IF NOT FOUND THEN RETURN false;END IF;
 IF p_deal IS NULL THEN RETURN true;END IF;
 SELECT location_id INTO sid FROM tj.crm_deals WHERE id=p_deal AND organization_id=p_org;
 IF NOT FOUND THEN RETURN false;END IF;
 IF sid IS NULL OR EXISTS(SELECT 1 FROM tj.platform_admins WHERE user_id=p_actor) THEN RETURN true;END IF;
 IF EXISTS(SELECT 1 FROM tj.org_location_members lm JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=p_org
 WHERE lm.organization_id=p_org AND lm.user_id=p_actor AND NOT lm.is_active AND (l.id=sid OR l.iq_store_id=sid)) THEN RETURN false;END IF;
 IF m.role IN('owner','admin') OR coalesce(m.visibility_scope,'own')='all' THEN RETURN true;END IF;
 RETURN EXISTS(SELECT 1 FROM tj.org_location_members lm JOIN tj.org_locations l ON l.id=lm.location_id AND l.organization_id=p_org
 WHERE lm.organization_id=p_org AND lm.user_id=p_actor AND lm.is_active AND (l.id=sid OR l.iq_store_id=sid));
END $$;
CREATE FUNCTION tj_private.speciq_project_store_allows_as(p_org uuid,p_project uuid,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.speciq_projects p WHERE p.id=p_project AND p.organization_id=p_org
 AND tj_private.speciq_deal_store_allows_as(p_org,p.deal_id,p_actor)
 AND NOT EXISTS(SELECT 1 FROM tj.speciq_packages k WHERE k.project_id=p.id
 AND (k.organization_id IS DISTINCT FROM p_org OR NOT tj_private.speciq_deal_store_allows_as(p_org,k.deal_id,p_actor))));
$$;
CREATE FUNCTION tj_private.speciq_package_store_allows_as(p_org uuid,p_package uuid,p_actor uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.speciq_packages k WHERE k.id=p_package AND k.organization_id=p_org
 AND tj_private.speciq_deal_store_allows_as(p_org,k.deal_id,p_actor)
 AND tj_private.speciq_project_store_allows_as(p_org,k.project_id,p_actor));
$$;
CREATE FUNCTION tj_private.speciq_project_store_allows(p_org uuid,p_project uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND tj_private.speciq_project_store_allows_as(p_org,p_project,tj_private.current_source_user_id());
$$;
CREATE FUNCTION tj_private.speciq_package_store_allows(p_org uuid,p_package uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT auth.uid() IS NOT NULL AND tj_private.speciq_package_store_allows_as(p_org,p_package,tj_private.current_source_user_id());
$$;
REVOKE ALL ON FUNCTION tj_private.speciq_deal_store_allows_as(uuid,uuid,uuid),tj_private.speciq_project_store_allows_as(uuid,uuid,uuid),tj_private.speciq_package_store_allows_as(uuid,uuid,uuid),tj_private.speciq_project_store_allows(uuid,uuid),tj_private.speciq_package_store_allows(uuid,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.speciq_project_store_allows(uuid,uuid),tj_private.speciq_package_store_allows(uuid,uuid) TO authenticated;

CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_projects AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_project_store_allows(organization_id,id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_packages AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_package_products AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,package_id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_package_services AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,package_id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_product_warranties AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,package_id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_approval_history AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,package_id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_extension_requests AS RESTRICTIVE FOR SELECT TO authenticated USING(tj_private.speciq_package_store_allows(organization_id,package_id));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_package_events AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.speciq_packages k WHERE k.id=package_id AND tj_private.speciq_package_store_allows(k.organization_id,k.id)));
CREATE POLICY consolidation_speciq_store_scope ON tj.speciq_package_versions AS RESTRICTIVE FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM tj.speciq_packages k WHERE k.id=package_id AND tj_private.speciq_package_store_allows(k.organization_id,k.id)));

CREATE OR REPLACE FUNCTION tj_private.speciq_add_comparison_winner(p_package_id uuid, p_comparison_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'tj', 'extensions', 'pg_temp'
AS $function$
declare v_product tj.aiq_products%rowtype; v_package tj.speciq_packages%rowtype; v_comparison tj.ai_product_comparisons%rowtype; v_id uuid;
begin
  select * into v_package from tj.speciq_packages where id=p_package_id FOR UPDATE;
  if not found then raise exception 'Package not found'; end if;
  PERFORM tj_private.assert_runtime_org(v_package.organization_id);
  IF NOT tj_private.speciq_package_store_allows(v_package.organization_id,v_package.id) THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501';END IF;
  IF v_package.deleted_at IS NOT NULL OR coalesce(v_package.locked,false) OR v_package.approval_status='approved' THEN RAISE EXCEPTION 'package_not_editable' USING ERRCODE='42501'; END IF;
  IF NOT tj.is_org_admin(v_package.organization_id) AND v_package.created_by IS DISTINCT FROM tj_private.current_source_user_id() THEN RAISE EXCEPTION 'package_owner_required' USING ERRCODE='42501'; END IF;
  select * into v_comparison from tj.ai_product_comparisons where id=p_comparison_id and organization_id=v_package.organization_id;
  IF NOT tj.is_org_admin(v_package.organization_id) AND v_comparison.user_id IS DISTINCT FROM tj_private.current_source_user_id() THEN RAISE EXCEPTION 'comparison_owner_required' USING ERRCODE='42501'; END IF;
  if not found or v_comparison.winner_product_id is null then raise exception 'Comparison winner not available'; end if;
  select * into v_product from tj.aiq_products where id=v_comparison.winner_product_id and organization_id=v_package.organization_id;
  if not found then raise exception 'Winner product not found'; end if;
  SELECT id INTO v_id FROM tj.speciq_package_products WHERE package_id=p_package_id AND organization_id=v_package.organization_id AND source_comparison_id=p_comparison_id AND aiq_product_id=v_product.id LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  insert into tj.speciq_package_products(package_id,organization_id,product_name,brand,model_number,category,finish,width_inches,height_inches,depth_inches,weight_lbs,installation_type,msrp,promo_price,aiq_product_id,brand_id,series,product_line,short_description,spec_snapshot,source_comparison_id,selection_reason)
  values(v_package.id,v_package.organization_id,concat_ws(' ',v_product.brand_name,v_product.model),v_product.brand_name,v_product.model,v_product.category,v_product.finish,v_product.width_inches,v_product.height_inches,v_product.depth_inches,v_product.weight_lbs,v_product.installation_type,v_product.msrp,coalesce(v_product.sale_price,v_product.lowest_price),v_product.id,v_product.brand_id,v_product.series,v_product.product_line,v_product.short_description,coalesce(v_product.specs_json,'{}'::jsonb),v_comparison.id,coalesce(v_comparison.comparison_snapshot->>'winner_reason','Selected as comparison winner')) returning id into v_id;
  insert into tj.speciq_package_events(package_id,event_type,event_data)
  values(v_package.id,'comparison_winner_added',jsonb_build_object('comparison_id',v_comparison.id,'product_id',v_product.id,'package_product_id',v_id));
  UPDATE tj.speciq_packages SET updated_at=now(),updated_by=tj_private.current_source_user_id() WHERE id=p_package_id;
  return v_id;
end; $function$
;

CREATE OR REPLACE FUNCTION tj_private.speciq_drafts(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 IF NOT tj_private.speciq_package_store_allows(org,replay.package_id) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable');END IF;
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
 RETURN jsonb_build_object('ok',true,'package_id',replay.package_id,'replayed',true,'pricing_state','draft_tax_unreviewed'); END IF;
 old_id:=nullif(p_body->>'previous_package_id','')::uuid;
 IF old_id IS NOT NULL THEN
 SELECT * INTO prior FROM tj.speciq_packages WHERE id=old_id AND organization_id=org FOR UPDATE;
 IF NOT FOUND OR NOT tj_private.speciq_package_store_allows(org,prior.id) OR (prior.created_by IS DISTINCT FROM actor AND role_name NOT IN('owner','admin','manager')) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable'); END IF;
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
$function$
;

CREATE OR REPLACE FUNCTION tj_private.speciq_projects(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE n uuid:=auth.uid();actor uuid;org uuid;v_role text;a text;req uuid;proj uuid;
 row_before tj.speciq_projects%ROWTYPE;row_after tj.speciq_projects%ROWTYPE;
 replay tj_private.speciq_project_requests%ROWTYPE;d jsonb;k text;v text;purchase date;delivery date;
BEGIN
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 org:=(p_body->>'organization_id')::uuid;a:=p_body->>'action';v_role:=tj_private.speciq_actor_role(org);actor:=tj_private.microsoft_actor(n);
 IF v_role IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required');END IF;
 IF a='list' THEN
 RETURN jsonb_build_object('ok',true,'projects',coalesce((SELECT jsonb_agg(to_jsonb(r)) FROM (
 SELECT p.*,tj_private.speciq_project_native(p.id) AND p.status<>'archived' AND (p.created_by=actor OR v_role IN('owner','admin','manager')) AND NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=p.id) AND v_role<>'viewer' can_edit,
 tj_private.speciq_project_native(p.id) AND p.status<>'archived' AND (p.created_by=actor OR v_role IN('owner','admin','manager')) AND NOT EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=p.id AND status<>'archived') AND v_role<>'viewer' can_archive
 FROM tj.speciq_projects p WHERE p.organization_id=org AND p.deleted_at IS NULL AND tj_private.speciq_project_store_allows(org,p.id) ORDER BY p.created_at DESC,p.id LIMIT 200) r),'[]'::jsonb));END IF;
 IF v_role NOT IN('owner','admin','manager','member') THEN RETURN jsonb_build_object('ok',false,'error','organization_write_required');END IF;
 IF a IS NULL OR a NOT IN('create','update','archive') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 req:=(p_body->>'request_id')::uuid;IF req IS NULL OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) AS keys(key_name) WHERE key_name NOT IN('action','organization_id','request_id','project_id','expected_updated_at','project')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||n::text||req::text,0));
 SELECT * INTO replay FROM tj_private.speciq_project_requests WHERE organization_id=org AND native_actor=n AND request_id=req;
 IF FOUND THEN
 IF NOT tj_private.speciq_project_store_allows(org,replay.project_id) THEN RETURN jsonb_build_object('ok',false,'error','project_unavailable');END IF;
 IF replay.body<>p_body THEN RETURN jsonb_build_object('ok',false,'error','request_conflict');END IF;
 RETURN jsonb_build_object('ok',true,'project_id',replay.project_id,'replayed',true);END IF;
 IF a<>'create' THEN
 proj:=(p_body->>'project_id')::uuid;
 SELECT * INTO row_before FROM tj.speciq_projects WHERE id=proj AND organization_id=org AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR NOT tj_private.speciq_project_store_allows(org,proj) OR (row_before.created_by IS DISTINCT FROM actor AND v_role NOT IN('owner','admin','manager')) THEN RETURN jsonb_build_object('ok',false,'error','project_unavailable');END IF;
 IF NOT tj_private.speciq_project_native(proj) THEN RETURN jsonb_build_object('ok',false,'error','historical_project_read_only');END IF;
 IF row_before.status='archived' THEN RETURN jsonb_build_object('ok',false,'error','project_archived');END IF;
 IF (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM row_before.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict');END IF;
 IF a='update' AND EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=proj) THEN RETURN jsonb_build_object('ok',false,'error','package_revision_required');END IF;
 IF a='archive' AND EXISTS(SELECT 1 FROM tj.speciq_packages WHERE project_id=proj AND status<>'archived') THEN RETURN jsonb_build_object('ok',false,'error','archive_packages_first');END IF;
 END IF;
 IF a IN('create','update') THEN
 d:=p_body->'project';IF jsonb_typeof(d) IS DISTINCT FROM 'object' THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(d) AS keys(key_name) WHERE key_name NOT IN('project_name','customer_name','customer_email','customer_phone','property_address','room_name','builder_name','designer_name','expected_purchase_date','delivery_date','notes')) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 FOR k,v IN SELECT key,value #>> '{}' FROM jsonb_each(d) LOOP
 IF jsonb_typeof(d->k) NOT IN('string','null') OR length(coalesce(v,''))>(CASE k WHEN 'notes' THEN 4000 WHEN 'property_address' THEN 1000 WHEN 'customer_email' THEN 254 WHEN 'customer_phone' THEN 50 WHEN 'room_name' THEN 100 WHEN 'expected_purchase_date' THEN 10 WHEN 'delivery_date' THEN 10 ELSE 200 END) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 IF length(btrim(coalesce(d->>'project_name',''))) NOT BETWEEN 1 AND 200 OR length(btrim(coalesce(d->>'customer_name',''))) NOT BETWEEN 1 AND 200 OR (coalesce(d->>'customer_email','')<>'' AND d->>'customer_email' !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 FOREACH k IN ARRAY ARRAY['expected_purchase_date','delivery_date'] LOOP
 v:=nullif(d->>k,'');IF v IS NOT NULL AND (v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' OR v::date::text<>v) THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023';END IF;
 END LOOP;
 purchase:=nullif(d->>'expected_purchase_date','')::date;delivery:=nullif(d->>'delivery_date','')::date;
 IF a='create' THEN
 INSERT INTO tj.speciq_projects(organization_id,created_by,project_name,customer_name) VALUES(org,actor,btrim(d->>'project_name'),btrim(d->>'customer_name')) RETURNING id INTO proj;
 END IF;
 UPDATE tj.speciq_projects SET project_name=btrim(d->>'project_name'),customer_name=btrim(d->>'customer_name'),customer_email=nullif(d->>'customer_email',''),customer_phone=nullif(d->>'customer_phone',''),property_address=nullif(d->>'property_address',''),room_name=nullif(d->>'room_name',''),builder_name=nullif(d->>'builder_name',''),designer_name=nullif(d->>'designer_name',''),expected_purchase_date=purchase,delivery_date=delivery,notes=nullif(d->>'notes',''),updated_at=clock_timestamp() WHERE id=proj RETURNING * INTO row_after;
 ELSE
 UPDATE tj.speciq_projects SET status='archived',updated_at=clock_timestamp() WHERE id=proj RETURNING * INTO row_after;
 END IF;
 INSERT INTO tj_private.speciq_project_requests(organization_id,native_actor,source_actor,request_id,project_id,body,before_image,after_image) VALUES(org,n,actor,req,proj,p_body,CASE WHEN a='create' THEN NULL ELSE to_jsonb(row_before) END,to_jsonb(row_after));
 RETURN jsonb_build_object('ok',true,'project_id',proj,'replayed',false);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR datetime_field_overflow OR invalid_datetime_format OR not_null_violation OR check_violation THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$function$
;

CREATE OR REPLACE FUNCTION tj_private.speciq_workflow(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE native uuid:=auth.uid(); actor uuid; org uuid; role_name text; manager boolean; a text; req uuid;
 pkg tj.speciq_packages%ROWTYPE; replay tj_private.speciq_draft_requests%ROWTYPE;
 decision text; v_comments text; v_conditions text; before_state jsonb; history_id uuid;
BEGIN
 actor:=tj_private.microsoft_actor(native);
 IF native IS NULL OR actor IS NULL THEN RETURN jsonb_build_object('ok',false,'error','identity_review_required'); END IF;
 IF NOT EXISTS(SELECT 1 FROM auth.users WHERE id=native AND email_confirmed_at IS NOT NULL) THEN RETURN jsonb_build_object('ok',false,'error','email_confirmation_required'); END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>16384 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 a:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;role_name:=tj_private.speciq_actor_role(org);
 IF role_name IS NULL THEN RETURN jsonb_build_object('ok',false,'error','organization_access_required'); END IF;
 manager:=role_name IN('owner','admin','manager');
 IF a='list' THEN
 RETURN jsonb_build_object('ok',true,'packages',coalesce((SELECT jsonb_agg(to_jsonb(r) ORDER BY r.created_at DESC) FROM
 (SELECT k.*,to_jsonb(p) AS speciq_projects FROM tj.speciq_packages k JOIN tj.speciq_projects p ON p.id=k.project_id AND p.organization_id=org
 WHERE k.organization_id=org AND tj_private.speciq_package_store_allows(org,k.id) AND k.deleted_at IS NULL AND k.superseded_by IS NULL AND k.status<>'archived'
 AND (manager OR k.created_by=actor) AND EXISTS(SELECT 1 FROM tj_private.speciq_draft_requests d WHERE d.package_id=k.id)
 ORDER BY k.created_at DESC,k.id LIMIT 200) r),'[]'::jsonb)); END IF;
 IF a IS NULL OR a NOT IN('get','submit','decide','archive') THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 IF a<>'get' THEN
 req:=(p_body->>'request_id')::uuid;
 IF req IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(org::text||native::text||req::text,0));
 END IF;
 SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org FOR UPDATE;
 IF NOT FOUND OR NOT tj_private.speciq_package_store_allows(org,pkg.id) OR NOT EXISTS(SELECT 1 FROM tj_private.speciq_draft_requests d WHERE d.package_id=pkg.id)
 OR (pkg.created_by IS DISTINCT FROM actor AND NOT manager) THEN RETURN jsonb_build_object('ok',false,'error','package_unavailable'); END IF;
 IF a='get' THEN
 RETURN jsonb_build_object('ok',true,'package',to_jsonb(pkg),'snapshot',(SELECT snapshot FROM tj.speciq_package_versions WHERE package_id=pkg.id ORDER BY version_number DESC,created_at DESC LIMIT 1),
 'history',coalesce((SELECT jsonb_agg(to_jsonb(h) ORDER BY h.created_at,h.id) FROM tj.speciq_approval_history h WHERE h.package_id=pkg.id AND h.organization_id=org),'[]'::jsonb),
 'can_decide',manager AND actor IS DISTINCT FROM pkg.created_by AND actor IS DISTINCT FROM pkg.submitted_by,
 'can_submit',role_name<>'viewer' AND pkg.status='draft' AND NOT coalesce(pkg.locked,false),'can_archive',role_name<>'viewer'); END IF;
 IF role_name NOT IN('owner','admin','manager','member') THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
 IF a='decide' AND (NOT manager OR actor IS NOT DISTINCT FROM pkg.created_by OR actor IS NOT DISTINCT FROM pkg.submitted_by) THEN RETURN jsonb_build_object('ok',false,'error','independent_manager_required'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','package_id','request_id','expected_version','expected_updated_at','decision','comments','conditions')) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 req:=(p_body->>'request_id')::uuid;
 IF req IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 SELECT * INTO replay FROM tj_private.speciq_draft_requests WHERE organization_id=org AND native_actor=native AND request_id=req;
 IF FOUND THEN
 IF replay.body<>p_body OR replay.package_id<>pkg.id THEN RETURN jsonb_build_object('ok',false,'error','request_conflict'); END IF;
 RETURN jsonb_build_object('ok',true,'package_id',pkg.id,'replayed',true); END IF;
 IF pkg.deleted_at IS NOT NULL OR pkg.superseded_by IS NOT NULL OR pkg.status='archived' OR pkg.sent_at IS NOT NULL OR pkg.shopify_pushed_at IS NOT NULL OR pkg.share_token IS NOT NULL THEN RETURN jsonb_build_object('ok',false,'error','package_not_editable'); END IF;
 IF (p_body->>'expected_version')::integer IS DISTINCT FROM pkg.version OR (p_body->>'expected_updated_at')::timestamptz IS DISTINCT FROM pkg.updated_at THEN RETURN jsonb_build_object('ok',false,'error','revision_conflict'); END IF;
 v_comments:=nullif(btrim(p_body->>'comments'),'');v_conditions:=nullif(btrim(p_body->>'conditions'),'');decision:=p_body->>'decision';
 IF length(coalesce(v_comments,''))>2000 OR length(coalesce(v_conditions,''))>2000 THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 before_state:=jsonb_build_object('status',pkg.status,'approval_status',pkg.approval_status,'locked',pkg.locked);
 IF a='submit' THEN
 IF pkg.status<>'draft' OR coalesce(pkg.locked,false) OR coalesce(pkg.approval_status,'unknown') NOT IN('not_required','returned') OR NOT EXISTS(SELECT 1 FROM tj.speciq_package_versions v WHERE v.package_id=pkg.id AND v.version_number=pkg.version) THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 UPDATE tj.speciq_packages SET status='ready_for_review',approval_status='pending',approval_required=true,submitted_by=actor,submitted_at=clock_timestamp(),updated_by=actor,updated_at=clock_timestamp(),manager_comments=NULL,approval_conditions=NULL,reviewed_by=NULL,reviewed_at=NULL,approved_at=NULL,approved_by=NULL WHERE id=pkg.id;
 INSERT INTO tj.speciq_approval_history(package_id,organization_id,submission_id,quote_version,submitted_by,approval_trigger,requested_discount,requested_validity_days)
 VALUES(pkg.id,org,req::text,pkg.version,actor,'native_draft_review',NULL,NULL);
 ELSIF a='decide' THEN
 IF pkg.status<>'ready_for_review' OR pkg.approval_status IS DISTINCT FROM 'pending' THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 IF decision IS NULL OR decision NOT IN('approved','approved_with_conditions','returned','rejected') OR (decision IN('returned','rejected') AND v_comments IS NULL) OR (decision='approved_with_conditions' AND v_conditions IS NULL) THEN RETURN jsonb_build_object('ok',false,'error','invalid_request'); END IF;
 SELECT id INTO history_id FROM tj.speciq_approval_history WHERE package_id=pkg.id AND organization_id=org AND manager_decision IS NULL AND quote_version=pkg.version ORDER BY created_at DESC,id DESC LIMIT 1 FOR UPDATE;
 IF history_id IS NULL THEN RETURN jsonb_build_object('ok',false,'error','invalid_transition'); END IF;
 UPDATE tj.speciq_packages SET approval_status=decision,status=CASE WHEN decision='returned' THEN 'draft' ELSE 'in_progress' END,locked=decision<>'returned',
 reviewed_by=actor,reviewed_at=clock_timestamp(),manager_comments=v_comments,approval_conditions=v_conditions,
 approved_by=CASE WHEN decision IN('approved','approved_with_conditions') THEN actor ELSE NULL END,approved_at=CASE WHEN decision IN('approved','approved_with_conditions') THEN clock_timestamp() ELSE NULL END,
 returned_to_rep_at=CASE WHEN decision='returned' THEN clock_timestamp() ELSE NULL END,rejection_reason=CASE WHEN decision='rejected' THEN v_comments ELSE NULL END,updated_by=actor,updated_at=clock_timestamp() WHERE id=pkg.id;
 UPDATE tj.speciq_approval_history SET manager_decision=decision,assigned_manager=actor,conditions=v_conditions,comments=v_comments,decision_at=clock_timestamp(),returned_to_rep_at=CASE WHEN decision='returned' THEN clock_timestamp() ELSE NULL END WHERE id=history_id;
 ELSE
 IF pkg.status NOT IN('draft','in_progress','ready_for_review') OR (coalesce(pkg.locked,false) AND NOT manager) THEN RETURN jsonb_build_object('ok',false,'error','forbidden'); END IF;
 UPDATE tj.speciq_packages SET status='archived',locked=true,approval_status=CASE WHEN approval_status='pending' THEN 'withdrawn' ELSE approval_status END,updated_by=actor,updated_at=clock_timestamp() WHERE id=pkg.id;
 UPDATE tj.speciq_approval_history SET manager_decision='withdrawn',comments=coalesce(v_comments,'Package archived'),decision_at=clock_timestamp(),assigned_manager=actor WHERE package_id=pkg.id AND organization_id=org AND manager_decision IS NULL;
 END IF;
 INSERT INTO tj.speciq_package_events(package_id,event_type,event_data) VALUES(pkg.id,CASE WHEN a='decide' AND decision='returned' THEN 'revision_requested' ELSE 'created' END,jsonb_build_object('workflow_action',a,'decision',decision,'source_actor',actor,'request_id',req,'before',before_state,'after',(SELECT jsonb_build_object('status',k.status,'approval_status',k.approval_status,'locked',k.locked) FROM tj.speciq_packages k WHERE k.id=pkg.id),'scope','draft_content_review; final tax and sending pending'));
 INSERT INTO tj_private.speciq_draft_requests(organization_id,native_actor,request_id,body,package_id) VALUES(org,native,req,p_body,pkg.id);
 RETURN jsonb_build_object('ok',true,'package_id',pkg.id,'replayed',false);
EXCEPTION WHEN invalid_text_representation OR invalid_parameter_value OR check_violation OR not_null_violation OR foreign_key_violation OR numeric_value_out_of_range OR datetime_field_overflow THEN RETURN jsonb_build_object('ok',false,'error','invalid_request');
END;
$function$
;

CREATE OR REPLACE FUNCTION tj_private.shopify_draft_order(p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid;org uuid;pkg tj.speciq_packages%rowtype;operation text;lines jsonb;subtotal numeric;bad integer;line_count integer;
BEGIN
  actor:=tj_private.microsoft_actor(auth.uid());
  IF actor IS NULL THEN RAISE EXCEPTION 'verified_identity_required' USING ERRCODE='42501'; END IF;
  IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>8192 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('package_id','organization_id','action')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  org:=(p_body->>'organization_id')::uuid;operation:=coalesce(p_body->>'action','create');
  IF operation NOT IN('preview','status','create') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
  IF org IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org AND deleted_at IS NULL;
  IF NOT FOUND OR NOT tj_private.speciq_package_store_allows(org,pkg.id) THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) OR EXISTS(SELECT 1 FROM tj.speciq_package_services WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) THEN RAISE EXCEPTION 'inconsistent_child_organization' USING ERRCODE='42501'; END IF;
  IF operation<>'preview' THEN
    RETURN jsonb_build_object('ok',operation='status','executed',false,'draft_created',false,'package_id',pkg.id,'organization_id',org,'create_ready',false,'blockers',jsonb_build_array('fresh_verified_shopify_connection_and_write_draft_orders_scope_required','verified_shop_currency_and_discount_tax_contract_required','connection_scoped_variant_customer_mapping_required','atomic_claim_and_uncertain_provider_result_reconciliation_required'));
  END IF;
  WITH product_rows AS (
    SELECT id,'product'::text kind,btrim(concat_ws(' ',nullif(btrim(brand),''),nullif(btrim(model_number),''),nullif(btrim(product_name),''))) title,coalesce(quantity,1) quantity,
      coalesce(negotiated_price,promo_price,msrp) price,
      CASE WHEN negotiated_price IS NOT NULL THEN 'negotiated_price' WHEN promo_price IS NOT NULL THEN 'promo_price' ELSE 'msrp' END price_basis,sort_order
    FROM tj.speciq_package_products WHERE package_id=pkg.id ORDER BY sort_order NULLS LAST,id LIMIT 101
  ), service_rows AS (
    SELECT id,'service'::text kind,coalesce(nullif(btrim(description),''),nullif(btrim(service_type),'')) title,1 quantity,amount price,'amount'::text price_basis,sort_order
    FROM tj.speciq_package_services WHERE package_id=pkg.id ORDER BY sort_order NULLS LAST,id LIMIT 101
  ), all_rows AS (SELECT * FROM product_rows UNION ALL SELECT * FROM service_rows)
  SELECT count(*),count(*) FILTER(WHERE title IS NULL OR length(title) NOT BETWEEN 1 AND 250 OR quantity NOT BETWEEN 1 AND 1000 OR price IS NULL OR price<0 OR price>10000000 OR scale(price)>2),
    coalesce(sum(price*quantity),0),coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'quantity',quantity,'unit_price',price::text,'extended_price',(price*quantity)::text,'price_basis',price_basis) ORDER BY kind,sort_order NULLS LAST,id),'[]'::jsonb)
    INTO line_count,bad,subtotal,lines FROM all_rows;
  IF line_count NOT BETWEEN 1 AND 100 OR bad<>0 THEN RAISE EXCEPTION 'invalid_quote_lines' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id) THEN RAISE EXCEPTION 'package_has_no_products' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('ok',true,'operation','preview','executed',false,'draft_created',false,'create_ready',false,'package_id',pkg.id,'organization_id',org,'package_version',pkg.version,'package_updated_at',pkg.updated_at,'lines',lines,'line_subtotal',subtotal::text,'currency',NULL,'recorded_volume_discount',pkg.volume_discount::text,'discount_applied',false,'tax_applied',false,'quote_hash',md5(jsonb_build_object('package_id',pkg.id,'lines',lines,'volume_discount',pkg.volume_discount,'tax_rule_id',pkg.tax_rule_id,'updated_at',pkg.updated_at)::text),'blockers',jsonb_build_array('fresh_verified_shopify_connection_and_write_draft_orders_scope_required','verified_shop_currency_and_discount_tax_contract_required','connection_scoped_variant_customer_mapping_required','atomic_claim_and_uncertain_provider_result_reconciliation_required'));
END $function$
;

CREATE OR REPLACE FUNCTION tj_private.shopify_draft_attempt(p_native uuid, p_body jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE actor uuid;operation text;org uuid;pkg tj.speciq_packages%rowtype;c tj.platform_connector_connections%rowtype;a tj_private.shopify_draft_attempts%rowtype;previous text;hash text;
BEGIN
 IF current_setting('role',true) IS DISTINCT FROM 'service_role' THEN RAISE EXCEPTION 'service_required' USING ERRCODE='42501'; END IF;
 actor:=tj_private.microsoft_actor(p_native);IF actor IS NULL THEN RAISE EXCEPTION 'verified_identity_required' USING ERRCODE='42501';END IF;
 IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>4096 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('action','organization_id','package_id','connection_id','request_id','payload_hash','attempt_id','fence','draft_id','response_hash')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
 operation:=p_body->>'action';org:=(p_body->>'organization_id')::uuid;
 IF operation IS NULL OR operation NOT IN('prepare','status','start','uncertain','reject','confirm','cancel') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
 IF org IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.user_id=actor AND m.organization_id=org AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
 -- Lock order is package -> attempt everywhere, serializing all request keys for one package.
 SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org AND deleted_at IS NULL FOR UPDATE;
 IF NOT FOUND OR EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) OR EXISTS(SELECT 1 FROM tj.speciq_package_services WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501'; END IF;
 IF operation IN('prepare','start','status') AND NOT tj_private.speciq_package_store_allows_as(org,pkg.id,actor) THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501';END IF;
 SELECT * INTO c FROM tj.platform_connector_connections WHERE id=(p_body->>'connection_id')::uuid AND organization_id=org;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM tj.platform_connectors pc WHERE pc.id=c.connector_id AND pc.key='shopify') THEN RAISE EXCEPTION 'connection_access_denied' USING ERRCODE='42501';END IF;
 IF operation='prepare' THEN
   IF coalesce(p_body->>'payload_hash','')!~'^[0-9a-f]{64}$' OR p_body->>'request_id' IS NULL THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023';END IF;
   hash:=tj_private.shopify_draft_source_hash(pkg.id);
   SELECT * INTO a FROM tj_private.shopify_draft_attempts WHERE native_user=p_native AND request_id=(p_body->>'request_id')::uuid FOR UPDATE;
   IF FOUND THEN
     IF a.package_id<>pkg.id OR a.connection_id<>c.id OR a.organization_id<>org OR a.payload_hash<>p_body->>'payload_hash' THEN RAISE EXCEPTION 'request_key_conflict' USING ERRCODE='40001';END IF;
   ELSE
     IF pkg.shopify_draft_order_id IS NOT NULL OR EXISTS(SELECT 1 FROM tj_private.shopify_draft_attempts WHERE package_id=pkg.id AND state NOT IN('rejected','cancelled')) THEN RAISE EXCEPTION 'package_claimed_or_existing_draft' USING ERRCODE='40001';END IF;
     INSERT INTO tj_private.shopify_draft_attempts(organization_id,package_id,connection_id,native_user,request_id,payload_hash,source_hash) VALUES(org,pkg.id,c.id,p_native,(p_body->>'request_id')::uuid,p_body->>'payload_hash',hash) RETURNING * INTO a;
     INSERT INTO tj_private.shopify_draft_events(organization_id,attempt_id,native_user,next_state) VALUES(org,a.id,p_native,'prepared');
   END IF;
 ELSE
   SELECT * INTO a FROM tj_private.shopify_draft_attempts WHERE id=(p_body->>'attempt_id')::uuid AND organization_id=org AND package_id=pkg.id AND connection_id=c.id AND native_user=p_native FOR UPDATE;
   IF NOT FOUND THEN RAISE EXCEPTION 'attempt_access_denied' USING ERRCODE='42501';END IF;
   IF operation<>'status' THEN
     IF a.fence IS DISTINCT FROM (p_body->>'fence')::uuid THEN RAISE EXCEPTION 'stale_worker' USING ERRCODE='40001';END IF;
     previous:=a.state;
     IF operation='start' THEN
       IF a.state<>'prepared' OR a.expires_at<=clock_timestamp() OR a.source_hash IS DISTINCT FROM tj_private.shopify_draft_source_hash(pkg.id) OR c.status IN('paused','disconnected') OR pkg.shopify_draft_order_id IS NOT NULL THEN RAISE EXCEPTION 'dispatch_not_allowed' USING ERRCODE='40001';END IF;
       a.state:='dispatched';
     ELSIF operation='cancel' THEN
       IF a.state<>'prepared' THEN RAISE EXCEPTION 'cannot_cancel_dispatched_attempt' USING ERRCODE='40001';END IF;a.state:='cancelled';
     ELSIF operation='uncertain' THEN
       IF a.state NOT IN('dispatched','unknown') THEN RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;a.state:='unknown';
     ELSE
       IF coalesce(p_body->>'response_hash','')!~'^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'verified_response_hash_required' USING ERRCODE='22023';END IF;
       IF operation='reject' THEN
         -- Unknown cannot be released based on a retry error: the first request may have succeeded.
         IF a.state<>'dispatched' OR p_body->>'draft_id' IS NOT NULL THEN RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;a.state:='rejected';
       ELSE
         IF coalesce(p_body->>'draft_id','')!~'^gid://shopify/DraftOrder/[1-9][0-9]{0,24}$' THEN RAISE EXCEPTION 'invalid_draft_id' USING ERRCODE='22023';END IF;
         IF a.state='succeeded' THEN
           IF a.provider_draft_id<>p_body->>'draft_id' OR a.response_hash<>p_body->>'response_hash' THEN RAISE EXCEPTION 'completion_conflict' USING ERRCODE='40001';END IF;
         ELSIF a.state IN('dispatched','unknown') THEN a.state:='succeeded';a.provider_draft_id:=p_body->>'draft_id';
         ELSE RAISE EXCEPTION 'invalid_transition' USING ERRCODE='40001';END IF;
       END IF;
       a.response_hash:=p_body->>'response_hash';
     END IF;
     IF previous<>a.state THEN
       UPDATE tj_private.shopify_draft_attempts SET state=a.state,provider_draft_id=a.provider_draft_id,response_hash=a.response_hash,updated_at=clock_timestamp() WHERE id=a.id;
       INSERT INTO tj_private.shopify_draft_events(organization_id,attempt_id,native_user,previous_state,next_state,response_hash) VALUES(org,a.id,p_native,previous,a.state,a.response_hash);
     END IF;
   END IF;
 END IF;
 RETURN jsonb_build_object('ok',true,'attempt_id',a.id,'fence',a.fence,'state',a.state,'provider_draft_id',a.provider_draft_id,'provider_execution_enabled',false);
END $function$
;

NOTIFY pgrst,'reload schema';
