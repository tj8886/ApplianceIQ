import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

const EXCLUDE_URL_KEYWORDS = [
  '/parts','/accessories','/replacement','/spare-parts',
  '/bath','/bathroom','/ceiling-fan','/hvac','/furnace','/air-condition',
  '/water-heater','/water-cooler','/water-dispenser','/water-filter',
  '/vacuum','/floor-care','/lighting','/light-bulb','/smart-home','/doorbell',
  '/humidifier','/dehumidifier','/air-purifier','/air-cleaner',
  '/toaster','/blender','/kettle','/food-processor','/stand-mixer','/coffee-maker',
  '/slow-cooker','/hand-mixer','/juicer','/waffle','/bread-maker',
  '/handle','/knob','/trim-kit','/filler','/backsplash','/wok-ring',
  '/grate-set','/drip-pan','/filter-pack','/stacking-kit','/pedestal',
  '/hose','/bracket','/panel-ready','/door-panel',
  '/personal-care','/hair','/shaver','/iron','/steamer',
  // Corporate / info pages (v9)
  '/faq','/support','/warranty-registration','/product-registration','/contact',
  '/blog','/about','/careers','/press','/news','/recipe','/how-to',
  '/compare','/promotions','/rebate','/financing',
  '/company-profile','/environmental','/recycling','/sustainability','/csr',
  '/corporate','/media','/investor','/annual-report','/history','/our-story',
  '/locations','/store-locator','/privacy','/terms','/cookie','/legal',
  '/sitemap','/search','/login','/register','/account','/cart','/checkout',
  '/where-to-buy','/find-a-dealer','/service-locator','/manuals','/downloads',
  '/recall','/safety-notice','/trade-program','/designer-program',
];

const EXCLUDE_URL_PATTERNS = [
  /\/(parts|accessories|replacement|spare)\//i,
  /-(handle|knob|kit|bracket|hose|cap|cover|gasket|burner-cap)s?$/i,
  /\/(bathroom|bath)-(fan|ventilat)/i,
];

const INCLUDE_URL_KEYWORDS = [
  'refrigerat','freezer','range','oven','cooktop','rangetop','dishwasher',
  'washer','dryer','laundry','microwave','hood','ventilat',
  'wine-cooler','wine-cellar','beverage','ice-maker','undercounter',
  'garbage-disposal','trash-compact','warming-drawer','speed-oven','steam-oven',
  'coffee-system','built-in-coffee','grill','smoker','pizza-oven',
  'outdoor-kitchen','outdoor-fridge','outdoor-refrigerat',
  'freestanding','slide-in','french-door','side-by-side','front-load','top-load',
  '/products/','/product/','/collections/',
];

function isRelevantUrl(url: string, productScope?: string[]): boolean {
  const lower = url.toLowerCase();
  for (const kw of INCLUDE_URL_KEYWORDS) { if (lower.includes(kw)) return true; }
  for (const kw of EXCLUDE_URL_KEYWORDS) { if (lower.includes(kw)) return false; }
  for (const rx of EXCLUDE_URL_PATTERNS) { if (rx.test(lower)) return false; }
  if (productScope && productScope.length > 0) {
    const scopeKeywords: Record<string, string[]> = {
      'range_hoods': ['hood','range-hood','chimney','downdraft','insert','liner','blower'],
      'ventilation_kitchen': ['hood','range-hood','kitchen-ventil','chimney','downdraft'],
      'refrigerators': ['refrigerat','fridge','french-door','side-by-side','top-freez','bottom-freez'],
      'freezers': ['freezer','chest-freezer','upright-freezer'],
      'ranges': ['range','stove','freestanding','slide-in','dual-fuel','gas-range','electric-range','induction-range'],
      'ovens': ['oven','wall-oven','double-oven','single-oven','convection-oven'],
      'cooktops': ['cooktop','rangetop','induction-cooktop','gas-cooktop','electric-cooktop'],
      'dishwashers': ['dishwasher'],
      'wine_coolers': ['wine','beverage','cellar'],
      'microwaves': ['microwave','over-the-range'],
      'outdoor_grills': ['grill','bbq','barbecue','smoker'],
      'outdoor_cooking': ['grill','bbq','outdoor-kitchen','pizza-oven','side-burner'],
      'washers': ['washer','washing-machine','front-load','top-load'],
      'dryers': ['dryer','tumble'],
    };
    const allScopeKws: string[] = [];
    for (const scope of productScope) {
      const kws = scopeKeywords[scope]; if (kws) allScopeKws.push(...kws);
    }
    if (allScopeKws.length > 0) {
      const matchesScope = allScopeKws.some(kw => lower.includes(kw));
      const isGenericProductUrl = lower.includes('/products/') || lower.includes('/product/') || lower.match(/\/[a-z0-9-]+\/?$/);
      if (!matchesScope && !isGenericProductUrl) return false;
    }
  }
  return true;
}

async function fetchSitemap(url: string, depth = 0): Promise<{url:string, lastmod?:string}[]> {
  if (depth > 2) return [];
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(20000) });
    if (!r.ok) return [];
    const xml = await r.text();
    const sitemapRefs: string[] = [];
    const sitemapRx = /<sitemap>[\s\S]*?<loc>([^<]+)<\/loc>[\s\S]*?<\/sitemap>/g;
    let sm;
    while ((sm = sitemapRx.exec(xml)) !== null) {
      sitemapRefs.push(sm[1].trim().replace(/&amp;/g, '&'));
    }
    if (sitemapRefs.length > 0) {
      const productRefs = sitemapRefs.filter(u => {
        const lower = u.toLowerCase();
        return lower.includes('product') || lower.includes('appliance') ||
               lower.includes('home-') || lower.includes('kitchen') ||
               lower.includes('laundry') || lower.includes('cooking');
      });
      const toFetch = productRefs.length > 0 ? productRefs : sitemapRefs;
      const results: {url:string, lastmod?:string}[] = [];
      const batch = toFetch.slice(0, 25);
      for (let i = 0; i < batch.length; i += 5) {
        const chunk = batch.slice(i, i + 5);
        const chunkResults = await Promise.all(chunk.map(ref => fetchSitemap(ref, depth + 1)));
        for (const cr of chunkResults) results.push(...cr);
      }
      return results;
    }
    const urls: {url:string, lastmod?:string}[] = [];
    const urlBlockRx = /<url>([\s\S]*?)<\/url>/g;
    let block;
    while ((block = urlBlockRx.exec(xml)) !== null) {
      const locMatch = block[1].match(/<loc>([^<]+)<\/loc>/);
      const modMatch = block[1].match(/<lastmod>([^<]+)<\/lastmod>/);
      if (locMatch) urls.push({ url: locMatch[1].trim().replace(/&amp;/g, '&'), lastmod: modMatch?.[1] });
    }
    if (urls.length === 0) {
      const locRx = /<loc>([^<]+)<\/loc>/g;
      let m;
      while ((m = locRx.exec(xml)) !== null) {
        const u = m[1].trim().replace(/&amp;/g, '&');
        if (!u.endsWith('.xml') && !u.endsWith('/sitemap')) urls.push({ url: u });
      }
    }
    return urls;
  } catch (_) { return []; }
}

async function searchProducts(brand: string, website: string | null): Promise<{url:string, title?:string}[]> {
  try {
    const query = website
      ? `site:${website} ${brand} products specifications`
      : `${brand} appliance products specifications`;
    const sq = encodeURIComponent(query);
    const r = await fetch(`https://lite.duckduckgo.com/lite/?q=${sq}`, {
      headers: { "User-Agent": UA, "Accept": "text/html" },
      signal: AbortSignal.timeout(10000)
    });
    if (!r.ok) return [];
    const html = await r.text();
    const urls: {url:string, title?:string}[] = [];
    const seen = new Set<string>();
    const urlRx = /uddg=([^&"]+)/g;
    let m;
    while ((m = urlRx.exec(html)) !== null) {
      try {
        const u = decodeURIComponent(m[1]);
        const lower = u.toLowerCase();
        if (lower.includes('amazon') || lower.includes('youtube') || lower.includes('reddit') ||
            lower.includes('wikipedia') || lower.includes('duckduckgo')) continue;
        if (!seen.has(u)) { seen.add(u); urls.push({ url: u }); }
      } catch (_) {}
    }
    return urls.slice(0, 20);
  } catch (_) { return []; }
}

function extractModelFromUrl(url: string): string | null {
  const parts = url.split('/').pop()?.split(/[?#]/)[0] || '';
  const clean = parts.replace(/-/g, ' ').replace(/\.html?$/, '');
  const modelMatch = clean.match(/\b([A-Z]{2,}[A-Z0-9-]{3,}[0-9]+[A-Z0-9]*)\b/i);
  return modelMatch ? modelMatch[1].toUpperCase() : null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { brand, appliances_only } = await req.json();
    if (!brand) return new Response(JSON.stringify({ error: "Provide brand name" }), { headers: CORS });
    const sbUrl = Deno.env.get("SUPABASE_URL") || "";
    const sbKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    const sb = createClient(sbUrl, sbKey);
    const { data: src } = await sb.from('scraper_brand_sources').select('*').ilike('brand_name', brand).maybeSingle();
    const productScope = src?.product_scope || [];
    const filterAppliances = appliances_only !== false;
    const results: {url:string, title?:string, model?:string|null, lastmod?:string, source:string, relevant:boolean}[] = [];
    const seen = new Set<string>();
    let filtered_count = 0;
    if (src?.sitemap_url) {
      const sitemapUrls = await fetchSitemap(src.sitemap_url);
      for (const su of sitemapUrls) {
        if (filterAppliances && !isRelevantUrl(su.url, productScope)) { filtered_count++; continue; }
        if (!seen.has(su.url)) {
          seen.add(su.url);
          results.push({ url: su.url, model: extractModelFromUrl(su.url), lastmod: su.lastmod, source: 'sitemap', relevant: true });
        }
      }
    }
    if (!src?.sitemap_url) {
      const website = src?.us_website || src?.ca_website;
      if (website) {
        const domain = website.startsWith('http') ? website : `https://www.${website}`;
        const guesses = [`${domain}/sitemap.xml`,`${domain}/sitemap_index.xml`,`${domain}/sitemap_products.xml`];
        for (const guess of guesses) {
          try {
            const sitemapUrls = await fetchSitemap(guess);
            if (sitemapUrls.length > 0) {
              if (src?.id) await sb.from('scraper_brand_sources').update({ sitemap_url: guess, updated_at: new Date().toISOString() }).eq('id', src.id);
              for (const su of sitemapUrls) {
                if (filterAppliances && !isRelevantUrl(su.url, productScope)) { filtered_count++; continue; }
                if (!seen.has(su.url)) {
                  seen.add(su.url);
                  results.push({ url: su.url, model: extractModelFromUrl(su.url), lastmod: su.lastmod, source: 'sitemap-auto', relevant: true });
                }
              }
              break;
            }
          } catch (_) {}
        }
      }
    }
    const website = src?.ca_website || src?.us_website;
    const searchUrls = await searchProducts(brand, website);
    for (const su of searchUrls) {
      if (filterAppliances && !isRelevantUrl(su.url, productScope)) { filtered_count++; continue; }
      if (!seen.has(su.url)) {
        seen.add(su.url);
        results.push({ url: su.url, title: su.title, model: extractModelFromUrl(su.url), source: 'search', relevant: true });
      }
    }
    const { data: existing } = await sb.from('aiq_products').select('model, source_reference').ilike('brand_name', brand).eq('status', 'active');
    const existingModels = new Set((existing || []).map(e => (e.model || '').toUpperCase()));
    const existingUrls = new Set((existing || []).map(e => e.source_reference).filter(Boolean));
    for (const r of results) {
      (r as any).in_pim = (r.model && existingModels.has(r.model.toUpperCase())) || existingUrls.has(r.url);
    }
    return new Response(JSON.stringify({
      brand, total: results.length,
      new_count: results.filter((r: any) => !r.in_pim).length,
      existing_count: results.filter((r: any) => r.in_pim).length,
      filtered_count, tier: src?.scrape_tier || 0,
      has_sitemap: !!src?.sitemap_url, server_fetchable: src?.server_fetchable || false,
      bot_protection: src?.bot_protection || null, product_scope: productScope,
      appliances_only: filterAppliances, results
    }), { headers: CORS });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { headers: CORS });
  }
});
