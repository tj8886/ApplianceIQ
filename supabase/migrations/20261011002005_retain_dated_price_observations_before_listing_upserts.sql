ALTER TABLE tj.pim_price_history ADD COLUMN source_observation_id uuid,
 ADD COLUMN observed_price numeric,ADD COLUMN retailer_name text,ADD COLUMN source_evidence jsonb;
CREATE UNIQUE INDEX pim_price_history_observation_version_idx ON tj.pim_price_history(source_observation_id,checked_at,observed_price)
 WHERE source_observation_id IS NOT NULL;
CREATE OR REPLACE FUNCTION tj_private.pim_capture_price(o public.price_observations) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE p public.products; pid uuid; t tj.aiq_products; identity_p public.products; cond public.listing_condition; existing tj.pim_retailer_prices; n integer; evidence jsonb;
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

 evidence:=jsonb_build_object('origin','native_price_observation','observation_id',o.id,'source_id',o.source_id,
 'price_status',o.price_status,'public_display_status',o.public_display_status,'extraction_method',o.extraction_method,
 'price_confidence',o.price_confidence,'red_flags',o.red_flags,'source_url',o.source_url);
 INSERT INTO tj.pim_price_history(product_id,price_currency,source_url,checked_at,created_at,source_observation_id,
 observed_price,retailer_name,source_evidence)
 VALUES(t.id,o.currency,o.source_url,o.last_checked_at,o.created_at,o.id,o.observed_price,o.retailer_name,evidence)
 ON CONFLICT(source_observation_id,checked_at,observed_price) WHERE source_observation_id IS NOT NULL
 DO UPDATE SET source_evidence=excluded.source_evidence;
 cond:=CASE lower(coalesce(o.condition,'')) WHEN 'new' THEN 'new' WHEN 'sale' THEN 'sale'
 WHEN 'open_box' THEN 'open_box' WHEN 'open box' THEN 'open_box' WHEN 'refurbished' THEN 'refurbished'
 WHEN 'floor_model' THEN 'floor_model' WHEN 'floor model' THEN 'floor_model' WHEN 'scratch_dent' THEN 'scratch_dent'
 WHEN 'scratch and dent' THEN 'scratch_dent' WHEN 'clearance' THEN 'clearance' WHEN 'end_of_life' THEN 'end_of_life'
 WHEN 'returned' THEN 'returned' WHEN 'discontinued' THEN 'discontinued' WHEN 'used' THEN 'used' WHEN 'as_is' THEN 'as_is' END;
 IF cond IS NULL OR nullif(btrim(o.retailer_name),'') IS NULL THEN RETURN pid; END IF;
 SELECT count(*) INTO n FROM tj.pim_retailer_prices r WHERE (r.product_url=o.source_url AND r.condition_normalized=cond)
 OR (r.brand_name=p.brand_name AND r.model=p.model_number AND r.retailer_name=o.retailer_name AND r.condition_normalized=cond AND r.country=t.market);
 IF n>1 THEN RETURN pid; END IF;
 SELECT * INTO existing FROM tj.pim_retailer_prices r WHERE (r.product_url=o.source_url AND r.condition_normalized=cond)
 OR (r.brand_name=p.brand_name AND r.model=p.model_number AND r.retailer_name=o.retailer_name AND r.condition_normalized=cond AND r.country=t.market)
 LIMIT 1 FOR UPDATE;
 IF FOUND THEN
  IF (existing.product_id IS NOT NULL AND existing.product_id<>t.id) OR existing.checked_at>o.last_checked_at THEN RETURN pid; END IF;
  -- Unknown/blocked observations stay in PIM history; they cannot replace an existing curated retailer listing.
  IF existing.source_evidence IS NULL AND o.public_display_status<>'eligible' THEN RETURN pid; END IF;
  UPDATE tj.pim_retailer_prices SET product_id=t.id,price=o.observed_price,price_currency=o.currency,
   checked_at=o.last_checked_at,last_seen_at=o.last_checked_at,source_evidence=evidence
  WHERE id=existing.id;
 ELSE
  INSERT INTO tj.pim_retailer_prices(id,product_id,brand_name,model,retailer_name,retailer_url,product_url,price,price_currency,
   country,checked_at,created_at,first_seen_at,last_seen_at,condition_raw,condition_normalized,source_evidence)
  VALUES(o.id,t.id,p.brand_name,p.model_number,o.retailer_name,o.retailer_domain,o.source_url,o.observed_price,o.currency,
   t.market,o.last_checked_at,o.created_at,o.created_at,o.last_checked_at,o.condition,cond,evidence)
  ON CONFLICT DO NOTHING;
 END IF;
 RETURN pid;
END $$;
