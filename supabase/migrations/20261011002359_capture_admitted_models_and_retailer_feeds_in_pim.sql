
-- Admission runs first; PIM identity creation is atomic with a successful native discovery INSERT.
CREATE OR REPLACE FUNCTION tj_private.pim_admitted_model_capture() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NEW.source_metadata->>'pim_completion_mode'='fill_blanks_only' THEN RETURN NEW; END IF;
 PERFORM tj_private.pim_capture_catalog(NEW,'admitted_native_model',NEW.created_at);
 RETURN NEW;
END $$;
CREATE TRIGGER pim_admitted_model_capture AFTER INSERT ON public.products FOR EACH ROW EXECUTE FUNCTION tj_private.pim_admitted_model_capture();
-- Actual retailer feed records are captured as dated observations, preserving sample/unverified states.
CREATE OR REPLACE FUNCTION tj_private.pim_retailer_feed_capture() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE o public.price_observations; pid uuid;
BEGIN
 IF NEW.last_checked_at IS NULL OR coalesce(NEW.sale_price,NEW.store_listed_price) IS NULL OR NEW.listing_url NOT LIKE 'https://%' THEN RETURN NEW; END IF;
 o.id:=NEW.id;o.product_id:=NEW.product_id;o.source_id:=NEW.data_source_id;o.offer_id:=NEW.id;
 SELECT name INTO o.retailer_name FROM public.stores WHERE id=NEW.store_id;
 o.source_url:=NEW.listing_url;o.country:=coalesce(NEW.country,NEW.retailer_country,NEW.store_country);
 o.market:=NEW.market;o.currency:=NEW.currency;o.observed_price:=coalesce(NEW.sale_price,NEW.store_listed_price);
 o.condition:=NEW.condition;o.created_at:=NEW.created_at;o.last_checked_at:=NEW.last_checked_at;
 o.extraction_method:='retailer_feed';o.price_status:='observed_internal';o.public_display_status:='blocked';
 pid:=tj_private.pim_capture_price(o);
 IF pid IS NOT NULL THEN
  UPDATE tj.pim_price_history SET source_evidence=source_evidence||jsonb_build_object('origin','native_store_offer',
   'store_offer_id',NEW.id,'offer_data_status',NEW.data_status,'listing_url_status',NEW.listing_url_status)
  WHERE source_observation_id=NEW.id AND checked_at=NEW.last_checked_at;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER pim_retailer_feed_capture AFTER INSERT OR UPDATE ON public.store_offers FOR EACH ROW EXECUTE FUNCTION tj_private.pim_retailer_feed_capture();
REVOKE ALL ON FUNCTION tj_private.pim_admitted_model_capture(),tj_private.pim_retailer_feed_capture()
 FROM PUBLIC,anon,authenticated,service_role;
