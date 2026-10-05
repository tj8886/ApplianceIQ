-- Missing view dependencies remain owner-only until their caller access is reviewed.
CREATE VIEW tj."v_floor_sales_normalized" WITH(security_invoker=true) AS  SELECT 'crm'::text AS source,
    d.organization_id,
    d.location_id AS store_id,
    d.id AS source_id,
    COALESCE(p.value ->> 'model'::text, p.value ->> 'sku'::text) AS model_number,
    COALESCE(p.value ->> 'name'::text, p.value ->> 'product_name'::text) AS product_name,
    normalize_brand(COALESCE(p.value ->> 'brand'::text, p.value ->> 'brand_name'::text), d.organization_id) AS brand,
    normalize_category(COALESCE(p.value ->> 'category'::text, p.value ->> 'product_category'::text), d.organization_id) AS category,
    COALESCE((p.value ->> 'price'::text)::numeric, (p.value ->> 'amount'::text)::numeric, 0::numeric) AS revenue,
    COALESCE((p.value ->> 'quantity'::text)::numeric, 1::numeric) AS quantity,
    COALESCE(d.closed_at, d.updated_at, d.created_at) AS sold_at,
    COALESCE(p.value ->> 'brand'::text, p.value ->> 'brand_name'::text) AS raw_brand,
    COALESCE(p.value ->> 'category'::text, p.value ->> 'product_category'::text) AS raw_category
   FROM crm_deals d
     CROSS JOIN LATERAL jsonb_array_elements(d.won_products) p(value)
  WHERE d.stage ~~* '%won%'::text AND d.won_products IS NOT NULL AND jsonb_typeof(d.won_products) = 'array'::text
UNION ALL
 SELECT 'pos'::text AS source,
    f.organization_id,
    t.store_id,
    f.id AS source_id,
    f.item_number AS model_number,
    f.description AS product_name,
    normalize_brand(f.brand, f.organization_id) AS brand,
    normalize_category(f.product_category, f.organization_id) AS category,
    COALESCE(f.line_amount, 0::numeric) AS revenue,
    COALESCE(f.quantity, 1::numeric) AS quantity,
    f.occurred_at AS sold_at,
    f.brand AS raw_brand,
    f.product_category AS raw_category
   FROM iq_transaction_line_facts f
     LEFT JOIN iq_pos_transactions t ON t.id = f.transaction_id
  WHERE COALESCE(f.is_warranty, false) = false AND COALESCE(f.is_service, false) = false AND COALESCE(f.is_delivery, false) = false AND COALESCE(f.is_installation, false) = false AND COALESCE(f.is_haul_away, false) = false;
REVOKE ALL ON tj."v_floor_sales_normalized" FROM PUBLIC,anon,authenticated,service_role;
SET LOCAL search_path='tj','extensions','pg_temp';
