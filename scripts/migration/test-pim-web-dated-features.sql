DO $test$
DECLARE f tj.pim_product_features; pid uuid; wid uuid; before_web jsonb; after_web jsonb; x jsonb; created timestamptz;
BEGIN
 SELECT feat.* INTO f FROM tj.pim_product_features feat JOIN tj.aiq_products t ON t.id=feat.product_id
 WHERE tj_private.pim_web_appliance(t) AND EXISTS(SELECT 1 FROM tj_private.pim_web_completion_log WHERE pim_product_id=t.id AND action='filled_blanks') LIMIT 1;
 IF f.id IS NULL THEN RAISE EXCEPTION 'missing_feature_fixture'; END IF;
 created:=f.created_at;
 SELECT website_product_id INTO wid FROM tj_private.pim_web_completion_log WHERE pim_product_id=f.product_id AND action='filled_blanks' ORDER BY id DESC LIMIT 1;
 SELECT to_jsonb(p) INTO before_web FROM public.products p WHERE p.id=wid;
 UPDATE tj.pim_product_features SET feature_value='rollback-newer-source-value' WHERE id=f.id;
 x:=tj_private.pim_web_incoming_specs(f.product_id,jsonb_build_object(f.feature_name,'older-source'),now()-interval '1 day');
 IF x->>f.feature_name<>'rollback-newer-source-value' THEN RAISE EXCEPTION 'latest_dated_source_not_selected'; END IF;
 IF (SELECT created_at FROM tj.pim_product_features WHERE id=f.id) IS DISTINCT FROM created THEN RAISE EXCEPTION 'historical_creation_date_changed'; END IF;
 IF (SELECT processed_at FROM tj_private.pim_web_completion_queue WHERE pim_product_id=f.product_id) IS NOT NULL THEN RAISE EXCEPTION 'feature_not_queued'; END IF;
 -- Repeated completion must not replace any already populated website spec value.
 PERFORM tj_private.pim_web_complete_product(f.product_id);
 SELECT to_jsonb(p) INTO after_web FROM public.products p WHERE p.id=wid;
 IF tj_private.pim_web_fill_json(after_web->'specs',before_web->'specs') IS DISTINCT FROM after_web->'specs' THEN RAISE EXCEPTION 'existing_website_specs_replaced'; END IF;
END $test$;
