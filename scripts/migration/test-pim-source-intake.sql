BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('pim-pipeline-worker',0)); DO $test$
DECLARE p public.products; original public.products; after_p public.products; t tj.aiq_products; pid uuid; o public.price_observations;
BEGIN
 SELECT pp.* INTO p FROM public.products pp WHERE pp.status='active' AND pp.manufacturer_status='enriched'
 AND EXISTS(SELECT 1 FROM tj.aiq_products tt WHERE tj_private.pim_web_key(tt.model)=tj_private.pim_web_key(pp.model_number)
 AND public.brand_resolve(tt.brand_name)=public.brand_resolve(pp.brand_name) AND tt.status='active' AND tt.approval_status='approved'
 AND tt.market=pp.market AND tj_private.pim_web_category(tt.category)=pp.category)
 AND public.catalog_containment_reason(pp.product_name,pp.brand_name,pp.category) IS NULL
 AND NOT tj_private.pim_web_part_description(coalesce(pp.description,'')) LIMIT 1;
 IF p.id IS NULL THEN RAISE EXCEPTION 'missing_dated_fixture'; END IF;
 original:=p;
 UPDATE public.products SET specs=coalesce(specs,'{}'::jsonb)||'{"pim_pipeline_rollback_fact":"test-fill"}'::jsonb,
 manufacturer_enriched_at=now() WHERE id=p.id;
 SELECT * INTO after_p FROM public.products WHERE id=p.id;
 SELECT pim_product_id INTO pid FROM tj_private.pim_catalog_links WHERE website_product_id=p.id;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid;
 IF t.specs_json->>'pim_pipeline_rollback_fact'<>'test-fill' OR after_p.specs->>'pim_pipeline_rollback_fact'<>'test-fill'
 THEN RAISE EXCEPTION 'pim_first_fact_missing'; END IF;
 IF tj_private.pim_web_fill_json(after_p.specs,original.specs) IS DISTINCT FROM after_p.specs THEN RAISE EXCEPTION 'native_known_specs_replaced'; END IF;
 IF nullif(original.description,'') IS NOT NULL AND original.description IS DISTINCT FROM after_p.description THEN RAISE EXCEPTION 'native_description_changed'; END IF;
 IF nullif(original.image_url,'') IS NOT NULL AND original.image_url IS DISTINCT FROM after_p.image_url THEN RAISE EXCEPTION 'native_image_changed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj_private.pim_feed_receipts WHERE website_product_id=p.id AND source_date IS NOT NULL) THEN RAISE EXCEPTION 'source_date_not_retained'; END IF;
 SELECT * INTO o FROM public.price_observations WHERE product_id=p.id AND currency IN ('CAD','USD') AND observed_price IS NOT NULL AND observed_price>=0 AND coalesce(country,market)=p.market AND source_url LIKE 'https://%' ORDER BY last_checked_at DESC LIMIT 1;
 IF o.id IS NOT NULL THEN
  PERFORM tj_private.pim_capture_price(o);
  IF NOT EXISTS(SELECT 1 FROM tj.pim_price_history WHERE source_observation_id=o.id AND checked_at=o.last_checked_at
    AND source_evidence->>'public_display_status'=o.public_display_status) THEN RAISE EXCEPTION 'dated_price_evidence_lost'; END IF;
 END IF;
 IF has_function_privilege('anon','tj_private.pim_capture_catalog(public.products,text,timestamptz)','execute')
 OR has_function_privilege('authenticated','tj_private.pim_capture_price(public.price_observations)','execute') THEN RAISE EXCEPTION 'public_intake'; END IF;
END $test$; ROLLBACK;
