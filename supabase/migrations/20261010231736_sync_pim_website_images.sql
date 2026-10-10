-- ApplianceIQ.ai PIM completion: fill blanks, retain sourced values, exclude parts.
-- User authorization October 10 2026. No source records/files are deleted.
CREATE OR REPLACE FUNCTION tj_private.pim_web_key(v text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT lower(regexp_replace(coalesce(v,''),'[^a-zA-Z0-9]','','g'))
$$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_spec_key(v text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE tj_private.pim_web_key(v)
 WHEN 'widthinches' THEN 'width' WHEN 'widthin' THEN 'width'
 WHEN 'heightinches' THEN 'height' WHEN 'heightin' THEN 'height'
 WHEN 'depthinches' THEN 'depth' WHEN 'depthin' THEN 'depth'
 WHEN 'capacitycuft' THEN 'capacity' WHEN 'totalcapacitycuft' THEN 'capacity'
 WHEN 'capacitycufttotal' THEN 'capacity' WHEN 'energy starqualified' THEN 'energystar'
 WHEN 'energystarqualified' THEN 'energystar' WHEN 'energystarcertified' THEN 'energystar'
 ELSE tj_private.pim_web_key(v) END
$$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_blank(v jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT v IS NULL OR v IN ('null'::jsonb,'""'::jsonb,'{}'::jsonb,'[]'::jsonb)
 OR (jsonb_typeof(v)='string' AND btrim(v#>>'{}')='')
$$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_fill_json(existing jsonb,incoming jsonb) RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE SET search_path='' AS $$
DECLARE result jsonb:=coalesce(existing,'{}'::jsonb); k text; v jsonb; actual_key text;
BEGIN
 IF jsonb_typeof(incoming) IS DISTINCT FROM 'object' THEN RETURN result; END IF;
 IF jsonb_typeof(result) IS DISTINCT FROM 'object' THEN RETURN result; END IF;
 FOR k,v IN SELECT * FROM jsonb_each(incoming) LOOP
  IF tj_private.pim_web_blank(v) OR length(v::text)>16000 OR
    tj_private.pim_web_key(k) ~ '(dealercost|wholesale|margin|organization|token|secret|apikey|password|internal|price|cost)' THEN CONTINUE; END IF;
  SELECT e.key INTO actual_key FROM jsonb_each(result) e
   WHERE tj_private.pim_web_spec_key(e.key)=tj_private.pim_web_spec_key(k)
   ORDER BY (e.key=k) DESC,e.key LIMIT 1;
  IF actual_key IS NULL THEN result:=result||jsonb_build_object(k,v);
  ELSIF tj_private.pim_web_blank(result->actual_key) THEN result:=result||jsonb_build_object(actual_key,v);
  ELSIF jsonb_typeof(result->actual_key)='object' AND jsonb_typeof(v)='object' THEN
   result:=result||jsonb_build_object(actual_key,tj_private.pim_web_fill_json(result->actual_key,v));
  END IF;
 END LOOP;
 RETURN result;
END $$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_category(raw text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE WHEN lower(btrim(coalesce(raw,''))) IN
 ('blower','warming-drawer','warming drawers') OR raw ~* '(accessor|parts|cookware|filter|kit)'
 THEN NULL ELSE public.tj_map_category(raw) END
$$;
CREATE OR REPLACE FUNCTION tj_private.pim_web_appliance(t tj.aiq_products) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT coalesce(t.status='active' AND t.approval_status='approved'
 AND t.source_review_status IN ('accepted','not_required') AND t.is_parts_accessory IS FALSE
 AND tj_private.pim_web_category(t.category) IS NOT NULL
 AND t.model ~ '[[:alpha:]]' AND t.model ~ '[0-9]' AND length(t.model) BETWEEN 3 AND 60
 AND t.model !~ '[,|/]' AND t.brand_name IS NOT NULL
 AND length(tj_private.pim_web_key(t.model))>=3
 AND coalesce(t.short_description,'') !~* '^\s*(this\s+|replacement\s+|genuine\s+|universal\s+|original\s+|the\s+)?(water\s+filter|filter\s+(kit|cartridge)|trim\s+kit|stacking\s+kit|replacement\s+(part|filter)|installation\s+kit|hose|pedestal|burner\s+cap|handle\s+kit)\M'
 AND coalesce(t.product_line,'') !~* '(accessor|replacement part|filter kit)'
 AND coalesce(t.product_segment,'') !~* '(accessor|parts)'
 AND EXISTS(SELECT 1 FROM public.brand_canonical b WHERE b.id=public.brand_resolve(t.brand_name) AND b.is_active)
 AND greatest(t.created_at,t.updated_at,t.source_extracted_at)<=now()+interval '5 minutes',false)
$$;
CREATE INDEX pim_web_products_model_lookup ON public.products ((tj_private.pim_web_key(model_number)));
CREATE INDEX pim_web_source_model_lookup ON tj.aiq_products ((tj_private.pim_web_key(model)));
CREATE TABLE tj_private.pim_web_completion_queue(
 pim_product_id uuid PRIMARY KEY, organization_id uuid,
 queued_at timestamptz NOT NULL DEFAULT clock_timestamp(), processed_at timestamptz,
 attempts integer NOT NULL DEFAULT 0, last_error text
);
CREATE TABLE tj_private.pim_web_completion_log(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, organization_id uuid,
 pim_product_id uuid NOT NULL, website_product_id uuid,
 source_updated_at timestamptz, action text NOT NULL,
 before_values jsonb, after_values jsonb, detail jsonb NOT NULL DEFAULT '{}',
 captured_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX pim_web_log_product ON tj_private.pim_web_completion_log(pim_product_id,captured_at DESC);
CREATE INDEX pim_web_log_website ON tj_private.pim_web_completion_log(website_product_id);
CREATE INDEX pim_web_queue_pending ON tj_private.pim_web_completion_queue(queued_at) WHERE processed_at IS NULL;
ALTER TABLE tj_private.pim_web_completion_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj_private.pim_web_completion_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj_private.pim_web_completion_queue,tj_private.pim_web_completion_log FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_product(source_id uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE t tj.aiq_products; p public.products; before_p public.products;
 category text; canonical_brand uuid; model_key text; n integer; candidate uuid;
 src_date timestamptz; new_record boolean:=false; description text; url text;
 spec_url text; merged jsonb; dims jsonb; image_candidates integer; action text;
 price_snapshot jsonb; image_urls jsonb; identity_row record; result jsonb;
BEGIN
 SELECT * INTO t FROM tj.aiq_products WHERE id=source_id;
 IF NOT FOUND OR NOT tj_private.pim_web_appliance(t) THEN RETURN jsonb_build_object('action','excluded'); END IF;
 canonical_brand:=public.brand_resolve(t.brand_name); model_key:=tj_private.pim_web_key(t.model);
 category:=tj_private.pim_web_category(t.category);
 PERFORM pg_advisory_xact_lock(hashtextextended('pim-web:'||model_key,0));
 SELECT * INTO identity_row FROM public.pim_identity_current ic WHERE ic.source_id=t.id;
 IF FOUND AND identity_row.decision<>'approved' THEN RETURN jsonb_build_object('action','identity_review'); END IF;
 SELECT count(*),(array_agg(id))[1] INTO n,candidate FROM public.products
 WHERE tj_private.pim_web_key(model_number)=model_key
 AND coalesce(brand_canonical_id,public.brand_resolve(brand_name))=canonical_brand
 AND (market IS NULL OR t.market IS NULL OR market=t.market);
 IF n>1 THEN RETURN jsonb_build_object('action','ambiguous'); END IF;
 IF n=0 AND EXISTS(SELECT 1 FROM public.products WHERE tj_private.pim_web_key(model_number)=model_key
  OR normalized_model_number=upper(model_key)) THEN RETURN jsonb_build_object('action','brand_or_market_collision'); END IF;
 IF identity_row.target_product_id IS NOT NULL AND identity_row.target_product_id IS DISTINCT FROM candidate THEN
  RETURN jsonb_build_object('action','identity_collision'); END IF;
 -- Newest eligible source for this exact brand/model/market wins; older copies do not fill conflicting blanks.
 SELECT s.* INTO t FROM tj.aiq_products s WHERE tj_private.pim_web_key(s.model)=model_key
 AND public.brand_resolve(s.brand_name)=canonical_brand AND tj_private.pim_web_appliance(s)
 AND (s.market IS NOT DISTINCT FROM t.market)
 ORDER BY greatest(s.updated_at,s.created_at,s.source_extracted_at) DESC,s.id LIMIT 1;
 src_date:=greatest(t.updated_at,t.created_at,t.source_extracted_at);
 IF n=0 THEN
  INSERT INTO public.products(slug,brand_name,brand_canonical_id,model_number,normalized_model_number,
   product_name,category,status,match_status,data_status,market,country,source_metadata)
  VALUES(lower(regexp_replace(t.brand_name||'-'||t.model||'-'||public.tj_admission_category_noun(category),'[^a-zA-Z0-9]+','-','g')),
   t.brand_name,canonical_brand,t.model,upper(model_key),
   t.brand_name||' '||t.model||' '||replace(public.tj_admission_category_noun(category),'-',' '),
   category,'active','auto_matched','unverified',t.market,t.market,
   jsonb_build_object('importType','approved_admin_import','pim_source_id',t.id,'pim_source_updated_at',src_date,
    'pim_completion_mode','fill_blanks_only','sourceType','approved_admin_import')) RETURNING * INTO p;
  IF p.id IS NULL THEN RETURN jsonb_build_object('action','admission_refused'); END IF;
  candidate:=p.id; new_record:=true;
 ELSE
  SELECT * INTO p FROM public.products WHERE id=candidate FOR UPDATE;
  IF p.status IN ('hidden','archived') THEN RETURN jsonb_build_object('action','website_withdrawn'); END IF;
  IF p.category IS DISTINCT FROM category THEN RETURN jsonb_build_object('action','category_collision'); END IF;
 END IF;
 before_p:=p;
 description:=nullif(btrim(regexp_replace(coalesce(nullif(t.long_description,''),t.short_description),'<[^>]*>','','g')),'');
 IF length(description)<20 OR length(description)>16000 THEN description:=NULL; END IF;
 IF nullif(btrim(p.description),'') IS NULL AND description IS NOT NULL THEN p.description:=description; END IF;
 merged:=tj_private.pim_web_fill_json(p.specs,t.specs_json); p.specs:=merged;
 -- Explicit typed measurements only, retaining any existing scalar or equivalent JSON value.
 dims:=tj_private.pim_web_fill_json(p.dimensions,jsonb_strip_nulls(jsonb_build_object(
  'width_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='width' AND NOT tj_private.pim_web_blank(e.value)) AND t.width_inches BETWEEN 1 AND 100 THEN t.width_inches END,
  'height_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='height' AND NOT tj_private.pim_web_blank(e.value)) AND t.height_inches>0 AND t.height_inches<=100 THEN t.height_inches END,
  'depth_inches',CASE WHEN NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='depth' AND NOT tj_private.pim_web_blank(e.value)) AND t.depth_inches>0 AND t.depth_inches<=100 THEN t.depth_inches END)));
 p.dimensions:=dims;
 IF nullif(btrim(p.finish),'') IS NULL THEN p.finish:=nullif(btrim(t.finish),''); END IF;
 IF p.facet_finish IS NULL THEN p.facet_finish:=coalesce(p.finish,nullif(btrim(t.finish),'')); END IF;
 IF p.facet_width_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')||coalesce(before_p.dimensions,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='width' AND NOT tj_private.pim_web_blank(e.value)) AND t.width_inches BETWEEN
  (CASE category WHEN 'dishwashers' THEN 17.5 WHEN 'washers' THEN 23 WHEN 'dryers' THEN 23
   WHEN 'laundry' THEN 23 WHEN 'refrigerators' THEN 14 WHEN 'freezers' THEN 11 WHEN 'ranges' THEN 20
   WHEN 'cooktops' THEN 15 WHEN 'wall-ovens' THEN 20 ELSE 11 END)
  AND (CASE category WHEN 'dishwashers' THEN 25 WHEN 'washers' THEN 30 WHEN 'dryers' THEN 30
   WHEN 'laundry' THEN 30 WHEN 'freezers' THEN 73.25 ELSE 48 END) THEN p.facet_width_in:=t.width_inches; END IF;
 IF p.facet_height_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')||coalesce(before_p.dimensions,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='height' AND NOT tj_private.pim_web_blank(e.value)) AND t.height_inches>0 AND t.height_inches<=84 THEN p.facet_height_in:=t.height_inches; END IF;
 IF p.facet_depth_in IS NULL AND NOT EXISTS(SELECT 1 FROM jsonb_each(coalesce(before_p.specs,'{}')||coalesce(before_p.dimensions,'{}')) e WHERE tj_private.pim_web_spec_key(e.key)='depth' AND NOT tj_private.pim_web_blank(e.value)) AND t.depth_inches BETWEEN (CASE category WHEN 'ventilation' THEN 2.75 ELSE 5 END) AND 40 THEN p.facet_depth_in:=t.depth_inches; END IF;
 IF p.facet_capacity_cuft IS NULL AND category<>'dishwashers' AND t.capacity_cu_ft BETWEEN 0.5 AND 35 THEN p.facet_capacity_cuft:=t.capacity_cu_ft; END IF;
 IF p.facet_fuel IS NULL THEN p.facet_fuel:=CASE lower(t.fuel_type)
  WHEN 'gas' THEN 'Gas' WHEN 'electric' THEN 'Electric' WHEN 'induction' THEN 'Induction'
  WHEN 'dual fuel' THEN 'Dual Fuel' WHEN 'dual-fuel' THEN 'Dual Fuel' WHEN 'heat pump' THEN 'Heat Pump' END; END IF;
 -- Do not turn default false booleans or MSRP into claimed verified facts/current offers.
 SELECT count(*) INTO image_candidates FROM tj.pim_product_images WHERE product_id=t.id;
 SELECT jsonb_agg(eligible.url ORDER BY eligible.updated_at DESC,eligible.is_primary DESC NULLS LAST,eligible.id)
 INTO image_urls FROM (
  SELECT DISTINCT ON(coalesce(nullif(i.cdn_url,''),i.file_url)) i.id,
   coalesce(nullif(i.cdn_url,''),i.file_url) url,i.updated_at,i.is_primary
  FROM tj.pim_product_images i
  WHERE i.product_id=t.id AND i.approved AND NOT coalesce(i.embargoed,true)
   AND (i.available_from IS NULL OR i.available_from<=now()) AND (i.available_until IS NULL OR i.available_until>now())
   AND (i.audience_tiers && ARRAY['public','all']) AND coalesce(cardinality(i.exclusive_codes),0)=0
   AND coalesce(nullif(i.cdn_url,''),i.file_url) ~ '^https://[^/@?#]+([/?#]|$)'
   AND EXISTS(SELECT 1 FROM public.product_images native
    JOIN public.media_rights_source rs ON rs.id=native.rights_source_id
    WHERE native.product_id=candidate AND native.url=coalesce(nullif(i.cdn_url,''),i.file_url)
     AND native.status='active' AND native.permission_status IN ('approved','partner_provided','licensed')
     AND native.rights_override IS NULL AND public.media_rights_effective(rs.grant_id,'applianceiq',coalesce(p.market,'CA'),now()))
   AND EXISTS(SELECT 1 FROM public.image_audit_results a WHERE a.product_id=candidate
    AND a.url=coalesce(nullif(i.cdn_url,''),i.file_url) AND a.decode_ok AND a.fetch_status=200
    AND a.content_type LIKE 'image/%' AND a.audited_at>=coalesce(i.updated_at,i.created_at))
  ORDER BY coalesce(nullif(i.cdn_url,''),i.file_url),i.updated_at DESC,i.id
 ) eligible;
 IF nullif(btrim(p.image_url),'') IS NULL AND jsonb_array_length(coalesce(image_urls,'[]'))>0 THEN p.image_url:=image_urls->>0; END IF;
 IF coalesce(cardinality(p.gallery_urls),0)=0 AND jsonb_array_length(coalesce(image_urls,'[]'))>0 THEN SELECT array_agg(x) INTO p.gallery_urls FROM jsonb_array_elements_text(image_urls) x; END IF;
 SELECT d.file_url INTO spec_url FROM tj.pim_product_documents d WHERE d.product_id=t.id
 AND d.doc_type IN ('spec_sheet','specification','specifications') AND d.approved AND d.is_current
 AND NOT coalesce(d.requires_auth,true) AND NOT coalesce(d.embargoed,true)
 AND (d.effective_date IS NULL OR d.effective_date<=current_date) AND (d.expiry_date IS NULL OR d.expiry_date>=current_date)
 AND (d.available_from IS NULL OR d.available_from<=now()) AND (d.available_until IS NULL OR d.available_until>now())
 AND d.audience_tiers && ARRAY['public','all'] AND coalesce(cardinality(d.exclusive_codes),0)=0
 AND d.file_url ~ '^https://[^/@?#]+([/?#]|$)' ORDER BY d.updated_at DESC,d.id LIMIT 1;
 IF nullif(btrim(p.spec_sheet_url),'') IS NULL THEN p.spec_sheet_url:=spec_url; END IF;
 INSERT INTO public.tj_listing_import(tj_listing_id,tj_product_id,brand_name,model,retailer_name,product_url,retailer_url,
 price,regular_price,on_sale,in_stock,condition_raw,listing_status,price_currency,country,checked_at,first_seen_at,last_seen_at,
 retailer_sku,matched_product_id,match_method)
 SELECT r.id,r.product_id,r.brand_name,r.model,r.retailer_name,r.product_url,r.retailer_url,
 r.price,r.regular_price,r.on_sale,r.in_stock,r.condition_raw,r.listing_status::text,r.price_currency,r.country,
 r.checked_at,r.first_seen_at,r.last_seen_at,r.retailer_sku,candidate,'pim_fill_only_exact_brand_model'
 FROM tj.pim_retailer_prices r WHERE r.product_id=t.id
 AND tj_private.pim_web_key(r.model)=model_key AND public.brand_resolve(r.brand_name)=canonical_brand
 ON CONFLICT(tj_listing_id) DO UPDATE SET matched_product_id=excluded.matched_product_id,match_method=excluded.match_method
 WHERE public.tj_listing_import.matched_product_id IS NULL;
 -- Current prices are not synthesized from undated MSRP or stale observations.
 -- Audit before/after captures only the columns this writer owns. Existing source, trust and prices remain unchanged.
 result:=jsonb_build_object('description',p.description,'specs',p.specs,'dimensions',p.dimensions,
 'finish',p.finish,'facet_finish',p.facet_finish,'facet_width_in',p.facet_width_in,'facet_height_in',p.facet_height_in,
 'facet_depth_in',p.facet_depth_in,'facet_capacity_cuft',p.facet_capacity_cuft,'facet_fuel',p.facet_fuel,
 'image_url',p.image_url,'gallery_urls',p.gallery_urls,'spec_sheet_url',p.spec_sheet_url);
 IF result IS DISTINCT FROM jsonb_build_object('description',before_p.description,'specs',before_p.specs,'dimensions',before_p.dimensions,
 'finish',before_p.finish,'facet_finish',before_p.facet_finish,'facet_width_in',before_p.facet_width_in,'facet_height_in',before_p.facet_height_in,
 'facet_depth_in',before_p.facet_depth_in,'facet_capacity_cuft',before_p.facet_capacity_cuft,'facet_fuel',before_p.facet_fuel,
 'image_url',before_p.image_url,'gallery_urls',before_p.gallery_urls,'spec_sheet_url',before_p.spec_sheet_url) THEN
 UPDATE public.products SET description=p.description,specs=p.specs,dimensions=p.dimensions,finish=p.finish,
 facet_finish=p.facet_finish,facet_width_in=p.facet_width_in,facet_height_in=p.facet_height_in,
 facet_depth_in=p.facet_depth_in,facet_capacity_cuft=p.facet_capacity_cuft,facet_fuel=p.facet_fuel,
 image_url=p.image_url,gallery_urls=p.gallery_urls,spec_sheet_url=p.spec_sheet_url,
 write_source='pim_catalog_completion' WHERE id=candidate RETURNING * INTO p;
 action:=CASE WHEN new_record THEN 'created' ELSE 'filled_blanks' END;
 ELSE action:=CASE WHEN new_record THEN 'created' ELSE 'already_complete' END; END IF;
 IF action<>'already_complete' THEN
 INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
 VALUES(t.organization_id,t.id,candidate,src_date,action,to_jsonb(before_p),to_jsonb(p),
 jsonb_build_object('saved_image_records',image_candidates,'eligible_image_records',jsonb_array_length(coalesce(image_urls,'[]')),
 'source_type',t.source_type,'source_reference',t.source_reference,'pricing','dated historical listings retained; no price refresh fabricated'));
 END IF;
 RETURN jsonb_build_object('action',action,'website_product_id',candidate,'pim_product_id',t.id);
END $$;

CREATE OR REPLACE FUNCTION tj_private.pim_web_queue_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE k uuid; org uuid;
BEGIN
 IF TG_TABLE_NAME='aiq_products' THEN k:=CASE WHEN TG_OP='DELETE' THEN OLD.id ELSE NEW.id END;
 ELSE k:=CASE WHEN TG_OP='DELETE' THEN OLD.product_id ELSE NEW.product_id END; END IF;
 SELECT organization_id INTO org FROM tj.aiq_products WHERE id=k;
 INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id) VALUES(k,org)
 ON CONFLICT(pim_product_id) DO UPDATE SET queued_at=clock_timestamp(),processed_at=NULL,last_error=NULL;
 IF TG_TABLE_NAME<>'aiq_products' AND TG_OP='UPDATE' THEN
 IF OLD.product_id IS DISTINCT FROM NEW.product_id THEN
  INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id)
  SELECT OLD.product_id,organization_id FROM tj.aiq_products WHERE id=OLD.product_id
  ON CONFLICT(pim_product_id) DO UPDATE SET queued_at=clock_timestamp(),processed_at=NULL;
 END IF;
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER pim_web_product_change AFTER INSERT OR UPDATE OR DELETE ON tj.aiq_products
 FOR EACH ROW EXECUTE FUNCTION tj_private.pim_web_queue_change();
CREATE TRIGGER pim_web_image_change AFTER INSERT OR UPDATE OR DELETE ON tj.pim_product_images
 FOR EACH ROW EXECUTE FUNCTION tj_private.pim_web_queue_change();
CREATE TRIGGER pim_web_document_change AFTER INSERT OR UPDATE OR DELETE ON tj.pim_product_documents
 FOR EACH ROW EXECUTE FUNCTION tj_private.pim_web_queue_change();
CREATE TRIGGER pim_web_price_change AFTER INSERT OR UPDATE OR DELETE ON tj.pim_retailer_prices
 FOR EACH ROW EXECUTE FUNCTION tj_private.pim_web_queue_change();

CREATE OR REPLACE FUNCTION tj_private.pim_web_complete_batch(batch_size integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE q record; outcome jsonb; stats jsonb:='{}'; label text;
BEGIN
 IF batch_size NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'invalid_batch_size'; END IF;
 FOR q IN SELECT * FROM tj_private.pim_web_completion_queue WHERE processed_at IS NULL AND attempts<5
 ORDER BY queued_at,pim_product_id LIMIT batch_size FOR UPDATE SKIP LOCKED LOOP
  BEGIN
   outcome:=tj_private.pim_web_complete_product(q.pim_product_id); label:=outcome->>'action';
   UPDATE tj_private.pim_web_completion_queue SET processed_at=clock_timestamp(),attempts=0,last_error=NULL WHERE pim_product_id=q.pim_product_id;
  EXCEPTION WHEN OTHERS THEN
   label:='error'; UPDATE tj_private.pim_web_completion_queue SET attempts=attempts+1,last_error=SQLSTATE||':'||SQLERRM WHERE pim_product_id=q.pim_product_id;
  END;
  stats:=jsonb_set(stats,ARRAY[label],to_jsonb(coalesce((stats->>label)::int,0)+1));
 END LOOP;
 RETURN stats;
END $$;
REVOKE ALL ON FUNCTION tj_private.pim_web_key(text),tj_private.pim_web_spec_key(text),tj_private.pim_web_blank(jsonb),
 tj_private.pim_web_fill_json(jsonb,jsonb),tj_private.pim_web_category(text),tj_private.pim_web_appliance(tj.aiq_products),
 tj_private.pim_web_complete_product(uuid),tj_private.pim_web_queue_change(),tj_private.pim_web_complete_batch(integer)
 FROM PUBLIC,anon,authenticated,service_role;
-- Native backend worker uses postgres; no anonymous/authenticated SECURITY DEFINER API.
INSERT INTO tj_private.pim_web_completion_queue(pim_product_id,organization_id)
 SELECT id,organization_id FROM tj.aiq_products WHERE tj_private.pim_web_appliance(aiq_products);
