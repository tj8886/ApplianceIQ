BEGIN;
DO $$
DECLARE p tj.aiq_products; w public.products; before_row jsonb; after_row jsonb; evidence jsonb; extracted timestamptz; source_url text; n int;
BEGIN
 IF (SELECT count(*) FROM tj.aiq_products WHERE model='RS3684WRUVE1' AND market='CA')<>1 THEN RAISE EXCEPTION 'Model/market identity is ambiguous';END IF;
 SELECT * INTO p FROM tj.aiq_products WHERE model='RS3684WRUVE1' AND market='CA' FOR UPDATE;
 IF p.source_extracted_at IS NOT NULL OR p.source_reference IS NOT NULL THEN RAISE EXCEPTION 'Original source fields already exist; preserve them';END IF;
 SELECT * INTO STRICT w FROM public.products WHERE model_number=p.model;
 SELECT jsonb_object_agg(e.key,e.value),min((e.value->>'fetched_at')::timestamptz),min(e.value->>'source_url'),count(*)
 INTO evidence,extracted,source_url,n FROM jsonb_each(w.spec_provenance)e WHERE e.value ? 'fetched_at';
 IF n<>7 OR extracted IS NULL OR extracted>now() OR source_url NOT LIKE 'https://www.fisherpaykel.com/ca/%rs3684wruve1%'
 OR (SELECT count(distinct e.value->>'fetched_at') FROM jsonb_each(evidence)e)<>1
 OR (SELECT count(distinct e.value->>'source_url') FROM jsonb_each(evidence)e)<>1
 OR EXISTS(SELECT 1 FROM jsonb_each(evidence)e WHERE p.specs_json->>e.key IS DISTINCT FROM e.value->>'value')
 THEN RAISE EXCEPTION 'Canadian stored specification provenance no longer matches';END IF;
 before_row:=to_jsonb(p);
 UPDATE tj.aiq_products SET source_extracted_at=extracted,source_reference=source_url WHERE id=p.id RETURNING to_jsonb(aiq_products.*) INTO after_row;
 IF (before_row-ARRAY['source_extracted_at','source_reference','updated_at']) IS DISTINCT FROM (after_row-ARRAY['source_extracted_at','source_reference','updated_at']) THEN RAISE EXCEPTION 'Protected facts changed';END IF;
 INSERT INTO tj_private.pim_feed_receipts(organization_id,website_product_id,pim_product_id,kind,source_date,payload,before_values,after_values,outcome)
 VALUES(p.organization_id,w.id,p.id,'historical_spec_source_date_recovery',extracted,
 jsonb_build_object('specification_provenance',evidence,'basis','Seven stored Canadian spec values match original field-level fetched_at and source_url. Original evidence_class remains unknown; this is no new verification. US enrichment attempt remains separate.'),
 before_row,after_row,'restored_original_source_date');
END $$;
COMMIT;
SELECT model,market,source_extracted_at,source_reference,category FROM tj.aiq_products WHERE model='RS3684WRUVE1' AND market='CA';
