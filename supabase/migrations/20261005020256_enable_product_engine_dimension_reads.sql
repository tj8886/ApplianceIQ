ALTER TABLE tj.pim_product_dimensions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj.pim_product_dimensions FROM anon;
GRANT SELECT ON tj.pim_product_dimensions TO authenticated;
CREATE POLICY us_product_engine_dimensions ON tj.pim_product_dimensions
FOR SELECT TO authenticated USING (product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
NOTIFY pgrst,'reload schema';
