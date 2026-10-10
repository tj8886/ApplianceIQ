import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Connection': 'keep-alive'
};

const ALLOWED_DOMAINS = new Set([
  // Retailers
  'appliancecanada.com',
  'dufresne.ca',
  'futureappliances.ca',
  'futuresappliances.ca',
  'leons.ca',
  'merrithewsappliance.com',
  'secondshop.ca',
  'taappliance.com',
  'thebrick.com',
  // Manufacturers (Shopify)
  'avantiproducts.com',
  'blombergappliances.com',
  'elmirastoveworks.com',
  'empava.com',
  'faberonline.com',
  'forno.ca',
  'kalamazoogourmet.com',
  'thorkitchen.com',
  'uniqueappliances.com',
  'zlinekitchen.com'
]);

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  
  try {
    const { url } = await req.json();
    if (!url) return new Response(JSON.stringify({ error: 'url required' }), { status: 400, headers: CORS });
    
    const parsed = new URL(url);
    const host = parsed.hostname.replace('www.', '');
    if (!ALLOWED_DOMAINS.has(host)) {
      return new Response(JSON.stringify({ error: 'Domain not allowed: ' + host }), { status: 403, headers: CORS });
    }
    
    const path = parsed.pathname;
    const isAllowed = path.includes('/products.json') || 
                      (path.startsWith('/products/') && path.endsWith('.json')) ||
                      path.includes('/search/suggest.json');
    if (!isAllowed) {
      return new Response(JSON.stringify({ error: 'Only Shopify product API paths allowed' }), { status: 403, headers: CORS });
    }
    
    const resp = await fetch(url, {
      headers: { 'User-Agent': 'Mozilla/5.0 (compatible; ApplianceIQ/1.0)' }
    });
    
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: 'Shopify returned ' + resp.status }), { status: resp.status, headers: CORS });
    }
    
    const data = await resp.json();
    return new Response(JSON.stringify(data), { headers: CORS });
    
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500, headers: CORS });
  }
});
