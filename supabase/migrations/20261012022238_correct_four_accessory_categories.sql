BEGIN;
CREATE TEMP TABLE accessory_fix AS
SELECT t.id pim_id,p.id website_id,t.organization_id,to_jsonb(t) before_pim,to_jsonb(p) before_web
FROM tj.aiq_products t JOIN public.products p ON p.model_number=t.model AND public.brand_resolve(p.brand_name)=public.brand_resolve(t.brand_name)
WHERE (t.brand_name='Fhiaba' AND t.model IN ('35133308','35134216','35135092') AND t.short_description ~* '(kit|shelf accessory)')
 OR (t.brand_name='Coyote' AND t.model='CSTUBE' AND t.short_description='Coyote Pellet Grill Tube CSTUBE');
DO $$ BEGIN IF (SELECT count(*) FROM accessory_fix)<>4 THEN RAISE EXCEPTION 'accessory_precondition_changed';END IF;END $$;
INSERT INTO tj_private.migration_delta_before_images(run_id,table_name,row_key,organization_id,before_data,source_checksum)
SELECT gen_random_uuid(),'accessory_pim_classification',pim_id::text,organization_id,before_pim,md5(before_pim::text) FROM accessory_fix
UNION ALL SELECT gen_random_uuid(),'accessory_web_classification',website_id::text,organization_id,before_web,md5(before_web::text) FROM accessory_fix;
UPDATE tj.aiq_products t SET is_parts_accessory=true,category='Accessories',updated_at=now() FROM accessory_fix f WHERE t.id=f.pim_id;
UPDATE public.products p SET category='accessories',updated_at=now() FROM accessory_fix f WHERE p.id=f.website_id;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM accessory_fix f JOIN tj.aiq_products t ON t.id=f.pim_id JOIN public.products p ON p.id=f.website_id WHERE NOT t.is_parts_accessory OR p.category<>'accessories' OR p.image_url IS DISTINCT FROM f.before_web->>'image_url' OR to_jsonb(p.gallery_urls) IS DISTINCT FROM f.before_web->'gallery_urls') THEN RAISE EXCEPTION 'accessory_validation_failed';END IF;END $$;
COMMIT;
