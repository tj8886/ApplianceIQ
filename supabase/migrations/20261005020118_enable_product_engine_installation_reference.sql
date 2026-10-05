-- Shared installation reference data; no tenant or shopper records.
ALTER TABLE tj.installation_requirements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON tj.installation_requirements FROM anon;
GRANT SELECT ON tj.installation_requirements TO authenticated;
CREATE POLICY us_product_engine_installation_reference ON tj.installation_requirements
FOR SELECT TO authenticated USING ((SELECT tj_private.has_active_mapped_org()));
NOTIFY pgrst,'reload schema';
