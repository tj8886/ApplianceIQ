import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const ALLOWED_DOMAINS = ['bestbrandappliance.ca','premiumappliances.ca','quanappliances.com'];

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const { url } = await req.json();
    if (!url || !ALLOWED_DOMAINS.some(d => url.includes(d))) {
      return new Response(JSON.stringify({ error: 'Domain not allowed', ok: false }), {
        status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
      });
    }
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-CA,en;q=0.9',
      },
      redirect: 'follow',
    });
    if (!resp.ok) return new Response(JSON.stringify({ ok: false, status: resp.status }), {
      headers: { ...CORS, 'Content-Type': 'application/json' }
    });
    const html = await resp.text();
    return new Response(JSON.stringify({ html, url, ok: true }), {
      headers: { ...CORS, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message, ok: false }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' }
    });
  }
});
