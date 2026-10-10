-- Owner explicitly approved publishing PIM appliance images on 2026-10-10.
-- Preserve source approval/review/manufacturer-verification fields; record owner authority separately.
CREATE OR REPLACE FUNCTION tj_private.pim_web_image_appliance(t tj.aiq_products) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT coalesce(t.status='active' AND t.approval_status='approved'
 AND t.is_parts_accessory IS FALSE
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

CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_images(source_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
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
   AND replace(coalesce(nullif(i.cdn_url,''),i.file_url),'&amp;','&') ~* '^https://[^/@?#]+/[^?#]*\.(jpe?g|png|webp|avif|gif)([?#]|$)'
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
 UPDATE public.products SET image_url=p.image_url,gallery_urls=p.gallery_urls,
 source_metadata=coalesce(source_metadata,'{}'::jsonb)||jsonb_build_object('pim_image_publication',jsonb_build_object(
  'authority','owner_explicit_instruction','approved_on','2026-10-10','mode','preserve_and_append',
  'pim_product_id',t.id,'images',image_sources,'verification','source asset URLs; no manufacturer verification claimed'))
 WHERE id=candidate RETURNING * INTO p;
 INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
 VALUES(t.organization_id,t.id,candidate,greatest(t.updated_at,t.created_at),'filled_images',to_jsonb(before_p),to_jsonb(p),
 jsonb_build_object('authority','owner_explicit_instruction','pim_image_sources',image_sources));
 RETURN jsonb_build_object('action','filled_images','website_product_id',candidate,'gallery_count',cardinality(p.gallery_urls));
END $$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_batch(batch_size integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q record; outcome jsonb; images jsonb; stats jsonb:='{}'; label text;
BEGIN
 IF batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid_batch_size'; END IF;
 FOR q IN SELECT * FROM tj_private.pim_web_completion_queue WHERE processed_at IS NULL AND attempts<5
 ORDER BY queued_at,pim_product_id LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  BEGIN
   outcome:=tj_private.pim_web_complete_product(q.pim_product_id);
   images:=tj_private.pim_web_complete_images(q.pim_product_id);
   label:=CASE WHEN images->>'action'='filled_images' THEN 'filled_images' ELSE outcome->>'action' END;
   UPDATE tj_private.pim_web_completion_queue SET processed_at=clock_timestamp(),attempts=0,last_error=NULL WHERE pim_product_id=q.pim_product_id;
  EXCEPTION WHEN OTHERS THEN
   label:='error'; UPDATE tj_private.pim_web_completion_queue SET attempts=attempts+1,last_error=SQLSTATE||':'||SQLERRM WHERE pim_product_id=q.pim_product_id;
  END;
  stats:=jsonb_set(stats,ARRAY[label],to_jsonb(coalesce((stats->>label)::int,0)+1));
 END LOOP;
 RETURN stats;
END $$;
REVOKE ALL ON FUNCTION tj_private.pim_web_image_appliance(tj.aiq_products),tj_private.pim_web_complete_images(uuid),tj_private.pim_web_complete_batch(integer)
 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id)
 SELECT t.id,t.organization_id FROM tj.aiq_products t WHERE tj_private.pim_web_image_appliance(t)
 AND EXISTS(SELECT 1 FROM tj.pim_product_images i WHERE i.product_id=t.id)
 ON CONFLICT(pim_product_id) DO UPDATE SET processed_at=NULL,last_error=NULL,attempts=0,queued_at=clock_timestamp();
