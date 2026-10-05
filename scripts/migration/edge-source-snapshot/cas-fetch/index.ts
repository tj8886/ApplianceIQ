import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Rotate user agents to look like different real browsers
const USER_AGENTS = [
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0',
  'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.92 Safari/537.36 Edg/130.0.2849.68',
];

let requestCount = 0;

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  try {
    const { url, urls } = await req.json();

    // Single URL fetch
    if (url) {
      const html = await fetchCAS(url);
      const blocked = html === '__CF_BLOCKED__';
      return new Response(JSON.stringify({ html: blocked ? null : html, url, ok: !!html && !blocked, blocked }), {
        headers: { ...CORS, 'Content-Type': 'application/json' }
      });
    }

    // Batch URL fetch (for sitemaps)
    if (urls && Array.isArray(urls)) {
      const results = [];
      for (const u of urls.slice(0, 5)) {
        const html = await fetchCAS(u);
        const blocked = html === '__CF_BLOCKED__';
        results.push({ url: u, html: blocked ? null : html, ok: !!html && !blocked, blocked });
        // Randomized delay between batch items
        if (urls.length > 1) await sleep(800 + Math.random() * 1200);
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

function sleep(ms: number): Promise<void> {
  return new Promise(r => setTimeout(r, ms));
}

async function fetchCAS(url: string): Promise<string | null> {
  try {
    // Pick a random user agent
    const ua = USER_AGENTS[requestCount % USER_AGENTS.length];
    requestCount++;

    // Build headers that match a real browser session
    const headers: Record<string, string> = {
      'User-Agent': ua,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'en-CA,en-US;q=0.9,en;q=0.8,fr;q=0.7',
      'Accept-Encoding': 'gzip, deflate, br',
      'Cache-Control': 'max-age=0',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
      'Sec-Ch-Ua': '"Chromium";v="131", "Not_A_Brand";v="24"',
      'Sec-Ch-Ua-Mobile': '?0',
      'Sec-Ch-Ua-Platform': '"macOS"',
      'DNT': '1',
    };

    // Add referer for product pages (looks like navigation from category)
    if (url.includes('/product/')) {
      const brand = url.split('/product/')[1]?.split('_')[0] || '';
      headers['Referer'] = 'https://www.canadianappliance.ca/categories/' + brand.toLowerCase();
    }

    const resp = await fetch(url, { headers, redirect: 'follow' });

    if (!resp.ok) {
      console.log('CAS fetch failed:', resp.status, url);
      return null;
    }

    const text = await resp.text();

    // Check if Cloudflare challenged us
    if (text.includes('Just a moment') && text.includes('challenge-platform')) {
      console.log('Cloudflare challenge detected for:', url);
      return '__CF_BLOCKED__'; // Distinct signal so client knows it was CF
    }

    // Check for other CF blocks
    if (text.includes('Attention Required!') || text.includes('cf-error-details')) {
      console.log('Cloudflare error page for:', url);
      return '__CF_BLOCKED__';
    }

    return text;
  } catch (e) {
    console.error('Fetch error for', url, (e as Error).message);
    return null;
  }
}
