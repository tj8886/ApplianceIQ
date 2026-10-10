CREATE OR REPLACE FUNCTION tj_private.pim_web_fill_json(existing jsonb,incoming jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE result jsonb:=CASE WHEN tj_private.pim_web_blank(existing) THEN '{}'::jsonb ELSE existing END; k text; v jsonb; actual_key text;
BEGIN
 IF jsonb_typeof(incoming) IS DISTINCT FROM 'object' THEN RETURN result; END IF;
 IF jsonb_typeof(result) IS DISTINCT FROM 'object' THEN RETURN result; END IF;
 FOR k,v IN SELECT * FROM jsonb_each(incoming) LOOP
  IF tj_private.pim_web_blank(v) OR length(v::text)>16000 OR
    tj_private.pim_web_key(k) ~ '(dealercost|wholesale|margin|organization|token|secret|apikey|password|internal|price|cost)' THEN CONTINUE; END IF;
  SELECT e.key INTO actual_key FROM jsonb_each(result) e
   WHERE tj_private.pim_web_spec_key(e.key)=tj_private.pim_web_spec_key(k)
   ORDER BY (e.key=k) DESC,e.key LIMIT 1;
  IF actual_key IS NULL THEN result:=result||jsonb_build_object(k,v);
  ELSIF tj_private.pim_web_blank(result->actual_key) THEN result:=result||jsonb_build_object(actual_key,v);
  ELSIF jsonb_typeof(result->actual_key)='object' AND jsonb_typeof(v)='object' THEN
   result:=result||jsonb_build_object(actual_key,tj_private.pim_web_fill_json(result->actual_key,v));
  END IF;
 END LOOP;
 RETURN result;
END $$;

-- Correct additive JSON measurement conflicts discovered in the first 100-product backfill.
-- Existing populated facts were retained. Restore only worker-written specs/dimensions
-- if still byte-identical to the logged after image, then requeue for the corrected writer.
CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_product(source_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t tj.aiq_products; p public.products; before_p public.products;
 category text; canonical_brand uuid; model_key text; n integer; candidate uuid;
 src_date timestamptz; new_record boolean:=false; description text; url text;
 spec_url text; merged jsonb; dims jsonb; image_candidates integer; action text;
 price_snapshot jsonb; image_urls jsonb; identity_row record; result jsonb;
BEGIN
 SELECT * INTO t FROM tj.aiq_products WHERE id=source_id;
 IF NOT FOUND OR NOT tj_private.pim_web_appliance(t) THEN RETURN jsonb_build_object('action','excluded'); END IF;
 canonical_brand:=public.brand_resolve(t.brand_name); model_key:=tj_private.pim_web_key(t.model);
 category:=tj_private.pim_web_category(t.category);
 PERFORM pg_advisory_xact_lock(hashtextextended('pim-web:'||model_key,0));
 SELECT * INTO identity_row FROM public.pim_identity_current ic WHERE ic.source_id=t.id;
 IF FOUND AND identity_row.decision<>'approved' THEN RETURN jsonb_build_object('action','identity_review'); END IF;
 SELECT count(*),(array_agg(id))[1] INTO n,candidate FROM public.products
 WHERE tj_private.pim_web_key(model_number)=model_key
 AND coalesce(brand_canonical_id,public.brand_resolve(brand_name))=canonical_brand
 AND (market IS NULL OR t.market IS NULL OR market=t.market);
 IF n>1 THEN RETURN jsonb_build_object('action','ambiguous'); END IF;
 IF n=0 AND EXISTS(SELECT 1 FROM public.products WHERE tj_private.pim_web_key(model_number)=model_key
  OR normalized_model_number=upper(model_key)) THEN RETURN jsonb_build_object('action','brand_or_market_collision'); END IF;
 IF identity_row.target_product_id IS NOT NULL AND identity_row.target_product_id IS DISTINCT FROM candidate THEN
  RETURN jsonb_build_object('action','identity_collision'); END IF;
 -- Newest eligible source for this exact brand/model/market wins; older copies do not fill conflicting blanks.
 SELECT s.* INTO t FROM tj.aiq_products s WHERE tj_private.pim_web_key(s.model)=model_key
 AND public.brand_resolve(s.brand_name)=canonical_brand AND tj_private.pim_web_appliance(s)
 AND (s.market IS NOT DISTINCT FROM t.market)
 ORDER BY greatest(s.updated_at,s.created_at,s.source_extracted_at) DESC,s.id LIMIT 1;
 src_date:=greatest(t.updated_at,t.created_at,t.source_extracted_at);
 IF n=0 THEN
  INSERT INTO public.products(slug,brand_name,brand_canonical_id,model_number,normalized_model_number,
   product_name,category,status,match_status,data_status,market,country,source_metadata)
  VALUES(lower(regexp_replace(t.brand_name||'-'||t.model||'-'||public.tj_admission_category_noun(category),'[^a-zA-Z0-9]+','-','g')),
   t.brand_name,canonical_brand,t.model,upper(model_key),
   t.brand_name||' '||t.model||' '||replace(public.tj_admission_category_noun(category),'-',' '),
   category,'active','auto_matched','unverified',t.market,t.market,
   jsonb_build_object('importType','approved_admin_import','pim_source_id',t.id,'pim_source_updated_at',src_date,
    'pim_completion_mode','fill_blanks_only','sourceType','approved_admin_import')) RETURNING * INTO p;
  IF p.id IS NULL THEN RETURN jsonb_build_object('action','admission_refused'); END IF;
  candidate:=p.id; new_record:=true;
 ELSE
  SELECT * INTO p FROM public.products WHERE id=candidate FOR UPDATE;
  IF p.status IN ('hidden','archived') THEN RETURN jsonb_build_object('action','website_withdrawn'); END IF;
  IF p.category IS DISTINCT FROM category THEN RETURN jsonb_build_object('action','category_collision'); END IF;
 END IF;
 before_p:=p;
 description:=nullif(btrim(regexp_replace(coalesce(nullif(t.long_description,''),t.short_description),'<[^>]*>','','g')),'');
 IF length(description)<20 OR length(description)>16000 THEN description:=NULL; END IF;
 IF nullif(btrim(p.description),'') IS NULL AND description IS NOT NULL THEN p.description:=description; END IF;
 SELECT coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) INTO merged
 FROM jsonb_each(CASE WHEN jsonb_typeof(t.specs_json)='object' THEN t.specs_json ELSE '{}'::jsonb END) e
 WHERE NOT (
 (tj_private.pim_web_spec_key(e.key)='width' AND (p.facet_width_in IS NOT NULL OR EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.dimensions)='object' THEN p.dimensions ELSE '{}'::jsonb END) d WHERE tj_private.pim_web_spec_key(d.key)='width' AND NOT tj_private.pim_web_blank(d.value)))) OR
 (tj_private.pim_web_spec_key(e.key)='height' AND (p.facet_height_in IS NOT NULL OR EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.dimensions)='object' THEN p.dimensions ELSE '{}'::jsonb END) d WHERE tj_private.pim_web_spec_key(d.key)='height' AND NOT tj_private.pim_web_blank(d.value)))) OR
 (tj_private.pim_web_spec_key(e.key)='depth' AND (p.facet_depth_in IS NOT NULL OR EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.dimensions)='object' THEN p.dimensions ELSE '{}'::jsonb END) d WHERE tj_private.pim_web_spec_key(d.key)='depth' AND NOT tj_private.pim_web_blank(d.value)))) OR
 (tj_private.pim_web_spec_key(e.key)='capacity' AND p.facet_capacity_cuft IS NOT NULL) OR
 (tj_private.pim_web_spec_key(e.key)='finish' AND (nullif(btrim(p.finish),'') IS NOT NULL OR nullif(btrim(p.facet_finish),'') IS NOT NULL)) OR
 (tj_private.pim_web_spec_key(e.key)='fuel' AND p.facet_fuel IS NOT NULL));
 p.specs:=tj_private.pim_web_fill_json(p.specs,merged);
 -- Explicit typed measurements only, retaining any existing scalar or equivalent JSON value.
 dims:=tj_private.pim_web_fill_json(p.dimensions,jsonb_strip_nulls(jsonb_build_object(
  'width_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END) e WHERE tj_private.pim_web_spec_key(e.key)='width' AND NOT tj_private.pim_web_blank(e.value)) AND before_p.facet_width_in IS NULL AND t.width_inches BETWEEN 1 AND 100 THEN t.width_inches END,
  'height_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END) e WHERE tj_private.pim_web_spec_key(e.key)='height' AND NOT tj_private.pim_web_blank(e.value)) AND before_p.facet_height_in IS NULL AND t.height_inches>0 AND t.height_inches<=100 THEN t.height_inches END,
  'depth_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END) e WHERE tj_private.pim_web_spec_key(e.key)='depth' AND NOT tj_private.pim_web_blank(e.value)) AND before_p.facet_depth_in IS NULL AND t.depth_inches>0 AND t.depth_inches<=100 THEN t.depth_inches END)));
 p.dimensions:=dims;
 IF nullif(btrim(p.finish),'') IS NULL THEN p.finish:=nullif(btrim(t.finish),''); END IF;
 IF p.facet_finish IS NULL THEN p.facet_finish:=coalesce(p.finish,nullif(btrim(t.finish),'')); END IF;
 IF p.facet_width_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each((CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END)||(CASE WHEN jsonb_typeof(before_p.dimensions)='object' THEN before_p.dimensions ELSE '{}'::jsonb END)) e WHERE tj_private.pim_web_spec_key(e.key)='width' AND NOT tj_private.pim_web_blank(e.value)) AND t.width_inches BETWEEN
  (CASE category WHEN 'dishwashers' THEN 17.5 WHEN 'washers' THEN 23 WHEN 'dryers' THEN 23
   WHEN 'laundry' THEN 23 WHEN 'refrigerators' THEN 14 WHEN 'freezers' THEN 11 WHEN 'ranges' THEN 20
   WHEN 'cooktops' THEN 15 WHEN 'wall-ovens' THEN 20 ELSE 11 END)
  AND (CASE category WHEN 'dishwashers' THEN 25 WHEN 'washers' THEN 30 WHEN 'dryers' THEN 30
   WHEN 'laundry' THEN 30 WHEN 'freezers' THEN 73.25 ELSE 48 END) THEN p.facet_width_in:=t.width_inches; END IF;
 IF p.facet_height_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each((CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END)||(CASE WHEN jsonb_typeof(before_p.dimensions)='object' THEN before_p.dimensions ELSE '{}'::jsonb END)) e WHERE tj_private.pim_web_spec_key(e.key)='height' AND NOT tj_private.pim_web_blank(e.value)) AND t.height_inches>0 AND t.height_inches<=84 THEN p.facet_height_in:=t.height_inches; END IF;
 IF p.facet_depth_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each((CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END)||(CASE WHEN jsonb_typeof(before_p.dimensions)='object' THEN before_p.dimensions ELSE '{}'::jsonb END)) e WHERE tj_private.pim_web_spec_key(e.key)='depth' AND NOT tj_private.pim_web_blank(e.value)) AND t.depth_inches BETWEEN (CASE category WHEN 'ventilation' THEN 2.75 ELSE 5 END) AND 40 THEN p.facet_depth_in:=t.depth_inches; END IF;
 IF p.facet_capacity_cuft IS NULL AND category<>'dishwashers' AND t.capacity_cu_ft BETWEEN 0.5 AND 35 THEN p.facet_capacity_cuft:=t.capacity_cu_ft; END IF;
 IF p.facet_fuel IS NULL THEN p.facet_fuel:=CASE lower(t.fuel_type)
  WHEN 'gas' THEN 'Gas' WHEN 'electric' THEN 'Electric' WHEN 'induction' THEN 'Induction'
  WHEN 'dual fuel' THEN 'Dual Fuel' WHEN 'dual-fuel' THEN 'Dual Fuel' WHEN 'heat pump' THEN 'Heat Pump' END; END IF;
 -- Do not turn default false booleans or MSRP into claimed verified facts/current offers.
 SELECT count(*) INTO image_candidates FROM tj.pim_product_images WHERE product_id=t.id;
 SELECT jsonb_agg(eligible.url ORDER BY eligible.updated_at DESC,eligible.is_primary DESC NULLS LAST,eligible.id)
 INTO image_urls FROM (
  SELECT DISTINCT ON(coalesce(nullif(i.cdn_url,''),i.file_url)) i.id,
   coalesce(nullif(i.cdn_url,''),i.file_url) url,i.updated_at,i.is_primary
  FROM tj.pim_product_images i
  WHERE i.product_id=t.id AND i.approved AND NOT coalesce(i.embargoed,true)
   AND (i.available_from IS NULL OR i.available_from<=now()) AND (i.available_until IS NULL OR i.available_until>now())
   AND (i.audience_tiers && ARRAY['public','all']) AND coalesce(cardinality(i.exclusive_codes),0)=0
   AND coalesce(nullif(i.cdn_url,''),i.file_url) ~ '^https://[^/@?#]+([/?#]|$)'
   AND EXISTS(SELECT 1 FROM public.product_images native
    JOIN public.media_rights_source rs ON rs.id=native.rights_source_id
    WHERE native.product_id=candidate AND native.url=coalesce(nullif(i.cdn_url,''),i.file_url)
     AND native.status='active' AND native.permission_status IN ('approved','partner_provided','licensed')
     AND native.rights_override IS NULL AND public.media_rights_effective(rs.grant_id,'applianceiq',coalesce(p.market,'CA'),now()))
   AND EXISTS(SELECT 1 FROM public.image_audit_results a WHERE a.product_id=candidate
    AND a.url=coalesce(nullif(i.cdn_url,''),i.file_url) AND a.decode_ok AND a.fetch_status=200
    AND a.content_type LIKE 'image/%' AND a.audited_at>=coalesce(i.updated_at,i.created_at))
  ORDER BY coalesce(nullif(i.cdn_url,''),i.file_url),i.updated_at DESC,i.id
 ) eligible;
 IF nullif(btrim(p.image_url),'') IS NULL AND jsonb_array_length(coalesce(image_urls,'[]'))>0 THEN p.image_url:=image_urls->>0; END IF;
 IF coalesce(cardinality(p.gallery_urls),0)=0 AND jsonb_array_length(coalesce(image_urls,'[]'))>0 THEN SELECT array_agg(x) INTO p.gallery_urls FROM jsonb_array_elements_text(image_urls) x; END IF;
 SELECT d.file_url INTO spec_url FROM tj.pim_product_documents d WHERE d.product_id=t.id
 AND d.doc_type IN ('spec_sheet','specification','specifications') AND d.approved AND d.is_current
 AND NOT coalesce(d.requires_auth,true) AND NOT coalesce(d.embargoed,true)
 AND (d.effective_date IS NULL OR d.effective_date<=current_date) AND (d.expiry_date IS NULL OR d.expiry_date>=current_date)
 AND (d.available_from IS NULL OR d.available_from<=now()) AND (d.available_until IS NULL OR d.available_until>now())
 AND d.audience_tiers && ARRAY['public','all'] AND coalesce(cardinality(d.exclusive_codes),0)=0
 AND d.file_url ~ '^https://[^/@?#]+([/?#]|$)' ORDER BY d.updated_at DESC,d.id LIMIT 1;
 IF nullif(btrim(p.spec_sheet_url),'') IS NULL THEN p.spec_sheet_url:=spec_url; END IF;
 INSERT INTO public.tj_listing_import(tj_listing_id,tj_product_id,brand_name,model,retailer_name,product_url,retailer_url,
 price,regular_price,on_sale,in_stock,condition_raw,listing_status,price_currency,country,checked_at,first_seen_at,last_seen_at,
 retailer_sku,matched_product_id,match_method)
 SELECT r.id,r.product_id,r.brand_name,r.model,r.retailer_name,r.product_url,r.retailer_url,
 r.price,r.regular_price,r.on_sale,r.in_stock,r.condition_raw,r.listing_status::text,r.price_currency,r.country,
 r.checked_at,r.first_seen_at,r.last_seen_at,r.retailer_sku,candidate,'pim_fill_only_exact_brand_model'
 FROM tj.pim_retailer_prices r WHERE r.product_id=t.id
 AND tj_private.pim_web_key(r.model)=model_key AND public.brand_resolve(r.brand_name)=canonical_brand
 ON CONFLICT(tj_listing_id) DO UPDATE SET matched_product_id=excluded.matched_product_id,match_method=excluded.match_method
 WHERE public.tj_listing_import.matched_product_id IS NULL;
 -- Current prices are not synthesized from undated MSRP or stale observations.
 -- Audit before/after captures only the columns this writer owns. Existing source, trust and prices remain unchanged.
 result:=jsonb_build_object('description',p.description,'specs',p.specs,'dimensions',p.dimensions,
 'finish',p.finish,'facet_finish',p.facet_finish,'facet_width_in',p.facet_width_in,'facet_height_in',p.facet_height_in,
 'facet_depth_in',p.facet_depth_in,'facet_capacity_cuft',p.facet_capacity_cuft,'facet_fuel',p.facet_fuel,
 'image_url',p.image_url,'gallery_urls',p.gallery_urls,'spec_sheet_url',p.spec_sheet_url);
 IF result IS DISTINCT FROM jsonb_build_object('description',before_p.description,'specs',before_p.specs,'dimensions',before_p.dimensions,
 'finish',before_p.finish,'facet_finish',before_p.facet_finish,'facet_width_in',before_p.facet_width_in,'facet_height_in',before_p.facet_height_in,
 'facet_depth_in',before_p.facet_depth_in,'facet_capacity_cuft',before_p.facet_capacity_cuft,'facet_fuel',before_p.facet_fuel,
 'image_url',before_p.image_url,'gallery_urls',before_p.gallery_urls,'spec_sheet_url',before_p.spec_sheet_url) THEN
 UPDATE public.products SET description=p.description,specs=p.specs,dimensions=p.dimensions,finish=p.finish,
 facet_finish=p.facet_finish,facet_width_in=p.facet_width_in,facet_height_in=p.facet_height_in,
 facet_depth_in=p.facet_depth_in,facet_capacity_cuft=p.facet_capacity_cuft,facet_fuel=p.facet_fuel,
 image_url=p.image_url,gallery_urls=p.gallery_urls,spec_sheet_url=p.spec_sheet_url,
 write_source='pim_catalog_completion' WHERE id=candidate RETURNING * INTO p;
 action:=CASE WHEN new_record THEN 'created' ELSE 'filled_blanks' END;
 ELSE action:=CASE WHEN new_record THEN 'created' ELSE 'already_complete' END; END IF;
 IF action<>'already_complete' THEN
 INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
 VALUES(t.organization_id,t.id,candidate,src_date,action,to_jsonb(before_p),to_jsonb(p),
 jsonb_build_object('saved_image_records',image_candidates,'eligible_image_records',jsonb_array_length(coalesce(image_urls,'[]')),
 'source_type',t.source_type,'source_reference',t.source_reference,'pricing','dated historical listings retained; no price refresh fabricated'));
 END IF;
 RETURN jsonb_build_object('action',action,'website_product_id',candidate,'pim_product_id',t.id);
END $$;

DO $repair$
DECLARE l record; p public.products; restore_specs boolean; restore_dims boolean;
BEGIN
 FOR l IN SELECT * FROM tj_private.pim_web_completion_log WHERE action IN ('filled_blanks','created') ORDER BY id LOOP
  SELECT * INTO p FROM public.products WHERE id=l.website_product_id FOR UPDATE;
  restore_specs:=p.specs IS NOT DISTINCT FROM l.after_values->'specs';
  restore_dims:=p.dimensions IS NOT DISTINCT FROM l.after_values->'dimensions';
  IF restore_specs OR restore_dims THEN
   UPDATE public.products SET
    specs=CASE WHEN restore_specs THEN nullif(l.before_values->'specs','null'::jsonb) ELSE p.specs END,
    dimensions=CASE WHEN restore_dims THEN nullif(l.before_values->'dimensions','null'::jsonb) ELSE p.dimensions END
   WHERE id=l.website_product_id;
   INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
   SELECT l.organization_id,l.pim_product_id,l.website_product_id,l.source_updated_at,'repair_json_before_recompletion',to_jsonb(p),to_jsonb(x),jsonb_build_object('original_log_id',l.id)
   FROM public.products x WHERE x.id=l.website_product_id;
   UPDATE tj_private.pim_web_completion_queue SET processed_at=NULL,last_error=NULL,attempts=0 WHERE pim_product_id=l.pim_product_id;
  END IF;
 END LOOP;
END $repair$;
