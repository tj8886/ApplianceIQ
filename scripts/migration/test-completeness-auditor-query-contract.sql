BEGIN;SET LOCAL ROLE authenticated;
SELECT id,brand_name,model,category,short_description,width_inches,height_inches,depth_inches,msrp,map_price,sale_price,lowest_price,upc,ean,gtin,source_confidence,public_visible,approval_status,status,is_discontinued,is_end_of_life,updated_at FROM tj.aiq_products_app LIMIT 0;
SELECT product_id,id FROM tj.pim_product_features LIMIT 0;
SELECT product_id,id,is_current,approved FROM tj.pim_product_documents LIMIT 0;
SELECT product_id,id,approved FROM tj.pim_product_images LIMIT 0;
SELECT product_id,id FROM tj.pim_product_dimensions LIMIT 0;
SELECT product_id,id,checked_at,in_stock FROM tj.pim_retailer_prices LIMIT 0;
ROLLBACK;
