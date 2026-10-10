BEGIN;
DO $test$
DECLARE sid uuid; wid uuid; before_row public.products; after_row public.products; x jsonb; logs int;
BEGIN
 SELECT t.id,p.id INTO sid,wid FROM tj.aiq_products t JOIN public.products p ON tj_private.pim_web_key(p.model_number)=tj_private.pim_web_key(t.model)
 AND coalesce(p.brand_canonical_id,public.brand_resolve(p.brand_name))=public.brand_resolve(t.brand_name)
 AND (p.market IS NULL OR t.market IS NULL OR p.market=t.market)
 AND p.category=tj_private.pim_web_category(t.category) AND p.status NOT IN ('hidden','archived')
 WHERE tj_private.pim_web_image_appliance(t) AND EXISTS(SELECT 1 FROM tj.pim_product_images i WHERE i.product_id=t.id) LIMIT 1;
 IF sid IS NULL THEN RAISE EXCEPTION 'no_image_fixture'; END IF;
 SELECT * INTO before_row FROM public.products WHERE id=wid;
 x:=tj_private.pim_web_complete_images(sid);
 SELECT * INTO after_row FROM public.products WHERE id=wid;
 IF nullif(btrim(before_row.image_url),'') IS NOT NULL AND after_row.image_url IS DISTINCT FROM before_row.image_url THEN RAISE EXCEPTION 'existing_hero_replaced'; END IF;
 IF NOT coalesce(before_row.gallery_urls,ARRAY[]::text[]) <@ coalesce(after_row.gallery_urls,ARRAY[]::text[]) THEN RAISE EXCEPTION 'existing_gallery_removed'; END IF;
 IF after_row.description IS DISTINCT FROM before_row.description OR after_row.specs IS DISTINCT FROM before_row.specs OR after_row.dimensions IS DISTINCT FROM before_row.dimensions THEN RAISE EXCEPTION 'facts_changed_by_image_worker'; END IF;
 SELECT count(*) INTO logs FROM tj_private.pim_web_completion_log WHERE website_product_id=wid;
 x:=tj_private.pim_web_complete_images(sid);
 IF logs<>(SELECT count(*) FROM tj_private.pim_web_completion_log WHERE website_product_id=wid) THEN RAISE EXCEPTION 'repeat_image_duplicate'; END IF;
 IF has_function_privilege('anon','tj_private.pim_web_complete_images(uuid)','execute') OR has_function_privilege('authenticated','tj_private.pim_web_complete_images(uuid)','execute') THEN RAISE EXCEPTION 'image_worker_public'; END IF;
END $test$; ROLLBACK;
