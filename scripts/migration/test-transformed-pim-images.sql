BEGIN;
DO $test$
DECLARE i tj.pim_product_images; t tj.aiq_products; p public.products; a public.products; native_before jsonb; result jsonb; fixtures integer:=0;
BEGIN
 FOR i IN SELECT * FROM tj.pim_product_images WHERE id IN ('d8e97d05-dbe4-4ef2-bcbf-e486e6b04f22','b6b76173-c154-48f4-8788-db59a7056bbf') LOOP
  SELECT * INTO STRICT t FROM tj.aiq_products WHERE id=i.product_id;
  IF NOT tj_private.pim_web_verified_image_url(i,t.model) THEN RAISE EXCEPTION 'verified_asset_rejected'; END IF;
  i.approved:=false;
  IF tj_private.pim_web_verified_image_url(i,t.model) THEN RAISE EXCEPTION 'unapproved_asset_accepted'; END IF;
  i.approved:=true; i.mime_type:='text/html';
  IF tj_private.pim_web_verified_image_url(i,t.model) THEN RAISE EXCEPTION 'html_accepted'; END IF;
  i.mime_type:='image/jpeg';i.caption:='not json';
  IF tj_private.pim_web_verified_image_url(i,t.model) THEN RAISE EXCEPTION 'missing_evidence_accepted'; END IF;
  SELECT * INTO i FROM tj.pim_product_images WHERE id=i.id;
  IF tj_private.pim_web_verified_image_url(i,'WRONG-MODEL') THEN RAISE EXCEPTION 'wrong_model_accepted'; END IF;
  i.caption:=jsonb_set(i.caption::jsonb,'{checked_on}','"2099-01-01"')::text;
  IF tj_private.pim_web_verified_image_url(i,t.model) THEN RAISE EXCEPTION 'future_evidence_accepted'; END IF;
  SELECT * INTO i FROM tj.pim_product_images WHERE id=i.id;
  SELECT * INTO p FROM public.products WHERE id=t.id FOR UPDATE;
  native_before:=to_jsonb(t)-'updated_at';
  UPDATE public.products SET image_url=NULL,gallery_urls=ARRAY[]::text[],write_source='pim_catalog_completion' WHERE id=p.id;
  result:=tj_private.pim_web_complete_images(t.id);
  SELECT * INTO a FROM public.products WHERE id=p.id;
  IF result->>'action'<>'filled_images' OR a.image_url<>i.file_url OR NOT i.file_url=ANY(a.gallery_urls) THEN RAISE EXCEPTION 'blank_hero_not_published'; END IF;
  IF (to_jsonb(a)-ARRAY['image_url','gallery_urls','source_metadata','updated_at','write_source']) IS DISTINCT FROM (to_jsonb(p)-ARRAY['image_url','gallery_urls','source_metadata','updated_at','write_source']) THEN RAISE EXCEPTION 'catalog_facts_changed'; END IF;
  IF (SELECT to_jsonb(x)-'updated_at' FROM tj.aiq_products x WHERE id=t.id) IS DISTINCT FROM native_before THEN RAISE EXCEPTION 'pim_facts_changed'; END IF;
  result:=tj_private.pim_web_complete_images(t.id);
  IF result->>'action'<>'images_already_complete' THEN RAISE EXCEPTION 'repeat_not_idempotent'; END IF;
  UPDATE public.products SET image_url='https://example.test/existing.jpg',write_source='pim_catalog_completion' WHERE id=p.id;
  PERFORM tj_private.pim_web_complete_images(t.id);
  IF (SELECT image_url FROM public.products WHERE id=p.id)<>'https://example.test/existing.jpg' THEN RAISE EXCEPTION 'existing_hero_overwritten'; END IF;
  fixtures:=fixtures+1;
 END LOOP;
 IF fixtures<>2 THEN RAISE EXCEPTION 'missing_test_fixtures'; END IF;
END $test$;
ROLLBACK;
