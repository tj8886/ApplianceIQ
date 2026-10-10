CREATE FUNCTION tj_private.allowed_catalog_products() RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT coalesce(array_agg(p.id),'{}'::uuid[]) FROM tj.aiq_products p JOIN tj.organizations o ON o.id=p.organization_id
 WHERE (SELECT tj_private.has_active_mapped_org()) AND o.status='active' AND o.deleted_at IS NULL AND (
 (SELECT tj_private.is_product_governance_admin())
 OR p.organization_id IN(SELECT m.organization_id FROM tj.organization_members m WHERE m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active' AND m.role IN('owner','admin'))
 OR p.brand_id IN(SELECT s.brand_id FROM tj.product_iq_brand_scopes s JOIN tj.mfr_members m ON m.vendor_id=s.vendor_id JOIN tj.brand_catalog b ON b.id=s.brand_id AND b.manufacturer_id=s.vendor_id WHERE s.organization_id=p.organization_id AND s.status='active' AND (s.expires_at IS NULL OR s.expires_at>now()) AND s.capabilities && ARRAY['product_read','product_manage'] AND m.user_id=(SELECT tj_private.current_source_user_id()) AND m.status='active' AND m.revoked_at IS NULL AND m.suspended_at IS NULL AND (m.expires_at IS NULL OR m.expires_at>now()) AND m.role IN('vendor_owner','vendor_admin','brand_admin','product_editor','product_reviewer','asset_editor','training_editor','viewer'))
 OR (p.public_visible AND p.approval_status='approved' AND p.status IN('active','discontinued','clearance','end_of_life','open_box','refurbished') AND p.brand_id IN(SELECT rb.brand_id FROM tj.piq_retailer_brands rb JOIN tj.mfr_user_roles r ON r.user_id=rb.user_id JOIN tj.piq_retailer_profiles rp ON rp.user_id=rb.user_id WHERE rb.user_id=(SELECT tj_private.current_source_user_id()) AND (r.is_retailer OR r.is_builder OR r.is_designer OR r.is_admin) AND (rp.organization_id IS NULL OR tj_private.can_read_runtime_org(rp.organization_id))))
 );
$$;
REVOKE ALL ON FUNCTION tj_private.allowed_catalog_products() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.allowed_catalog_products() TO authenticated;
ALTER POLICY consolidation_catalog_read ON tj.aiq_products USING(id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.pim_price_history USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.pim_product_certifications USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.pim_product_features USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.pim_retailer_prices USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.pim_product_documents USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]) AND approved IS TRUE AND tj_private.catalog_asset_allowed(available_from,available_until,embargoed,audience_tiers,exclusive_codes) AND is_current IS TRUE AND (expiry_date IS NULL OR expiry_date>=current_date));
ALTER POLICY consolidation_catalog_read ON tj.pim_product_images USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]) AND approved IS TRUE AND tj_private.catalog_asset_allowed(available_from,available_until,embargoed,audience_tiers,exclusive_codes));
ALTER POLICY consolidation_catalog_read ON tj.pim_product_videos USING(product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]) AND approved IS TRUE AND tj_private.catalog_asset_allowed(available_from,available_until,embargoed,audience_tiers,exclusive_codes) AND is_current IS TRUE AND archived_at IS NULL);
ALTER POLICY consolidation_catalog_read ON tj.product_relationships USING(source_product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]) AND related_product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]));
ALTER POLICY consolidation_catalog_read ON tj.retailer_discovered_products USING(aiq_product_id = ANY ((SELECT tj_private.allowed_catalog_products())::uuid[]) OR (SELECT tj_private.is_product_governance_admin()));
