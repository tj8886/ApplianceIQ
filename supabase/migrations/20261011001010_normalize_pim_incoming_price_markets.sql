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
