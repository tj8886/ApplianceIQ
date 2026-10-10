CREATE OR REPLACE FUNCTION tj_private.pim_web_part_description(v text) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT public.spec_name_is_accessory(regexp_replace(
 CASE WHEN length(v)>300 THEN left(regexp_replace(v,'<[^>]*>','','g'),180) ELSE regexp_replace(v,'<[^>]*>','','g') END,
 '\m(with|including|includes)\s+(a\s+)?trim kit( included)?\M','','gi'))
$$;
REVOKE ALL ON FUNCTION tj_private.pim_web_part_description(text) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.pim_web_appliance(t tj.aiq_products) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT coalesce(t.status='active' AND t.approval_status='approved'
 AND t.source_review_status IN ('accepted','not_required') AND t.is_parts_accessory IS FALSE
 AND tj_private.pim_web_category(t.category) IS NOT NULL
 AND NOT tj_private.pim_web_part_description(coalesce(t.short_description,t.long_description,''))
 AND t.model !~* '(^|[- ])FILTER($|[- ])'
 AND t.model ~ '[[:alpha:]]' AND t.model ~ '[0-9]' AND length(t.model) BETWEEN 3 AND 60
 AND t.model !~ '[,|/]' AND t.brand_name IS NOT NULL
 AND length(tj_private.pim_web_key(t.model))>=3
 AND coalesce(t.short_description,'') !~* '^\s*(this\s+|replacement\s+|genuine\s+|universal\s+|original\s+|the\s+)?(water\s+filter|filter\s+(kit|cartridge)|trim\s+kit|stacking\s+kit|replacement\s+(part|filter)|installation\s+kit|hose|pedestal|burner\s+cap|handle\s+kit)\M'
 AND coalesce(t.product_line,'') !~* '(accessor|replacement part|filter kit)'
 AND coalesce(t.product_segment,'') !~* '(accessor|parts)'
 AND EXISTS(SELECT 1 FROM public.brand_canonical b WHERE b.id=public.brand_resolve(t.brand_name) AND b.is_active)
 AND greatest(t.created_at,t.updated_at,t.source_extracted_at)<=now()+interval '5 minutes',false)
$$;
DO $repair$
DECLARE r record; p public.products; original jsonb; latest jsonb; patch jsonb; k text; vals public.products;
BEGIN
 FOR r IN SELECT DISTINCT l.website_product_id FROM tj_private.pim_web_completion_log l JOIN tj.aiq_products t ON t.id=l.pim_product_id
 WHERE tj_private.pim_web_part_description(coalesce(t.short_description,t.long_description,'')) LOOP
  SELECT * INTO p FROM public.products WHERE id=r.website_product_id FOR UPDATE;
  SELECT before_values INTO original FROM tj_private.pim_web_completion_log WHERE website_product_id=p.id ORDER BY id LIMIT 1;
  SELECT after_values INTO latest FROM tj_private.pim_web_completion_log WHERE website_product_id=p.id AND after_values IS NOT NULL ORDER BY id DESC LIMIT 1;
  patch:='{}';
  FOREACH k IN ARRAY ARRAY['description','specs','dimensions','finish','facet_finish','facet_width_in','facet_height_in','facet_depth_in','facet_capacity_cuft','facet_fuel','image_url','gallery_urls','spec_sheet_url'] LOOP
   IF to_jsonb(p)->k IS NOT DISTINCT FROM latest->k THEN patch:=patch||jsonb_build_object(k,original->k); END IF;
  END LOOP;
  IF EXISTS(SELECT 1 FROM tj_private.pim_web_completion_log WHERE website_product_id=p.id AND action='created') THEN patch:=patch||jsonb_build_object('status','hidden'); END IF;
  vals:=jsonb_populate_record(p,patch);
  UPDATE public.products SET description=vals.description,specs=vals.specs,dimensions=vals.dimensions,finish=vals.finish,
   facet_finish=vals.facet_finish,facet_width_in=vals.facet_width_in,facet_height_in=vals.facet_height_in,
   facet_depth_in=vals.facet_depth_in,facet_capacity_cuft=vals.facet_capacity_cuft,facet_fuel=vals.facet_fuel,
   image_url=vals.image_url,gallery_urls=vals.gallery_urls,spec_sheet_url=vals.spec_sheet_url,status=vals.status
  WHERE id=p.id;
  INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
  SELECT l.organization_id,l.pim_product_id,p.id,l.source_updated_at,'exclude_mislabelled_accessory',to_jsonb(p),to_jsonb(x),jsonb_build_object('records_retained',true)
  FROM public.products x CROSS JOIN LATERAL (SELECT * FROM tj_private.pim_web_completion_log WHERE website_product_id=p.id ORDER BY id LIMIT 1) l WHERE x.id=p.id;
 END LOOP;
END $repair$;
DO $tests$ BEGIN
 IF NOT tj_private.pim_web_part_description('Electrolux Water Filter EWF02C')
 OR NOT tj_private.pim_web_part_description('LG Stacking Kit for 27 inch Front Load Laundry Pair HSTK1B')
 OR NOT tj_private.pim_web_part_description('Crown Verity 4-Piece Steak Knife Set CV-KS-1')
 OR tj_private.pim_web_part_description('Cosmo 30 in. 1.6 cu. ft. Built-In Microwave Oven in Stainless Steel with Trim Kit Included')
 THEN RAISE EXCEPTION 'appliance_only_description_contract'; END IF;
 IF EXISTS(SELECT 1 FROM tj_private.pim_web_completion_log l JOIN public.products p ON p.id=l.website_product_id JOIN tj.aiq_products t ON t.id=l.pim_product_id
 WHERE l.action='created' AND p.status='active' AND tj_private.pim_web_part_description(coalesce(t.short_description,t.long_description,''))) THEN RAISE EXCEPTION 'new_accessory_remains_visible'; END IF;
END $tests$;
