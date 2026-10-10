CREATE OR REPLACE FUNCTION public.tj_pim_scraper_context() RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT jsonb_build_object('allowed',tj_private.is_product_governance_admin()); $$;
NOTIFY pgrst,'reload schema';
