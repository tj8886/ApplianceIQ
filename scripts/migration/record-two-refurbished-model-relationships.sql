BEGIN;
SET LOCAL statement_timeout='25s';
WITH links(source_id,base_pim_id,base_website_id,source_model,base_model,source_url) AS (VALUES
('07917f78-8101-47a0-be1b-2c62253fec56'::uuid,'f76a6f38-35a8-41f3-a940-4e39293d3251'::uuid,'bf38239b-dcd3-41b2-ba3c-b543f0600c87'::uuid,'HRE3001-R','HRE3001','https://www.thorkitchen.com/products/thor-kitchen-30-inch-professional-electric-range-hre3001-r-refurbished'),
('0491372d-0592-4bc0-9112-075c159b26df'::uuid,'8c5f852b-7764-44cc-803a-a7793bae96b6'::uuid,'239f99c0-ad3a-4654-b46d-11b544933aa6'::uuid,'HRE3601-R','HRE3601','https://www.thorkitchen.com/products/thor-kitchen-36-inch-professional-electric-range-hre3601-r-refurbished')),
logged AS (
INSERT INTO tj_private.pim_web_completion_log(organization_id,pim_product_id,website_product_id,source_updated_at,action,before_values,after_values,detail)
SELECT t.organization_id,t.id,p.id,t.source_extracted_at,'condition_variant_relationship',to_jsonb(t),to_jsonb(t),
jsonb_build_object('operation','record_two_refurbished_model_relationships','source_model',l.source_model,'base_model',l.base_model,'base_pim_id',l.base_pim_id,'source_url',l.source_url,'condition','certified_refurbished','checked_on','2026-10-11','provider_exact_sku_verified',true,'catalog_publication',false,'price_and_specs_transferred',false,'source_retained',true)
FROM links l JOIN tj.aiq_products t ON t.id=l.source_id AND t.model=l.source_model AND t.brand_name='Thor Kitchen'
JOIN tj.aiq_products b ON b.id=l.base_pim_id AND b.model=l.base_model AND b.brand_name='Thor Kitchen'
JOIN public.products p ON p.id=l.base_website_id AND p.model_number=l.base_model AND p.brand_canonical_id=public.brand_resolve('Thor Kitchen')
WHERE t.source_reference=l.source_url AND t.short_description ILIKE '%Certified Refurbished%'
AND NOT EXISTS(SELECT 1 FROM tj_private.pim_web_completion_log a WHERE a.pim_product_id=t.id AND a.detail->>'operation'='record_two_refurbished_model_relationships')
RETURNING id)
SELECT count(*) recorded_condition_relationships FROM logged;
COMMIT;
