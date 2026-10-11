BEGIN;
SET LOCAL statement_timeout='25s';
CREATE TEMP TABLE duplicate_pim_matches ON COMMIT DROP AS
SELECT t.id source_id,z.id canonical_id,t.organization_id,t.model,to_jsonb(t) before_values
FROM tj.aiq_products t JOIN public.products p ON tj_private.pim_web_key(p.model_number)=tj_private.pim_web_key(t.model)
JOIN tj.aiq_products z ON z.model=t.model AND z.market='CA' AND z.brand_name=p.brand_name AND z.id<>t.id AND z.status='active' AND z.approval_status='approved'
WHERE t.id IN ('b211ca9e-ea68-493e-9811-ec0bacc3cdf5','1a4d6b88-e1a8-42e3-b068-b4cde1efa1f1','ef24eea5-4e25-4935-80aa-32ee3660f04b','91401f3a-4b7f-4ffc-b9c1-7fabea0b3253','0af68e71-f28e-4b38-bc1f-934feec6a5a8','dab68c55-60f4-4e7f-a9d4-e1ff744388d3')
AND t.status='active' AND t.market IN ('CA','Canada')
AND p.brand_canonical_id=public.brand_resolve(z.brand_name)
AND EXISTS(SELECT 1 FROM tj_private.pim_web_completion_log l WHERE l.website_product_id=p.id AND l.detail->>'operation'='resolve_43_remaining_appliance_matches');
CREATE TEMP TABLE copied_duplicate_assets ON COMMIT DROP AS
SELECT i.id original_image_id,gen_random_uuid() copied_image_id,b.source_id,b.canonical_id,to_jsonb(i) original_asset
FROM duplicate_pim_matches b JOIN tj.pim_product_images i ON i.product_id=b.source_id
WHERE NOT EXISTS(SELECT 1 FROM tj.pim_product_images z WHERE z.product_id=b.canonical_id
AND coalesce(nullif(z.cdn_url,''),z.file_url)=coalesce(nullif(i.cdn_url,''),i.file_url));
INSERT INTO tj.pim_product_images
SELECT (jsonb_populate_record(NULL::tj.pim_product_images,c.original_asset||jsonb_build_object('id',c.copied_image_id,'product_id',c.canonical_id))).* FROM copied_duplicate_assets c;
UPDATE tj.aiq_products t SET status='archived' FROM duplicate_pim_matches b WHERE t.id=b.source_id;
DO $check$ BEGIN
IF EXISTS(SELECT 1 FROM duplicate_pim_matches b JOIN tj.aiq_products t ON t.id=b.source_id WHERE (b.before_values - ARRAY['status','updated_at']) IS DISTINCT FROM (to_jsonb(t)-ARRAY['status','updated_at'])) THEN RAISE EXCEPTION 'Unexpected duplicate source change'; END IF;
END $check$;
INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,source_updated_at,action,before_values,after_values,detail)
SELECT b.organization_id,b.source_id,t.source_extracted_at,'retained_canonical_duplicate',b.before_values,to_jsonb(t),
jsonb_build_object('operation','consolidate_six_duplicate_pim_sources','canonical_pim_id',b.canonical_id,'exact_model',b.model,'manufacturer_proof_operation','resolve_43_remaining_appliance_matches','checked_on','2026-10-11','source_assets_dates_retained',true,'copied_images',(SELECT coalesce(jsonb_agg(jsonb_build_object('original_id',c.original_image_id,'copied_id',c.copied_image_id)),'[]') FROM copied_duplicate_assets c WHERE c.source_id=b.source_id))
FROM duplicate_pim_matches b JOIN tj.aiq_products t ON t.id=b.source_id;
INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id)
SELECT canonical_id,organization_id FROM duplicate_pim_matches
ON CONFLICT(pim_product_id) DO UPDATE SET queued_at=clock_timestamp(),processed_at=NULL
WHERE tj_private.pim_web_completion_queue.processed_at IS NOT NULL AND tj_private.pim_web_completion_queue.last_error IS NULL;
SELECT (SELECT count(*) FROM duplicate_pim_matches) retained_duplicate_sources,(SELECT count(*) FROM copied_duplicate_assets) source_images_copied;
COMMIT;
