import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { createCatalogFetchHandler } from "../_shared/catalog-fetch.ts";
Deno.serve(createCatalogFetchHandler({ kind: "shopify-proxy", createClient, env: (name) => Deno.env.get(name) }));
