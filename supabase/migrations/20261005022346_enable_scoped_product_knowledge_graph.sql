CREATE FUNCTION tj_private.visible_product_graph_nodes(p_org uuid) RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 WITH allowed AS MATERIALIZED (SELECT tj_private.allowed_catalog_products() ids)
 SELECT coalesce(array_agg(n.id),'{}'::uuid[]) FROM tj.aicrm_graph_nodes n CROSS JOIN allowed a
 WHERE tj_private.can_read_runtime_org(p_org) AND n.organization_id=p_org AND n.active IS TRUE AND (
 (n.entity_type='aiq_products' AND EXISTS(SELECT 1 FROM tj.aiq_products p WHERE p.id=n.entity_id AND p.organization_id=p_org AND p.id=ANY(a.ids))) OR
 (n.entity_type='brand_catalog' AND EXISTS(SELECT 1 FROM tj.brand_catalog b WHERE b.id=n.entity_id AND b.organization_id=p_org AND b.is_active IS TRUE AND EXISTS(SELECT 1 FROM tj.aiq_products p WHERE p.brand_id=b.id AND p.organization_id=p_org AND p.id=ANY(a.ids)))) OR
 (n.entity_type='pim_product_documents' AND EXISTS(SELECT 1 FROM tj.pim_product_documents d JOIN tj.aiq_products p ON p.id=d.product_id WHERE d.id=n.entity_id AND p.organization_id=p_org AND p.id=ANY(a.ids) AND d.approved IS TRUE AND d.is_current IS TRUE AND (d.expiry_date IS NULL OR d.expiry_date>=current_date) AND tj_private.catalog_asset_allowed(d.available_from,d.available_until,d.embargoed,d.audience_tiers,d.exclusive_codes))) OR
 (n.entity_type='pim_product_accessories' AND EXISTS(SELECT 1 FROM tj.pim_product_accessories x JOIN tj.aiq_products p ON p.id=x.product_id WHERE x.id=n.entity_id AND p.organization_id=p_org AND p.id=ANY(a.ids))));
$$;
CREATE FUNCTION tj_private.product_graph_lookup(p_org uuid,p_product_ids uuid[] DEFAULT '{}',p_models text[] DEFAULT '{}',p_query text DEFAULT '',p_limit integer DEFAULT 100) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE visible_ids uuid[]; seeds uuid[]; nodes jsonb; edges jsonb;
BEGIN
 IF NOT tj_private.can_read_runtime_org(p_org) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501'; END IF;
 IF cardinality(p_product_ids)>25 OR cardinality(p_models)>25 OR length(p_query)>100 OR p_limit NOT BETWEEN 1 AND 250 THEN RAISE EXCEPTION 'Invalid graph request' USING ERRCODE='22023'; END IF;
 visible_ids:=tj_private.visible_product_graph_nodes(p_org);
 SELECT coalesce(array_agg(id),'{}') INTO seeds FROM (
 SELECT n.id FROM tj.aicrm_graph_nodes n WHERE n.id=ANY(visible_ids) AND (
 CASE WHEN cardinality(p_product_ids)>0 THEN n.entity_type='aiq_products' AND n.entity_id=ANY(p_product_ids)
 WHEN cardinality(p_models)>0 THEN n.entity_type='aiq_products' AND EXISTS(SELECT 1 FROM tj.aiq_products p WHERE p.id=n.entity_id AND p.model=ANY(p_models))
 ELSE p_query<>'' AND n.label ILIKE '%'||replace(replace(p_query,'%','\%'),'_','\_')||'%' END)
 ORDER BY n.id LIMIT 25) q;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',n.id,'organization_id',n.organization_id,'node_type',n.node_type,'entity_id',n.entity_id,'entity_type',n.entity_type,'label',n.label,'description',n.description,'metadata','{}'::jsonb)),'[]') INTO nodes FROM tj.aicrm_graph_nodes n WHERE n.id=ANY(seeds);
 SELECT coalesce(jsonb_agg(result),'[]') INTO edges FROM (
 SELECT jsonb_build_object('id',e.id,'relationship_type',e.relationship_type,'strength',e.strength,'confidence',e.confidence,'source',e.source,
 'metadata',jsonb_build_object('semantic_type',CASE WHEN e.metadata->>'semantic_type'=ANY(ARRAY['made_by_brand','has_document','requires_accessory','includes_accessory','compatible_accessory','replaced_by']) THEN e.metadata->>'semantic_type' ELSE 'connected' END),
 'from_node',jsonb_build_object('id',f.id,'node_type',f.node_type,'entity_id',f.entity_id,'entity_type',f.entity_type,'label',f.label,'description',f.description,'metadata','{}'::jsonb),
 'to_node',jsonb_build_object('id',t.id,'node_type',t.node_type,'entity_id',t.entity_id,'entity_type',t.entity_type,'label',t.label,'description',t.description,'metadata','{}'::jsonb)) result
 FROM tj.aicrm_graph_edges e JOIN tj.aicrm_graph_nodes f ON f.id=e.from_node_id JOIN tj.aicrm_graph_nodes t ON t.id=e.to_node_id
 WHERE e.organization_id=p_org AND f.organization_id=p_org AND t.organization_id=p_org AND f.id=ANY(visible_ids) AND t.id=ANY(visible_ids)
 AND (f.id=ANY(seeds) OR t.id=ANY(seeds)) ORDER BY e.id LIMIT p_limit) q;
 RETURN jsonb_build_object('ok',true,'mode','lookup','nodes',nodes,'relationships',edges,'node_count',jsonb_array_length(nodes),'relationship_count',jsonb_array_length(edges));
END $$;
CREATE FUNCTION tj_private.sync_product_graph(p_org uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF p_org IS NULL OR NOT tj_private.can_read_runtime_org(p_org) OR NOT tj.is_org_admin(p_org) THEN RAISE EXCEPTION 'Organization administrator required' USING ERRCODE='42501'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_org::text,0));
 RETURN tj.aiq_sync_knowledge_graph(p_org);
END $$;
REVOKE ALL ON FUNCTION tj_private.visible_product_graph_nodes(uuid),tj_private.product_graph_lookup(uuid,uuid[],text[],text,integer),tj_private.sync_product_graph(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION tj_private.product_graph_lookup(uuid,uuid[],text[],text,integer),tj_private.sync_product_graph(uuid) TO authenticated;
CREATE FUNCTION public.tj_product_graph_lookup(p_org uuid,p_product_ids uuid[] DEFAULT '{}',p_models text[] DEFAULT '{}',p_query text DEFAULT '',p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.product_graph_lookup(p_org,p_product_ids,p_models,p_query,p_limit);$$;
CREATE FUNCTION public.tj_sync_product_graph(p_org uuid) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.sync_product_graph(p_org);$$;
REVOKE ALL ON FUNCTION public.tj_product_graph_lookup(uuid,uuid[],text[],text,integer),public.tj_sync_product_graph(uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.tj_product_graph_lookup(uuid,uuid[],text[],text,integer),public.tj_sync_product_graph(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
