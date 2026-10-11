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
 IF pid IS NULL AND EXISTS(SELECT 1 FROM tj.aiq_products s
 WHERE tj_private.pim_web_key(s.model)=tj_private.pim_web_key(p.model_number)
 AND public.brand_resolve(s.brand_name)=public.brand_resolve(p.brand_name)
 AND (s.is_parts_accessory IS TRUE OR tj_private.pim_web_part_description(coalesce(s.short_description,s.long_description,'')))) THEN RETURN NULL; END IF;
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

CREATE OR REPLACE FUNCTION tj_private.pim_capture_price(o public.price_observations) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.products; pid uuid; t tj.aiq_products; identity_p public.products;
BEGIN
 IF o.product_id IS NULL OR o.observed_price IS NULL OR o.observed_price<0 OR o.last_checked_at IS NULL
 OR o.last_checked_at>now()+interval '5 minutes' OR o.currency NOT IN ('CAD','USD')
 OR o.source_url !~ '^https://[^/@?#]+([/?#]|$)' THEN RETURN NULL; END IF;
 SELECT * INTO p FROM public.products WHERE id=o.product_id;
 IF NOT FOUND THEN RETURN NULL; END IF;
 IF (CASE upper(coalesce(o.country,o.market,'')) WHEN 'CA' THEN 'CA' WHEN 'CANADA' THEN 'CA' WHEN 'US' THEN 'US' WHEN 'USA' THEN 'US' WHEN 'UNITED STATES' THEN 'US' ELSE NULL END) IS DISTINCT FROM coalesce(p.market,'CA') THEN RETURN NULL; END IF;
 SELECT pim_product_id INTO pid FROM tj_private.pim_catalog_links WHERE website_product_id=p.id;

 IF pid IS NULL THEN
  identity_p:=p; identity_p.description:=NULL; identity_p.specs:='{}'; identity_p.dimensions:='{}';
  identity_p.finish:=NULL; identity_p.facet_width_in:=NULL; identity_p.facet_height_in:=NULL; identity_p.facet_depth_in:=NULL;
  identity_p.facet_capacity_cuft:=NULL; identity_p.facet_fuel:=NULL; identity_p.image_url:=NULL; identity_p.gallery_urls:=NULL; identity_p.spec_sheet_url:=NULL;
  pid:=tj_private.pim_capture_catalog(identity_p,'dated_price_identity',o.last_checked_at);
 END IF;
 IF pid IS NULL THEN RETURN NULL; END IF;
 SELECT * INTO t FROM tj.aiq_products WHERE id=pid;
 IF (CASE upper(coalesce(o.country,o.market,'')) WHEN 'CA' THEN 'CA' WHEN 'CANADA' THEN 'CA' WHEN 'US' THEN 'US' WHEN 'USA' THEN 'US' WHEN 'UNITED STATES' THEN 'US' ELSE NULL END) IS DISTINCT FROM t.market THEN RETURN NULL; END IF;
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
-- Explicit owner authorization covers active approved PIM appliances; pending source review is retained, not misrepresented as manufacturer verification.
CREATE OR REPLACE FUNCTION tj_private.pim_web_appliance(t tj.aiq_products) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT coalesce(t.status='active' AND t.approval_status='approved'
 AND t.source_review_status IN ('accepted','not_required','approved','pending','pending_review') AND t.is_parts_accessory IS FALSE
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

CREATE TABLE tj_private.pim_incoming_reconcile_queue (
 kind text NOT NULL CHECK(kind IN ('catalog','price')), object_id uuid NOT NULL,
 organization_id uuid NOT NULL DEFAULT '00000000-0000-0000-0000-000000000002' REFERENCES tj.organizations(id),
 source_date timestamptz,queued_at timestamptz NOT NULL DEFAULT now(),processed_at timestamptz,
 outcome text,attempts integer NOT NULL DEFAULT 0,last_error text,PRIMARY KEY(kind,object_id));
CREATE INDEX pim_incoming_reconcile_org_idx ON tj_private.pim_incoming_reconcile_queue(organization_id);
ALTER TABLE tj_private.pim_incoming_reconcile_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.pim_incoming_reconcile_queue FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION tj_private.pim_enqueue_daily_intake() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE n integer; m integer;
BEGIN
 INSERT INTO tj_private.pim_incoming_reconcile_queue(kind,object_id,source_date)
 SELECT 'catalog',id,greatest(CASE WHEN manufacturer_status='enriched' THEN manufacturer_enriched_at END,
 CASE WHEN icecat_status='enriched' THEN icecat_enriched_at END)
 FROM public.products WHERE status='active' AND ((manufacturer_status='enriched' AND manufacturer_enriched_at IS NOT NULL)
 OR (icecat_status='enriched' AND icecat_enriched_at IS NOT NULL))
 ON CONFLICT(kind,object_id) DO UPDATE SET source_date=excluded.source_date,processed_at=NULL,outcome=NULL,attempts=0,last_error=NULL,queued_at=clock_timestamp()
 WHERE excluded.source_date>tj_private.pim_incoming_reconcile_queue.source_date;
 GET DIAGNOSTICS n=ROW_COUNT;
 INSERT INTO tj_private.pim_incoming_reconcile_queue(kind,object_id,source_date)
 SELECT 'price',id,last_checked_at FROM public.price_observations WHERE last_checked_at>now()-interval '24 hours'
 AND last_checked_at<=now()+interval '5 minutes'
 ON CONFLICT(kind,object_id) DO UPDATE SET source_date=excluded.source_date,processed_at=NULL,outcome=NULL,attempts=0,last_error=NULL,queued_at=clock_timestamp()
 WHERE excluded.source_date>tj_private.pim_incoming_reconcile_queue.source_date;
 GET DIAGNOSTICS m=ROW_COUNT;
 RETURN n+m;
END $$;
CREATE OR REPLACE FUNCTION tj_private.pim_incoming_reconcile_batch(batch_size integer DEFAULT 250) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q record; p public.products; o public.price_observations; pid uuid; label text; stats jsonb:='{}'; deadline timestamptz:=clock_timestamp()+interval '20 seconds';
BEGIN
 IF batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid_batch_size'; END IF;
 FOR q IN SELECT * FROM tj_private.pim_incoming_reconcile_queue WHERE processed_at IS NULL AND attempts<5
 ORDER BY queued_at,kind,object_id LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  EXIT WHEN clock_timestamp()>deadline;
  BEGIN
   pid:=NULL;
   IF q.kind='catalog' THEN
    SELECT * INTO p FROM public.products WHERE id=q.object_id;
    IF FOUND THEN pid:=tj_private.pim_capture_catalog(p,'dated_catalog_reconciliation',q.source_date); END IF;
   ELSE
    SELECT * INTO o FROM public.price_observations WHERE id=q.object_id;
    IF FOUND THEN pid:=tj_private.pim_capture_price(o); END IF;
   END IF;
   label:=CASE WHEN pid IS NOT NULL THEN 'captured_in_pim' ELSE 'held_identity_or_source' END;
   UPDATE tj_private.pim_incoming_reconcile_queue SET processed_at=clock_timestamp(),outcome=label,attempts=0,last_error=NULL WHERE kind=q.kind AND object_id=q.object_id;
  EXCEPTION WHEN OTHERS THEN
   label:='error'; UPDATE tj_private.pim_incoming_reconcile_queue SET attempts=attempts+1,last_error=SQLSTATE||':'||SQLERRM WHERE kind=q.kind AND object_id=q.object_id;
  END;
  stats:=jsonb_set(stats,ARRAY[label],to_jsonb(coalesce((stats->>label)::int,0)+1));
 END LOOP;
 RETURN stats;
END $$;
REVOKE ALL ON FUNCTION tj_private.pim_enqueue_daily_intake(),tj_private.pim_incoming_reconcile_batch(integer)
 FROM PUBLIC,anon,authenticated,service_role;
SELECT tj_private.pim_enqueue_daily_intake();
SELECT cron.schedule('applianceiq-pim-incoming-reconcile','* * * * *',$job$SELECT tj_private.pim_incoming_reconcile_batch(250);$job$);
SELECT cron.schedule('applianceiq-pim-daily-catchup','15 5 * * *',$job$SELECT tj_private.pim_enqueue_daily_intake();$job$);
-- Another pass over active approved sources, using owner authorization, never overwriting completed facts.
INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id)
 SELECT t.id,t.organization_id FROM tj.aiq_products t WHERE tj_private.pim_web_appliance(t)
 ON CONFLICT(pim_product_id) DO UPDATE SET processed_at=NULL,last_error=NULL,attempts=0,queued_at=clock_timestamp();
