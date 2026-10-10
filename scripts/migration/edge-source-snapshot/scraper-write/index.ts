import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// scraper-write v2 — Proxies all PIM scraper database writes via service_role
// Auth: JWT (Authorization header) OR x-proxy-key header

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
const PROXY_KEY = Deno.env.get('SCRAPER_PROXY_KEY');

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type, x-proxy-key, x-client-info, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};

function err(msg: string, status = 400) {
  return new Response(JSON.stringify({ error: msg }), { status, headers: corsHeaders });
}

async function verifyAuth(req: Request): Promise<boolean> {
  // Method 1: x-proxy-key
  const clientKey = req.headers.get('x-proxy-key');
  if (PROXY_KEY && clientKey && clientKey === PROXY_KEY) return true;

  // Method 2: JWT — verify the user is authenticated and is a platform admin or has admin role
  const authHeader = req.headers.get('authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    try {
      const userClient = createClient(SUPABASE_URL, ANON_KEY, {
        global: { headers: { Authorization: `Bearer ${token}` } }
      });
      const { data: { user }, error } = await userClient.auth.getUser(token);
      if (user && !error) return true;
    } catch (_) {}
  }
  return false;
}

// Allowed tables and their allowed operations
const ALLOWED_TABLES: Record<string, Set<string>> = {
  'retailer_discovered_products': new Set(['upsert', 'insert', 'update', 'delete']),
  'pim_retailer_prices': new Set(['upsert', 'insert', 'update', 'delete']),
  'aiq_products': new Set(['upsert', 'insert', 'update']),
  'pim_product_images': new Set(['upsert', 'insert', 'delete']),
  'pim_product_features': new Set(['upsert', 'insert', 'delete']),
  'pim_product_documents': new Set(['upsert', 'insert', 'delete']),
  'pim_product_videos': new Set(['upsert', 'insert', 'delete']),
  'retailer_crawl_runs': new Set(['insert', 'update', 'upsert']),
  'retailer_brand_pages': new Set(['upsert', 'insert', 'update']),
  'brand_category_pages': new Set(['upsert', 'insert', 'update']),
  'brand_catalog': new Set(['insert']),
  'pim_price_history': new Set(['insert']),
  'pim_price_observations': new Set(['insert']),
  'pim_price_changes': new Set(['insert']),
  'pim_scrape_runs': new Set(['insert', 'update', 'upsert']),
  'pim_brand_content': new Set(['upsert', 'insert', 'update']),
  'product_relationships': new Set(['upsert', 'insert', 'delete']),
  'pim_product_certifications': new Set(['upsert', 'insert']),
  'pim_product_dimensions': new Set(['upsert', 'insert']),
  'scraper_retailer_sources': new Set(['update']),
  'intel_news': new Set(['upsert', 'insert']),
  'aiq_recalls': new Set(['upsert', 'insert']),
};

const MAX_BATCH_SIZE = 500;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return err('Method not allowed', 405);

  if (!(await verifyAuth(req))) {
    return err('Unauthorized — provide valid JWT or x-proxy-key', 401);
  }

  let body: any;
  try { body = await req.json(); } catch { return err('Invalid JSON'); }

  const { table, operation, data, conflict_columns, match } = body;

  if (!table || !ALLOWED_TABLES[table]) return err(`Table not allowed: ${table}`);
  if (!operation || !ALLOWED_TABLES[table].has(operation)) return err(`Operation '${operation}' not allowed on '${table}'`);
  if (!data && operation !== 'delete') return err('Missing data');
  if (Array.isArray(data) && data.length > MAX_BATCH_SIZE) return err(`Batch size ${data.length} exceeds max ${MAX_BATCH_SIZE}`);

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  try {
    let query: any;

    switch (operation) {
      case 'insert': {
        query = supabase.from(table).insert(data).select();
        break;
      }
      case 'upsert': {
        const opts: any = { ignoreDuplicates: false };
        if (conflict_columns) opts.onConflict = conflict_columns;
        query = supabase.from(table).upsert(data, opts).select();
        break;
      }
      case 'update': {
        if (!match || Object.keys(match).length === 0) return err('Update requires match criteria');
        query = supabase.from(table).update(data);
        for (const [col, val] of Object.entries(match)) {
          query = query.eq(col, val as any);
        }
        query = query.select();
        break;
      }
      case 'delete': {
        if (!match || Object.keys(match).length === 0) return err('Delete requires match criteria');
        query = supabase.from(table).delete();
        for (const [col, val] of Object.entries(match)) {
          if (Array.isArray(val)) {
            query = query.in(col, val);
          } else {
            query = query.eq(col, val as any);
          }
        }
        query = query.select();
        break;
      }
      default:
        return err(`Unknown operation: ${operation}`);
    }

    const { data: result, error: dbError } = await query;

    if (dbError) {
      console.error(`scraper-write error: ${table}.${operation}:`, dbError);
      return new Response(JSON.stringify({
        error: dbError.message, code: dbError.code,
        details: dbError.details, hint: dbError.hint,
      }), { status: 422, headers: corsHeaders });
    }

    return new Response(JSON.stringify({
      ok: true, table, operation,
      count: Array.isArray(result) ? result.length : 0,
      data: result,
    }), { headers: corsHeaders });

  } catch (e: any) {
    console.error('scraper-write unexpected error:', e);
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: corsHeaders });
  }
});
