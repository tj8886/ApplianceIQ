CREATE FUNCTION public.tj_pim_scraper_context() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT jsonb_build_object('allowed',tj_private.is_product_governance_admin(),'source_user_id',tj_private.current_source_user_id()); $$;
REVOKE ALL ON FUNCTION public.tj_pim_scraper_context() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.tj_pim_scraper_context() TO authenticated;
NOTIFY pgrst,'reload schema';
