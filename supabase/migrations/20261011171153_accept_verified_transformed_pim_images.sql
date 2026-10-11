-- Accept transformed assets only with explicit recorded image evidence.
CREATE OR REPLACE FUNCTION tj_private.pim_web_verified_image_url(i tj.pim_product_images, model text)
RETURNS boolean LANGUAGE plpgsql STABLE SET search_path='' AS $$
DECLARE u text:=replace(coalesce(nullif(i.cdn_url,''),i.file_url),'&amp;','&'); e jsonb;
BEGIN
 IF u IS NULL OR u !~ '^https://[^/@?#[:space:]]+/[^[:space:]]+$' THEN RETURN false; END IF;
 IF i.mime_type IS NOT NULL AND lower(split_part(i.mime_type,';',1)) NOT IN
 ('image/jpeg','image/png','image/webp','image/avif','image/gif') THEN RETURN false; END IF;
 IF u ~* '^https://[^/@?#]+/[^?#]*[.](jpe?g|png|webp|avif|gif)([?#]|$)' THEN RETURN true; END IF;
 -- Evidence applies to the file URL, not an unrelated CDN redirect.
 IF u IS DISTINCT FROM replace(i.file_url,'&amp;','&') OR NOT coalesce(i.approved,false)
 OR lower(split_part(coalesce(i.mime_type,''),';',1)) NOT IN
 ('image/jpeg','image/png','image/webp','image/avif','image/gif') THEN RETURN false; END IF;
 BEGIN e:=i.caption::jsonb; EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
 RETURN coalesce(e->>'exact_model'=model
 AND e->>'publication_status'='approved'
 AND e->>'image_use_permission_status'='owner_approved'
 AND nullif(e->>'approval_evidence','') IS NOT NULL
 AND e->>'visual_finish_checked'='true'
 AND e->>'http_status' IN ('200','206')
 AND lower(e->>'content_type')=lower(split_part(i.mime_type,';',1))
 AND e->>'source_page' ~ '^https://[^/@?#[:space:]]+/'
 AND e->>'checked_on' ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
 AND (e->>'checked_on')::date <= current_date,false);
 EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN RETURN false;
END $$;
REVOKE ALL ON FUNCTION tj_private.pim_web_verified_image_url(tj.pim_product_images,text)
FROM PUBLIC,anon,authenticated,service_role;

CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_images(source_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE t tj.aiq_products; p public.products; before_p public.products; candidate uuid;
 n integer; image_urls text[]; merged_urls text[]; image_sources jsonb; identity_row record;
BEGIN
 SELECT * INTO t FROM tj.aiq_products WHERE id=source_id;
 IF NOT FOUND OR NOT tj_private.pim_web_image_appliance(t) THEN RETURN jsonb_build_object('action','images_excluded'); END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pim-web:'||tj_private.pim_web_key(t.model),0));
 SELECT * INTO identity_row FROM public.pim_identity_current ic WHERE ic.source_id=t.id;
 IF FOUND AND identity_row.decision<>'approved' THEN RETURN jsonb_build_object('action','image_identity_review'); END IF;
 SELECT count(*),(array_agg(id))[1] INTO n,candidate FROM public.products
 WHERE tj_private.pim_web_key(model_number)=tj_private.pim_web_key(t.model)
 AND coalesce(brand_canonical_id,public.brand_resolve(brand_name))=public.brand_resolve(t.brand_name)
 AND (market IS NULL OR t.market IS NULL OR market=t.market);
 IF n<>1 THEN RETURN jsonb_build_object('action','images_no_unique_match'); END IF;
 IF identity_row.target_product_id IS NOT NULL AND identity_row.target_product_id IS DISTINCT FROM candidate THEN RETURN jsonb_build_object('action','image_identity_collision'); END IF;
 SELECT * INTO p FROM public.products WHERE id=candidate FOR UPDATE;
 IF p.status IN ('hidden','archived') OR p.category IS DISTINCT FROM tj_private.pim_web_category(t.category)
 THEN RETURN jsonb_build_object('action','images_withdrawn_or_category_collision'); END IF;
 before_p:=p;
 SELECT array_agg(x.url ORDER BY x.is_primary DESC NULLS LAST,x.display_order,x.source_date DESC,x.id),
 jsonb_agg(jsonb_build_object('pim_image_id',x.id,'url',x.url,'source_updated_at',x.source_date))
 INTO image_urls,image_sources FROM (
  SELECT DISTINCT ON(replace(coalesce(nullif(i.cdn_url,''),i.file_url),'&amp;','&')) i.id,
   replace(coalesce(nullif(i.cdn_url,''),i.file_url),'&amp;','&') url,
   i.is_primary,i.display_order,greatest(i.updated_at,i.created_at) source_date
  FROM tj.pim_product_images i WHERE i.product_id=t.id
   AND NOT coalesce(i.embargoed,false)
   AND (i.available_from IS NULL OR i.available_from<=now()) AND (i.available_until IS NULL OR i.available_until>now())
   AND i.audience_tiers && ARRAY['public','all'] AND coalesce(cardinality(i.exclusive_codes),0)=0
   AND greatest(i.updated_at,i.created_at)<=now()+interval '5 minutes'
   -- Image asset URLs only: do not insert HTML product pages as images.
   AND tj_private.pim_web_verified_image_url(i,t.model)
  ORDER BY replace(coalesce(nullif(i.cdn_url,''),i.file_url),'&amp;','&'),greatest(i.updated_at,i.created_at) DESC,i.id
 ) x;
 IF coalesce(cardinality(image_urls),0)=0 THEN RETURN jsonb_build_object('action','images_no_assets'); END IF;
 IF nullif(btrim(p.image_url),'') IS NULL THEN p.image_url:=image_urls[1]; END IF;
 -- Keep every existing URL in its original order; append only missing source assets.
 merged_urls:=coalesce(p.gallery_urls,ARRAY[]::text[]);
 IF nullif(btrim(before_p.image_url),'') IS NOT NULL AND NOT before_p.image_url=ANY(merged_urls)
 THEN merged_urls:=array_append(merged_urls,before_p.image_url); END IF;
 FOR n IN 1..cardinality(image_urls) LOOP
  IF NOT image_urls[n]=ANY(merged_urls) THEN merged_urls:=array_append(merged_urls,image_urls[n]); END IF;
 END LOOP;
 p.gallery_urls:=merged_urls;
 IF p.image_url IS NOT DISTINCT FROM before_p.image_url AND p.gallery_urls IS NOT DISTINCT FROM before_p.gallery_urls
 THEN RETURN jsonb_build_object('action','images_already_complete'); END IF;
 UPDATE public.products SET image_url=p.image_url,gallery_urls=p.gallery_urls,write_source='pim_catalog_completion',
 source_metadata=coalesce(source_metadata,'{}'::jsonb)||jsonb_build_object('pim_image_publication',jsonb_build_object(
  'authority','owner_explicit_instruction','approved_on','2026-10-10','mode','preserve_and_append',
  'pim_product_id',t.id,'images',image_sources,'verification','source asset URLs; no manufacturer verification claimed'))
 WHERE id=candidate RETURNING * INTO p;
 INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
 VALUES(t.organization_id,t.id,candidate,greatest(t.updated_at,t.created_at),'filled_images',to_jsonb(before_p),to_jsonb(p),
 jsonb_build_object('authority','owner_explicit_instruction','pim_image_sources',image_sources));
 RETURN jsonb_build_object('action','filled_images','website_product_id',candidate,'gallery_count',cardinality(p.gallery_urls));
END $function$
;
REVOKE ALL ON FUNCTION tj_private.pim_web_complete_images(uuid) FROM PUBLIC,anon,authenticated,service_role;
