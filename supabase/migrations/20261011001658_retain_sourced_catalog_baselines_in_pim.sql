CREATE OR REPLACE FUNCTION tj_private.pim_catalog_incoming_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE pid uuid; t tj.aiq_products; observed timestamptz; kind text;
BEGIN
 IF NEW.write_source='pim_catalog_completion' OR pg_trigger_depth()>1 THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND NEW.source_metadata->'pim_image_publication' IS DISTINCT FROM OLD.source_metadata->'pim_image_publication'
 THEN RETURN NEW; END IF;
 IF TG_OP='UPDATE' AND ROW(NEW.description,NEW.specs,NEW.dimensions,NEW.finish,NEW.facet_width_in,NEW.facet_height_in,NEW.facet_depth_in,
 NEW.facet_capacity_cuft,NEW.facet_fuel,NEW.image_url,NEW.gallery_urls,NEW.spec_sheet_url)
 IS NOT DISTINCT FROM ROW(OLD.description,OLD.specs,OLD.dimensions,OLD.finish,OLD.facet_width_in,OLD.facet_height_in,OLD.facet_depth_in,
 OLD.facet_capacity_cuft,OLD.facet_fuel,OLD.image_url,OLD.gallery_urls,OLD.spec_sheet_url) THEN RETURN NEW; END IF;
 observed:=greatest(CASE WHEN NEW.manufacturer_status='enriched' THEN NEW.manufacturer_enriched_at END,
 CASE WHEN NEW.icecat_status='enriched' THEN NEW.icecat_enriched_at END);
 kind:=CASE WHEN NEW.icecat_status='enriched' AND NEW.icecat_enriched_at=observed THEN 'icecat' ELSE 'native_scraper_or_manufacturer' END;
 IF TG_OP='UPDATE' AND (OLD.manufacturer_status='enriched' OR OLD.icecat_status='enriched' OR OLD.source_metadata?'pim_completion') THEN
  PERFORM tj_private.pim_capture_catalog(OLD,'existing_sourced_catalog_baseline',greatest(
   CASE WHEN OLD.manufacturer_status='enriched' THEN OLD.manufacturer_enriched_at END,
   CASE WHEN OLD.icecat_status='enriched' THEN OLD.icecat_enriched_at END));
 END IF;
 pid:=tj_private.pim_capture_catalog(NEW,kind,observed);
 IF pid IS NULL THEN
  IF TG_OP='UPDATE' AND observed IS NOT NULL AND NOT pg_try_advisory_xact_lock(hashtextextended('pim-web:'||tj_private.pim_web_key(NEW.model_number),0)) THEN
   INSERT INTO tj_private.pim_feed_receipts(organization_id,website_product_id,kind,source_date,payload,outcome)
   VALUES('00000000-0000-0000-0000-000000000002',NEW.id,kind,observed,to_jsonb(NEW)-'source_metadata','deferred_native_write');
   NEW.description:=OLD.description;NEW.specs:=OLD.specs;NEW.dimensions:=OLD.dimensions;NEW.finish:=OLD.finish;
   NEW.facet_width_in:=OLD.facet_width_in;NEW.facet_height_in:=OLD.facet_height_in;NEW.facet_depth_in:=OLD.facet_depth_in;
   NEW.facet_capacity_cuft:=OLD.facet_capacity_cuft;NEW.facet_fuel:=OLD.facet_fuel;NEW.image_url:=OLD.image_url;
   NEW.gallery_urls:=OLD.gallery_urls;NEW.spec_sheet_url:=OLD.spec_sheet_url;NEW.product_name:=OLD.product_name;
  END IF;
  RETURN NEW;
 END IF;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid;
 IF TG_OP='UPDATE' THEN
  -- Preserve complete website facts; fill only from the canonical PIM, never from a conflicting incoming value.
  NEW.description:=coalesce(nullif(btrim(OLD.description),''),nullif(t.long_description,''),nullif(t.short_description,''));
  NEW.specs:=tj_private.pim_web_fill_json(OLD.specs,t.specs_json);
  NEW.dimensions:=tj_private.pim_web_fill_json(OLD.dimensions,jsonb_strip_nulls(jsonb_build_object(
   'width_inches',CASE WHEN OLD.facet_width_in IS NULL THEN t.width_inches END,
   'height_inches',CASE WHEN OLD.facet_height_in IS NULL THEN t.height_inches END,
   'depth_inches',CASE WHEN OLD.facet_depth_in IS NULL THEN t.depth_inches END))); 
  NEW.finish:=coalesce(nullif(btrim(OLD.finish),''),t.finish);
  NEW.facet_width_in:=coalesce(OLD.facet_width_in,t.width_inches); NEW.facet_height_in:=coalesce(OLD.facet_height_in,t.height_inches);
  NEW.facet_depth_in:=coalesce(OLD.facet_depth_in,t.depth_inches); NEW.facet_capacity_cuft:=coalesce(OLD.facet_capacity_cuft,t.capacity_cu_ft);
  NEW.facet_fuel:=coalesce(OLD.facet_fuel,t.fuel_type); NEW.facet_finish:=coalesce(OLD.facet_finish,t.finish);
  IF nullif(btrim(OLD.image_url),'') IS NOT NULL THEN NEW.image_url:=OLD.image_url;
  ELSIF NEW.image_url !~* '^https://[^/@?#]+/[^?#]*\.(jpe?g|png|webp|avif|gif)([?#]|$)' THEN NEW.image_url:=NULL; END IF;
  SELECT array_agg(url ORDER BY first_pos) INTO NEW.gallery_urls FROM (
   SELECT url,min(pos) first_pos FROM unnest(coalesce(OLD.gallery_urls,ARRAY[]::text[])||coalesce(NEW.gallery_urls,ARRAY[]::text[])) WITH ORDINALITY a(url,pos)
   GROUP BY url) g;
  NEW.spec_sheet_url:=coalesce(nullif(btrim(OLD.spec_sheet_url),''),NEW.spec_sheet_url);
  NEW.product_name:=coalesce(nullif(btrim(OLD.product_name),''),NEW.product_name);
 END IF;
 RETURN NEW;
END $$;
