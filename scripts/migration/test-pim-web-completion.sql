DO $test$
DECLARE x jsonb;
BEGIN
 x:=tj_private.pim_web_fill_json('{"width_inches":30,"wifi":false,"count":0,"nested":{"present":"keep","blank":null}}',
 '{"Width":36,"wifi":true,"count":2,"nested":{"present":"replace","blank":"fill","new":"yes"},"dealer_cost":10,"new":"fact"}');
 IF x#>>'{width_inches}'<>'30' OR x?'Width' OR x->'wifi'<>'false'::jsonb OR x->'count'<>'0'::jsonb
 OR x#>>'{nested,present}'<>'keep' OR x#>>'{nested,blank}'<>'fill' OR x#>>'{nested,new}'<>'yes'
 OR x?'dealer_cost' OR x->>'new'<>'fact' THEN RAISE EXCEPTION 'fill_only_semantic_preservation_failed: %',x; END IF;
 IF tj_private.pim_web_category('cooking-accessories') IS NOT NULL OR tj_private.pim_web_category('blower') IS NOT NULL
 OR tj_private.pim_web_category('Refrigerators')<>'refrigerators' THEN RAISE EXCEPTION 'parts_category_failed'; END IF;
 IF has_function_privilege('anon','tj_private.pim_web_complete_product(uuid)','EXECUTE')
 OR has_function_privilege('authenticated','tj_private.pim_web_complete_batch(integer)','EXECUTE') THEN
 RAISE EXCEPTION 'public_worker_access'; END IF;
END $test$;
DO $life$
DECLARE sid uuid; target uuid; x jsonb; before_row jsonb; after_row jsonb; qstamp timestamptz; first_count int;
BEGIN
 SELECT id INTO sid FROM tj.aiq_products t WHERE tj_private.pim_web_appliance(t)
 AND EXISTS(SELECT 1 FROM public.products p WHERE tj_private.pim_web_key(p.model_number)=tj_private.pim_web_key(t.model)
 AND coalesce(p.brand_canonical_id,public.brand_resolve(p.brand_name))=public.brand_resolve(t.brand_name)) ORDER BY id LIMIT 1;
 x:=tj_private.pim_web_complete_product(sid); target:=(x->>'website_product_id')::uuid;
 IF target IS NULL THEN RAISE EXCEPTION 'no_test_match: %',x; END IF;
 SELECT to_jsonb(p) INTO before_row FROM public.products p WHERE p.id=target;
 SELECT count(*) INTO first_count FROM tj_private.pim_web_completion_log WHERE website_product_id=target;
 x:=tj_private.pim_web_complete_product(sid);
 SELECT to_jsonb(p) INTO after_row FROM public.products p WHERE p.id=target;
 IF before_row IS DISTINCT FROM after_row THEN RAISE EXCEPTION 'repeat_modified_completed_product'; END IF;
 IF first_count<>(SELECT count(*) FROM tj_private.pim_web_completion_log WHERE website_product_id=target) THEN RAISE EXCEPTION 'repeat_audit_duplication'; END IF;
 UPDATE tj_private.pim_web_completion_queue SET processed_at=now() WHERE pim_product_id=sid;
 UPDATE tj.aiq_products SET updated_at=now() WHERE id=sid;
 IF (SELECT processed_at FROM tj_private.pim_web_completion_queue WHERE pim_product_id=sid) IS NOT NULL THEN RAISE EXCEPTION 'automatic_queue_failed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM tj.aiq_products WHERE id=sid) THEN RAISE EXCEPTION 'source_changed'; END IF;
END $life$;
