-- Preserve the two existing exposed schemas and enable guarded TJ routes.
DO $guard$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_class c WHERE c.relnamespace='tj'::regnamespace AND c.relkind IN('r','p','v','m') AND has_table_privilege('anon',c.oid,'select')) THEN RAISE EXCEPTION 'TJ anonymous table privileges require review'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c WHERE c.relnamespace='tj'::regnamespace AND c.relkind IN('r','p') AND has_table_privilege('authenticated',c.oid,'select') AND NOT c.relrowsecurity) THEN RAISE EXCEPTION 'TJ readable table without RLS'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c WHERE c.relnamespace='tj'::regnamespace AND c.relkind IN('v','m') AND has_table_privilege('authenticated',c.oid,'select')) THEN RAISE EXCEPTION 'TJ view permissions require review'; END IF;
END $guard$;
ALTER ROLE authenticator SET pgrst.db_schemas='public,graphql_public,tj';
NOTIFY pgrst,'reload config';
NOTIFY pgrst,'reload schema';
