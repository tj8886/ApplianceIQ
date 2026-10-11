-- Incoming native scraper/enrichment writes are received by the PIM before catalog publication.
-- Existing known PIM and website facts are fill-only; conflicts remain in private feed receipts.
CREATE TABLE tj_private.pim_catalog_links (
 website_product_id uuid PRIMARY KEY REFERENCES public.products(id) DEFERRABLE INITIALLY DEFERRED,
 pim_product_id uuid NOT NULL REFERENCES tj.aiq_products(id),
 organization_id uuid NOT NULL REFERENCES tj.organizations(id), linked_at timestamptz NOT NULL DEFAULT now());
CREATE INDEX pim_catalog_links_pim_idx ON tj_private.pim_catalog_links(pim_product_id);
CREATE INDEX pim_catalog_links_org_idx ON tj_private.pim_catalog_links(organization_id);
CREATE TABLE tj_private.pim_feed_receipts (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, organization_id uuid NOT NULL REFERENCES tj.organizations(id),
 website_product_id uuid NOT NULL, pim_product_id uuid REFERENCES tj.aiq_products(id),
 kind text NOT NULL, source_date timestamptz, received_at timestamptz NOT NULL DEFAULT now(),
 payload jsonb NOT NULL, before_values jsonb, after_values jsonb, outcome text NOT NULL);
CREATE INDEX pim_feed_receipts_pim_idx ON tj_private.pim_feed_receipts(pim_product_id);
CREATE INDEX pim_feed_receipts_org_idx ON tj_private.pim_feed_receipts(organization_id);
CREATE INDEX pim_feed_receipts_native_idx ON tj_private.pim_feed_receipts(website_product_id,received_at DESC);
ALTER TABLE tj_private.pim_catalog_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj_private.pim_feed_receipts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.pim_catalog_links,tj_private.pim_feed_receipts FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE tj.pim_retailer_prices ADD COLUMN source_evidence jsonb;

CREATE OR REPLACE FUNCTION tj_private.pim_capture_catalog(p public.products,kind text,source_date timestamptz) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t tj.aiq_products; before_t tj.aiq_products; src jsonb; specs jsonb; cat text; u text; pid uuid;
BEGIN
 cat:=tj_private.pim_web_category(p.category);
 IF p.status IN ('hidden','archived') OR cat IS NULL OR public.brand_resolve(p.brand_name) IS NULL
 OR length(tj_private.pim_web_key(p.model_number))<3 OR p.model_number !~ '[0-9]' OR p.model_number !~ '[[:alpha:]]'
 OR p.model_number ~ '[,|/]' OR public.catalog_containment_reason(p.product_name,p.brand_name,p.category) IS NOT NULL
 OR tj_private.pim_web_part_description(coalesce(p.description,'')) THEN RETURN NULL; END IF;
 IF source_date>now()+interval '5 minutes' THEN RETURN NULL; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('pim-web:'||tj_private.pim_web_key(p.model_number),0));
 SELECT pim_product_id INTO pid FROM tj_private.pim_catalog_links WHERE website_product_id=p.id;
 IF pid IS NULL THEN
  SELECT s.id INTO pid FROM tj.aiq_products s WHERE s.status='active' AND s.approval_status='approved'
   AND s.is_parts_accessory IS FALSE AND tj_private.pim_web_category(s.category)=cat
   AND tj_private.pim_web_key(s.model)=tj_private.pim_web_key(p.model_number)
   AND public.brand_resolve(s.brand_name)=public.brand_resolve(p.brand_name)
   AND (s.market IS NOT DISTINCT FROM coalesce(p.market,'CA'))
   AND NOT tj_private.pim_web_part_description(coalesce(s.short_description,s.long_description,''))
  ORDER BY (s.source_review_status IN ('accepted','not_required')) DESC,
   greatest(s.updated_at,s.created_at,s.source_extracted_at) DESC,s.id LIMIT 1;
 END IF;
 -- A new master requires dated actual enrichment, not an undated/sample catalog seed.
 IF pid IS NULL AND source_date IS NOT NULL THEN
  INSERT INTO tj.aiq_products(brand_name,model,category,market,status,approval_status,source_type,source_reference,
   source_extracted_at,source_review_status,public_visible)
  VALUES(p.brand_name,p.model_number,cat,coalesce(p.market,'CA'),'active','approved','internal','native-catalog:'||p.id,
   source_date,'not_required',true) RETURNING id INTO pid;
 END IF;
 IF pid IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid FOR UPDATE;
 IF t.status<>'active' OR t.approval_status<>'approved' OR t.is_parts_accessory IS NOT FALSE THEN RETURN NULL; END IF;
 INSERT INTO tj_private.pim_catalog_links(website_product_id,pim_product_id,organization_id)
 VALUES(p.id,t.id,t.organization_id) ON CONFLICT(website_product_id) DO NOTHING;
 before_t:=t;
 src:=jsonb_build_object('description',p.description,'specs',p.specs,'dimensions',p.dimensions,'finish',p.finish,
 'facet_width_in',p.facet_width_in,'facet_height_in',p.facet_height_in,'facet_depth_in',p.facet_depth_in,
 'facet_capacity_cuft',p.facet_capacity_cuft,'facet_fuel',p.facet_fuel,'image_url',p.image_url,
 'gallery_urls',p.gallery_urls,'spec_sheet_url',p.spec_sheet_url,'source_url',p.spec_source_url);
 -- Preserve explicit PIM measurement/finish fields against contradictory JSON aliases.
 SELECT coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) INTO specs FROM jsonb_each(
  CASE WHEN jsonb_typeof(p.specs)='object' THEN p.specs ELSE '{}'::jsonb END) e
 WHERE NOT ((tj_private.pim_web_spec_key(e.key)='width' AND t.width_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='height' AND t.height_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='depth' AND t.depth_inches IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='capacity' AND t.capacity_cu_ft IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='finish' AND nullif(btrim(t.finish),'') IS NOT NULL)
 OR (tj_private.pim_web_spec_key(e.key)='fuel' AND nullif(btrim(t.fuel_type),'') IS NOT NULL));
 t.specs_json:=tj_private.pim_web_fill_json(t.specs_json,specs);
 IF nullif(btrim(t.long_description),'') IS NULL AND nullif(btrim(t.short_description),'') IS NULL
 THEN t.long_description:=nullif(btrim(p.description),''); END IF;
 t.finish:=coalesce(nullif(btrim(t.finish),''),nullif(btrim(p.finish),''));
 t.width_inches:=coalesce(t.width_inches,p.facet_width_in,CASE WHEN jsonb_typeof(p.dimensions->'width_inches')='number' THEN (p.dimensions->>'width_inches')::numeric END);
 t.height_inches:=coalesce(t.height_inches,p.facet_height_in,CASE WHEN jsonb_typeof(p.dimensions->'height_inches')='number' THEN (p.dimensions->>'height_inches')::numeric END);
 t.depth_inches:=coalesce(t.depth_inches,p.facet_depth_in,CASE WHEN jsonb_typeof(p.dimensions->'depth_inches')='number' THEN (p.dimensions->>'depth_inches')::numeric END);
 t.capacity_cu_ft:=coalesce(t.capacity_cu_ft,p.facet_capacity_cuft);
 t.fuel_type:=coalesce(nullif(btrim(t.fuel_type),''),nullif(btrim(p.facet_fuel),''));
 IF ROW(t.long_description,t.specs_json,t.finish,t.width_inches,t.height_inches,t.depth_inches,t.capacity_cu_ft,t.fuel_type)
 IS DISTINCT FROM ROW(before_t.long_description,before_t.specs_json,before_t.finish,before_t.width_inches,before_t.height_inches,before_t.depth_inches,before_t.capacity_cu_ft,before_t.fuel_type) THEN
  UPDATE tj.aiq_products SET long_description=t.long_description,specs_json=t.specs_json,finish=t.finish,
  width_inches=t.width_inches,height_inches=t.height_inches,depth_inches=t.depth_inches,capacity_cu_ft=t.capacity_cu_ft,
  fuel_type=t.fuel_type,updated_at=clock_timestamp(),source_extracted_at=greatest(source_extracted_at,source_date)
  WHERE id=t.id RETURNING * INTO t;
 END IF;
 FOR u IN SELECT DISTINCT x FROM unnest(coalesce(p.gallery_urls,ARRAY[]::text[])||ARRAY[p.image_url]) x
 WHERE x ~* '^https://[^/@?#]+/[^?#]*\.(jpe?g|png|webp|avif|gif)([?#]|$)' LOOP
  IF NOT EXISTS(SELECT 1 FROM tj.pim_product_images WHERE product_id=t.id AND coalesce(nullif(cdn_url,''),file_url)=u) THEN
   INSERT INTO tj.pim_product_images(product_id,file_url,source,approved,approved_at,audience_tiers,embargoed,created_at,updated_at)
   VALUES(t.id,u,'web_scrape',true,now(),ARRAY['public'],false,coalesce(source_date,now()),coalesce(source_date,now()));
  END IF;
 END LOOP;
 IF p.spec_sheet_url ~* '^https://[^/@?#]+/[^?#]*\.pdf([?#]|$)'
 AND NOT EXISTS(SELECT 1 FROM tj.pim_product_documents WHERE product_id=t.id AND file_url=p.spec_sheet_url) THEN
  INSERT INTO tj.pim_product_documents(product_id,file_url,doc_type,title,approved,is_current,requires_auth,embargoed,audience_tiers)
  VALUES(t.id,p.spec_sheet_url,'spec_sheet',p.brand_name||' '||p.model_number||' specifications',true,true,false,false,ARRAY['public']);
 END IF;
 INSERT INTO tj_private.pim_feed_receipts(organization_id,website_product_id,pim_product_id,kind,source_date,payload,before_values,after_values,outcome)
 VALUES(t.organization_id,p.id,t.id,kind,source_date,src,to_jsonb(before_t),to_jsonb(t),
 CASE WHEN before_t IS DISTINCT FROM t THEN 'filled_pim_blanks' ELSE 'retained_complete_pim' END);
 RETURN t.id;
END $$;

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
 pid:=tj_private.pim_capture_catalog(NEW,kind,observed);
 IF pid IS NULL THEN RETURN NEW; END IF;
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
CREATE TRIGGER aa_pim_catalog_incoming BEFORE INSERT OR UPDATE OF description,specs,dimensions,finish,facet_width_in,facet_height_in,
 facet_depth_in,facet_capacity_cuft,facet_fuel,image_url,gallery_urls,spec_sheet_url ON public.products
 FOR EACH ROW EXECUTE FUNCTION tj_private.pim_catalog_incoming_write();

CREATE OR REPLACE FUNCTION tj_private.pim_capture_price(o public.price_observations) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.products; pid uuid; t tj.aiq_products;
BEGIN
 IF o.product_id IS NULL OR o.observed_price IS NULL OR o.observed_price<0 OR o.last_checked_at IS NULL
 OR o.last_checked_at>now()+interval '5 minutes' OR o.currency NOT IN ('CAD','USD')
 OR o.source_url !~ '^https://[^/@?#]+([/?#]|$)' THEN RETURN NULL; END IF;
 SELECT * INTO p FROM public.products WHERE id=o.product_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT pim_product_id INTO pid FROM tj_private.pim_catalog_links WHERE website_product_id=p.id;
 IF pid IS NULL THEN pid:=tj_private.pim_capture_catalog(p,'dataseofor_product_link',NULL); END IF;
 IF pid IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid;
 IF coalesce(o.market,o.country) IS NOT NULL AND coalesce(o.market,o.country) IS DISTINCT FROM t.market THEN RETURN NULL; END IF;
 INSERT INTO tj.pim_retailer_prices(id,product_id,brand_name,model,retailer_name,retailer_url,product_url,price,price_currency,
 country,checked_at,created_at,first_seen_at,last_seen_at,condition_raw,source_evidence)
 VALUES(o.id,t.id,p.brand_name,p.model_number,o.retailer_name,o.retailer_domain,o.source_url,o.observed_price,o.currency,
 coalesce(o.country,o.market,t.market),o.last_checked_at,o.created_at,o.created_at,o.last_checked_at,o.condition,
 jsonb_build_object('origin','native_price_observation','observation_id',o.id,'source_id',o.source_id,
 'price_status',o.price_status,'public_display_status',o.public_display_status,'extraction_method',o.extraction_method,
 'price_confidence',o.price_confidence,'red_flags',o.red_flags))
 ON CONFLICT(id) DO UPDATE SET price=excluded.price,checked_at=excluded.checked_at,last_seen_at=excluded.last_seen_at,source_evidence=excluded.source_evidence
 WHERE tj.pim_retailer_prices.source_evidence->>'origin'='native_price_observation'
 AND excluded.checked_at>=tj.pim_retailer_prices.checked_at;
 RETURN pid;
END $$;
CREATE OR REPLACE FUNCTION tj_private.pim_price_incoming_write() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN PERFORM tj_private.pim_capture_price(NEW); RETURN NEW; END $$;
CREATE TRIGGER pim_price_incoming AFTER INSERT OR UPDATE ON public.price_observations FOR EACH ROW EXECUTE FUNCTION tj_private.pim_price_incoming_write();
REVOKE ALL ON FUNCTION tj_private.pim_capture_catalog(public.products,text,timestamptz),tj_private.pim_catalog_incoming_write(),
 tj_private.pim_capture_price(public.price_observations),tj_private.pim_price_incoming_write()
 FROM PUBLIC,anon,authenticated,service_role;
