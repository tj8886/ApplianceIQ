CREATE FUNCTION tj_private.latest_product_conversation(p_organization_id uuid) RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE actor uuid:=tj_private.current_source_user_id();result uuid;BEGIN
 IF actor IS NULL OR NOT tj_private.can_read_runtime_org(p_organization_id) THEN RAISE EXCEPTION 'Organization access denied' USING ERRCODE='42501';END IF;
 SELECT id INTO result FROM tj.ai_conversations WHERE user_id=actor AND organization_id=p_organization_id AND status='active' ORDER BY last_message_at DESC,updated_at DESC,id DESC LIMIT 1;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION tj_private.latest_product_conversation(uuid) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION tj_private.latest_product_conversation(uuid) TO authenticated;
CREATE FUNCTION public.tj_latest_product_conversation(p_organization_id uuid) RETURNS uuid LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$SELECT tj_private.latest_product_conversation(p_organization_id);$$;
REVOKE ALL ON FUNCTION public.tj_latest_product_conversation(uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tj_latest_product_conversation(uuid) TO authenticated;
NOTIFY pgrst,'reload schema';
