import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { url, urls } = await req.json();

    // Single URL fetch
    if (url) {
      const html = await fetchTrail(url);
      return new Response(JSON.stringify({ html, url, ok: !!html }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      });
    }

    // Batch URL fetch (up to 5 at a time)
    if (urls && Array.isArray(urls)) {
      const results = [];
      for (const u of urls.slice(0, 5)) {
        const html = await fetchTrail(u);
        results.push({ url: u, html, ok: !!html });
        // Small delay between requests to be respectful
        if (urls.length > 1) await new Promise(r => setTimeout(r, 500));
      }
      return new Response(JSON.stringify({ results }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ error: 'Provide url or urls' }), {
      status: 400, headers: { ...CORS, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500, headers: { ...CORS, 'Content-Type': 'application/json' }
    });
  }
});

async function fetchTrail(url: string): Promise<string | null> {
  // Only allow trailappliances.com
  if (!url.includes('trailappliances.com')) {
    console.log('Blocked non-Trail URL:', url);
    return null;
  }
  try {
    const resp = await fetch(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-CA,en-US;q=0.9,en;q=0.8',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-User': '?1',
      },
      redirect: 'follow',
    });

    if (!resp.ok) {
      console.log('Trail fetch failed:', resp.status, url);
      return null;
    }

    return await resp.text();
  } catch (e) {
    console.error('Trail fetch error for', url, (e as Error).message);
    return null;
  }
}
