CREATE FUNCTION tj_private.can_reference_field_client(p_id uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM tj.field_clients c WHERE c.id=p_id AND c.status='active' AND tj_private.can_read_runtime_org(c.organization_id) AND tj.is_field_client_member(c.id));
$$;
REVOKE ALL ON FUNCTION tj_private.can_reference_field_client(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.can_reference_field_client(uuid) TO authenticated;
CREATE POLICY consolidation_field_client_reference_read ON tj.field_clients FOR SELECT TO authenticated USING(tj_private.can_reference_field_client(id));
GRANT SELECT(id,organization_id) ON tj.field_clients TO authenticated;
NOTIFY pgrst,'reload schema';
