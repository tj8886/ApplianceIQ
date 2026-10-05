-- Platform catalog and personal state; no direct table writes granted.
CREATE FUNCTION tj_private.owns_source_user(p_user_id uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT coalesce(p_user_id=tj_private.current_source_user_id(),false); $$;
REVOKE ALL ON FUNCTION tj_private.owns_source_user(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj_private.owns_source_user(uuid) TO authenticated;

ALTER TABLE tj.platform_modules ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj.platform_user_context ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj.crm_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE tj.iq_pos_transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY consolidation_platform_catalog_read ON tj.platform_modules FOR SELECT TO authenticated
USING ((SELECT tj.is_platform_admin()) OR EXISTS(SELECT 1 FROM tj.my_org_ids()));
CREATE POLICY consolidation_personal_context_read ON tj.platform_user_context FOR SELECT TO authenticated
USING (tj_private.owns_source_user(user_id) AND
 (organization_id IS NULL OR organization_id IN (SELECT x.organization_id FROM tj.my_platform_organizations() x))
 AND (location_id IS NULL OR location_id IN (SELECT x.location_id FROM tj.my_platform_locations(organization_id) x)));
CREATE POLICY consolidation_personal_notifications_read ON tj.crm_notifications FOR SELECT TO authenticated
USING (tj_private.owns_source_user(user_id) AND
 (organization_id IS NULL OR organization_id IN (SELECT x.organization_id FROM tj.my_platform_organizations() x)));
CREATE POLICY consolidation_scoped_pos_read ON tj.iq_pos_transactions FOR SELECT TO authenticated
USING (tj.is_org_member(organization_id) AND tj.aiq_store_allows(organization_id,store_id));
GRANT SELECT ON tj.platform_modules,tj.platform_user_context,tj.crm_notifications,tj.iq_pos_transactions TO authenticated;

-- Search is invoker-only: each result also passes its underlying table's RLS.
CREATE FUNCTION tj.platform_global_search(p_query text,p_limit integer DEFAULT 30)
RETURNS TABLE(entity_type text,entity_id text,entity_label text,subtitle text,module_key text,
 organization_id uuid,location_id uuid,rank integer)
LANGUAGE plpgsql STABLE SECURITY INVOKER SET search_path=''
AS $$
DECLARE ctx jsonb:=tj.my_platform_context(); org_id uuid:=(ctx->>'organization_id')::uuid;
 q text:=trim(coalesce(p_query,'')); lim integer:=least(greatest(coalesce(p_limit,30),1),50);
BEGIN
 IF org_id IS NULL OR length(q)<2 THEN RETURN; END IF;
 RETURN QUERY WITH hits AS (
 SELECT 'contact'::text AS entity_type,c.id::text AS entity_id,
 trim(concat_ws(' ',c.first_name,c.last_name))::text AS entity_label,
 coalesce(c.email,c.phone,'')::text AS subtitle,'crm'::text AS module_key,
 c.organization_id,NULL::uuid AS location_id,
 CASE WHEN lower(trim(concat_ws(' ',c.first_name,c.last_name)))=lower(q) THEN 100
 WHEN lower(trim(concat_ws(' ',c.first_name,c.last_name))) LIKE lower(q)||'%' THEN 80 ELSE 60 END AS r
 FROM tj.contacts c WHERE c.organization_id=org_id AND
 (concat_ws(' ',c.first_name,c.last_name) ILIKE '%'||q||'%' OR c.email ILIKE '%'||q||'%' OR c.phone ILIKE '%'||q||'%')
 UNION ALL
 SELECT 'product',p.id::text,coalesce(nullif(p.name,''),concat_ws(' ',p.brand,p.model)),
 concat_ws(' · ',p.brand,p.model,p.category),'product_iq',p.organization_id,NULL::uuid,
 CASE WHEN lower(coalesce(p.model,''))=lower(q) THEN 100
 WHEN lower(coalesce(p.model,'')) LIKE lower(q)||'%' THEN 85 ELSE 55 END
 FROM tj.products p WHERE p.organization_id=org_id AND
 (p.name ILIKE '%'||q||'%' OR p.brand ILIKE '%'||q||'%' OR p.model ILIKE '%'||q||'%' OR p.category ILIKE '%'||q||'%')
 UNION ALL
 SELECT 'transaction',t.id::text,coalesce(t.pos_transaction_id,t.id::text),
 concat_ws(' · ',t.source_system,to_char(t.transaction_date,'YYYY-MM-DD'),
 coalesce(t.currency_code,'')||' '||coalesce(t.transaction_amount,0)::text),
 'command_center',t.organization_id,t.store_id,
 CASE WHEN lower(coalesce(t.pos_transaction_id,''))=lower(q) THEN 100 ELSE 50 END
 FROM tj.iq_pos_transactions t WHERE t.organization_id=org_id AND
 (t.pos_transaction_id ILIKE '%'||q||'%' OR t.customer_external_id ILIKE '%'||q||'%' OR t.salesperson_external_id ILIKE '%'||q||'%')
 ) SELECT h.entity_type,h.entity_id,h.entity_label,h.subtitle,h.module_key,h.organization_id,h.location_id,h.r
 FROM hits h ORDER BY h.r DESC,h.entity_label LIMIT lim;
END $$;
REVOKE ALL ON FUNCTION tj.platform_global_search(text,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION tj.platform_global_search(text,integer) TO authenticated;
NOTIFY pgrst,'reload schema';
