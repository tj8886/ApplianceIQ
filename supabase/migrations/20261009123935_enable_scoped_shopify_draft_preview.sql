-- Read-only quote preview. No provider credentials, customer/address mappings or draft writes.
CREATE FUNCTION tj_private.shopify_draft_order(p_body jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid;org uuid;pkg tj.speciq_packages%rowtype;operation text;lines jsonb;subtotal numeric;bad integer;line_count integer;
BEGIN
  actor:=tj_private.microsoft_actor(auth.uid());
  IF actor IS NULL THEN RAISE EXCEPTION 'verified_identity_required' USING ERRCODE='42501'; END IF;
  IF p_body IS NULL OR jsonb_typeof(p_body)<>'object' OR octet_length(p_body::text)>8192 OR EXISTS(SELECT 1 FROM jsonb_object_keys(p_body) k WHERE k NOT IN('package_id','organization_id','action')) THEN RAISE EXCEPTION 'invalid_request' USING ERRCODE='22023'; END IF;
  org:=(p_body->>'organization_id')::uuid;operation:=coalesce(p_body->>'action','create');
  IF operation NOT IN('preview','status','create') THEN RAISE EXCEPTION 'invalid_action' USING ERRCODE='22023'; END IF;
  IF org IS NULL OR NOT EXISTS(SELECT 1 FROM tj.organization_members m JOIN tj.organizations o ON o.id=m.organization_id WHERE m.organization_id=org AND m.user_id=actor AND m.status='active' AND m.role IN('owner','admin','super_admin') AND o.status='active' AND o.deleted_at IS NULL) THEN RAISE EXCEPTION 'admin_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO pkg FROM tj.speciq_packages WHERE id=(p_body->>'package_id')::uuid AND organization_id=org AND deleted_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'package_access_denied' USING ERRCODE='42501'; END IF;
  IF EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) OR EXISTS(SELECT 1 FROM tj.speciq_package_services WHERE package_id=pkg.id AND organization_id IS DISTINCT FROM org) THEN RAISE EXCEPTION 'inconsistent_child_organization' USING ERRCODE='42501'; END IF;
  IF operation<>'preview' THEN
    RETURN jsonb_build_object('ok',operation='status','executed',false,'draft_created',false,'package_id',pkg.id,'organization_id',org,'create_ready',false,'blockers',jsonb_build_array('fresh_verified_shopify_connection_and_write_draft_orders_scope_required','verified_shop_currency_and_discount_tax_contract_required','connection_scoped_variant_customer_mapping_required','atomic_claim_and_uncertain_provider_result_reconciliation_required'));
  END IF;
  WITH product_rows AS (
    SELECT id,'product'::text kind,btrim(concat_ws(' ',nullif(btrim(brand),''),nullif(btrim(model_number),''),nullif(btrim(product_name),''))) title,coalesce(quantity,1) quantity,
      coalesce(negotiated_price,promo_price,msrp) price,
      CASE WHEN negotiated_price IS NOT NULL THEN 'negotiated_price' WHEN promo_price IS NOT NULL THEN 'promo_price' ELSE 'msrp' END price_basis,sort_order
    FROM tj.speciq_package_products WHERE package_id=pkg.id ORDER BY sort_order NULLS LAST,id LIMIT 101
  ), service_rows AS (
    SELECT id,'service'::text kind,coalesce(nullif(btrim(description),''),nullif(btrim(service_type),'')) title,1 quantity,amount price,'amount'::text price_basis,sort_order
    FROM tj.speciq_package_services WHERE package_id=pkg.id ORDER BY sort_order NULLS LAST,id LIMIT 101
  ), all_rows AS (SELECT * FROM product_rows UNION ALL SELECT * FROM service_rows)
  SELECT count(*),count(*) FILTER(WHERE title IS NULL OR length(title) NOT BETWEEN 1 AND 250 OR quantity NOT BETWEEN 1 AND 1000 OR price IS NULL OR price<0 OR price>10000000 OR scale(price)>2),
    coalesce(sum(price*quantity),0),coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'title',title,'quantity',quantity,'unit_price',price::text,'extended_price',(price*quantity)::text,'price_basis',price_basis) ORDER BY kind,sort_order NULLS LAST,id),'[]'::jsonb)
    INTO line_count,bad,subtotal,lines FROM all_rows;
  IF line_count NOT BETWEEN 1 AND 100 OR bad<>0 THEN RAISE EXCEPTION 'invalid_quote_lines' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS(SELECT 1 FROM tj.speciq_package_products WHERE package_id=pkg.id) THEN RAISE EXCEPTION 'package_has_no_products' USING ERRCODE='22023'; END IF;
  RETURN jsonb_build_object('ok',true,'operation','preview','executed',false,'draft_created',false,'create_ready',false,'package_id',pkg.id,'organization_id',org,'package_version',pkg.version,'package_updated_at',pkg.updated_at,'lines',lines,'line_subtotal',subtotal::text,'currency',NULL,'recorded_volume_discount',pkg.volume_discount::text,'discount_applied',false,'tax_applied',false,'quote_hash',md5(jsonb_build_object('package_id',pkg.id,'lines',lines,'volume_discount',pkg.volume_discount,'tax_rule_id',pkg.tax_rule_id,'updated_at',pkg.updated_at)::text),'blockers',jsonb_build_array('fresh_verified_shopify_connection_and_write_draft_orders_scope_required','verified_shop_currency_and_discount_tax_contract_required','connection_scoped_variant_customer_mapping_required','atomic_claim_and_uncertain_provider_result_reconciliation_required'));
END $$;
REVOKE ALL ON FUNCTION tj_private.shopify_draft_order(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.shopify_draft_order(jsonb) TO authenticated;
CREATE FUNCTION public.tj_shopify_draft_order(p_body jsonb) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT tj_private.shopify_draft_order(p_body); $$;
REVOKE ALL ON FUNCTION public.tj_shopify_draft_order(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_shopify_draft_order(jsonb) TO authenticated;
