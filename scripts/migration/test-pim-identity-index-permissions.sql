BEGIN;
SET LOCAL statement_timeout='20s';
DO $$ BEGIN IF has_function_privilege('authenticated','tj_private.pim_web_complete_batch(integer)','EXECUTE') OR has_function_privilege('service_role','tj_private.pim_web_complete_batch(integer)','EXECUTE') THEN RAISE EXCEPTION 'worker authority changed';END IF;END $$;
SET LOCAL ROLE service_role;
UPDATE public.products SET manufacturer_status=manufacturer_status WHERE id=(SELECT id FROM public.products WHERE status='active' LIMIT 1);
SELECT tj_private.pim_web_key(' Bosch-ABC123 ')='boschabc123' AS normalizer_works;
RESET ROLE;
ROLLBACK;
