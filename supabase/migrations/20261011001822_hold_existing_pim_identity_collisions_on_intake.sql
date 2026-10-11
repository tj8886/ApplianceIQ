CREATE OR REPLACE FUNCTION tj_private.pim_capture_catalog(p public.products,kind text,source_date timestamptz) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t tj.aiq_products; before_t tj.aiq_products; src jsonb; specs jsonb; cat text; u text; pid uuid;
BEGIN
 cat:=tj_private.pim_web_category(p.category);
 IF p.status IN ('hidden','archived') OR cat IS NULL OR public.brand_resolve(p.brand_name) IS NULL
 OR length(tj_private.pim_web_key(p.model_number))<3 OR p.model_number !~ '[0-9]' OR p.model_number !~ '[[:alpha:]]'
 OR p.model_number ~ '[,|/]' OR public.catalog_containment_reason(p.product_name,p.brand_name,p.category) IS NOT NULL
 OR tj_private.pim_web_part_description(coalesce(p.description,'')) THEN RETURN NULL; END IF;
 IF source_date>now()+interval '5 minutes' THEN RETURN NULL; END IF;
 IF NOT pg_try_advisory_xact_lock(hashtextextended('pim-web:'||tj_private.pim_web_key(p.model_number),0)) THEN RETURN NULL; END IF;
 SELECT pim_product_id INTO pid FROM tj_private.pim_catalog_links WHERE website_product_id=p.id;
 IF pid IS NULL THEN
  SELECT s.id INTO pid FROM tj.aiq_products s WHERE s.status='active' AND s.approval_status='approved'
   AND s.is_parts_accessory IS FALSE AND tj_private.pim_web_category(s.category)=cat
   AND tj_private.pim_web_key(s.model)=tj_private.pim_web_key(p.model_number)
   AND public.brand_resolve(s.brand_name)=public.brand_resolve(p.brand_name)
   AND (s.market IS NOT DISTINCT FROM coalesce(p.market,'CA'))
   AND NOT tj_private.pim_web_part_description(coalesce(s.short_description,s.long_description,''))
  ORDER BY (s.source_review_status IN ('accepted','not_required')) DESC,
   greatest(s.updated_at,s.created_at,s.source_extracted_at) DESC,s.id LIMIT 1;
 END IF;
 -- A new master requires dated actual enrichment, not an undated/sample catalog seed.
 IF pid IS NULL AND EXISTS(SELECT 1 FROM tj.aiq_products s
 WHERE tj_private.pim_web_key(s.model)=tj_private.pim_web_key(p.model_number)
 AND public.brand_resolve(s.brand_name)=public.brand_resolve(p.brand_name)
 AND (s.is_parts_accessory IS TRUE OR tj_private.pim_web_part_description(coalesce(s.short_description,s.long_description,'')))) THEN RETURN NULL; END IF;
 IF pid IS NULL AND EXISTS(SELECT 1 FROM tj.aiq_products s WHERE tj_private.pim_web_key(s.model)=tj_private.pim_web_key(p.model_number) AND public.brand_resolve(s.brand_name)=public.brand_resolve(p.brand_name) AND s.market=coalesce(p.market,'CA')) THEN RETURN NULL; END IF;
 IF pid IS NULL AND source_date IS NOT NULL THEN
  INSERT INTO tj.aiq_products(manufacturer_name,brand_name,model,category,market,status,approval_status,source_type,source_reference,
   source_extracted_at,source_review_status,public_visible)
  VALUES('',p.brand_name,p.model_number,cat,coalesce(p.market,'CA'),'active','approved','internal','native-catalog:'||p.id,
   source_date,'not_required',true) RETURNING id INTO pid;
 END IF;
 IF pid IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid FOR UPDATE;
 IF t.status<>'active' OR t.approval_status<>'approved' OR t.is_parts_accessory IS NOT FALSE THEN RETURN NULL; END IF;
 INSERT INTO tj_private.pim_catalog_links(website_product_id,pim_product_id,organization_id)
 VALUES(p.id,t.id,t.organization_id) ON CONFLICT(website_product_id) DO NOTHING;
 before_t:=t;
 src:=jsonb_build_object('description',p.description,'specs',p.specs,'dimensions',p.dimensions,'finish',p.finish,
 'facet_width_in',p.facet_width_in,'facet_height_in',p.facet_height_in,'facet_depth_in',p.facet_depth_in,
 'facet_capacity_cuft',p.facet_capacity_cuft,'facet_fuel',p.facet_fuel,'image_url',p.image_url,
 'gallery_urls',p.gallery_urls,'spec_sheet_url',p.spec_sheet_url,'source_url',p.spec_source_url);
 -- Preserve explicit PIM measurement/finish fields against contradictory JSON aliases.
 SELECT coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) INTO specs FROM jsonb_each(
  CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END) e
 WHERE NOT ((tj_private.pim_web_spec_key(e.key)='width' AND t.width_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='height' AND t.height_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='depth' AND t.depth_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='capacity' AND t.capacity_cu_ft IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='finish' AND nullif(btrim(t.finish),'') IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='fuel' AND nullif(btrim(t.fuel_type),'') IS NOT NULL));
 t.specs_json:=tj_private.pim_web_fill_json(t.specs_json,specs);
 IF nullif(btrim(t.long_description),'') IS NULL AND nullif(btrim(t.short_description),'') IS NULL
 THEN t.long_description:=nullif(btrim(p.description),''); END IF;
 t.finish:=coalesce(nullif(btrim(t.finish),''),nullif(btrim(p.finish),''));
 t.width_inches:=coalesce(t.width_inches,p.facet_width_in,CASE WHEN jsonb_typeof(p.dimensions->'width_inches')='number' THEN (p.dimensions->>'width_inches')::numeric END);
 t.height_inches:=coalesce(t.height_inches,p.facet_height_in,CASE WHEN jsonb_typeof(p.dimensions->'height_inches')='number' THEN (p.dimensions->>'height_inches')::numeric END);
 t.depth_inches:=coalesce(t.depth_inches,p.facet_depth_in,CASE WHEN jsonb_typeof(p.dimensions->'depth_inches')='number' THEN (p.dimensions->>'depth_inches')::numeric END);
 t.capacity_cu_ft:=coalesce(t.capacity_cu_ft,p.facet_capacity_cuft);
 t.fuel_type:=coalesce(nullif(btrim(t.fuel_type),''),nullif(btrim(p.facet_fuel),''));
 IF ROW(t.long_description,t.specs_json,t.finish,t.width_inches,t.height_inches,t.depth_inches,t.capacity_cu_ft,t.fuel_type)
 IS DISTINCT FROM ROW(before_t.long_description,before_t.specs_json,before_t.finish,before_t.width_inches,before_t.height_inches,before_t.depth_inches,before_t.capacity_cu_ft,before_t.fuel_type) THEN
  UPDATE tj.aiq_products SET long_description=t.long_description,specs_json=t.specs_json,finish=t.finish,
  width_inches=t.width_inches,height_inches=t.height_inches,depth_inches=t.depth_inches,capacity_cu_ft=t.capacity_cu_ft,
  fuel_type=t.fuel_type,updated_at=clock_timestamp(),source_extracted_at=greatest(source_extracted_at,source_date)
  WHERE id=t.id RETURNING * INTO t;
 END IF;
 FOR u IN SELECT DISTINCT x FROM unnest(coalesce(p.gallery_urls,ARRAY[]::text[])||ARRAY[p.image_url]) x
 WHERE x ~* '^https://[^/@?#]+/[^?#]*\.(jpe?g|png|webp|avif|gif)([?#]|$)' LOOP
  IF NOT EXISTS(SELECT 1 FROM tj.pim_product_images WHERE product_id=t.id AND coalesce(nullif(cdn_url,''),file_url)=u) THEN
   INSERT INTO tj.pim_product_images(product_id,file_url,source,approved,approved_at,audience_tiers,embargoed,created_at,updated_at)
   VALUES(t.id,u,'web_scrape',true,now(),ARRAY['public'],false,coalesce(source_date,now()),coalesce(source_date,now()));
  END IF;
 END LOOP;
 IF p.spec_sheet_url ~* '^https://[^/@?#]+/[^?#]*\.pdf([?#]|$)'
 AND NOT EXISTS(SELECT 1 FROM tj.pim_product_documents WHERE product_id=t.id AND file_url=p.spec_sheet_url) THEN
  INSERT INTO tj.pim_product_documents(product_id,file_url,doc_type,title,approved,is_current,requires_auth,embargoed,audience_tiers)
  VALUES(t.id,p.spec_sheet_url,'spec_sheet',p.brand_name||' '||p.model_number||' specifications',true,true,false,false,ARRAY['public']);
 END IF;
 INSERT INTO tj_private.pim_feed_receipts(organization_id,website_product_id,pim_product_id,kind,source_date,payload,before_values,after_values,outcome)
 VALUES(t.organization_id,p.id,t.id,kind,source_date,src,to_jsonb(before_t),to_jsonb(t),
 CASE WHEN before_t IS DISTINCT FROM t THEN 'filled_pim_blanks' ELSE 'retained_complete_pim' END);
 RETURN t.id;
END $$;


UPDATE tj_private.pim_incoming_reconcile_queue SET attempts=0,last_error=NULL,processed_at=NULL WHERE last_error LIKE '23505:%';
