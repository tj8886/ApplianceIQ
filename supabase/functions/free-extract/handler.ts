import {createPublicPimFetch,approvedPimUrl} from '../_shared/pim-public-fetch.ts';
export function createHandler({createClient,env,fetchImpl=fetch}:{createClient:any;env:(n:string)=>string|undefined;fetchImpl?:typeof fetch}){
const fetch=createPublicPimFetch(fetchImpl);

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
const HEADERS: Record<string, string> = { "User-Agent": UA, "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Accept-Language": "en-US,en;q=0.9" };

const sitemapCache: Record<string, string[]> = {};

async function fetchSitemap(url: string, cacheKey: string): Promise<string[]> {
  if (sitemapCache[cacheKey]) return sitemapCache[cacheKey];
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA }, signal: AbortSignal.timeout(10000) });
    if (!r.ok) return [];
    const xml = await r.text();
    const urls: string[] = [];
    let m; const p = /<loc>([^<]+)<\/loc>/g;
    while ((m = p.exec(xml)) !== null) urls.push(m[1]);
    sitemapCache[cacheKey] = urls;
    return urls;
  } catch (_) { return []; }
}

async function tryDirectUrl(brand: string, model: string, market: string): Promise<string | null> {
  const ml = model.toLowerCase();
  const mu = model.toUpperCase();
  const bl = brand.toLowerCase().replace(/[^a-z]/g, "");
  const h = { "User-Agent": UA };
  if (bl === "lg" || bl === "lgstudio") {
    const slugs = ["refrigerators","refrigerators/french-door","refrigerators/side-by-side","refrigerators/top-freezer","refrigerators/bottom-freezer","cooking-appliances/ranges","cooking-appliances/wall-ovens","cooking-appliances/cooktops","cooking-appliances/microwave-ovens","cooking-appliances/hoods","dishwashers","dishwashers/front-control","dishwashers/top-control","laundry/washers","laundry/dryers","laundry/washtower","laundry/washer-dryer-combos"];
    const doms = market==="CA" ? ["www.lg.com/ca_en","www.lg.com/us"] : ["www.lg.com/us","www.lg.com/ca_en"];
    for (const dom of doms) { for (const s of slugs) { try { const u = `https://${dom}/${s}/${ml}/`; const r = await fetch(u, { headers: h, method:"HEAD", signal: AbortSignal.timeout(4000), redirect:"manual" }); if (r.status===200||r.status===301||r.status===302||r.status===308) return u; } catch (_) {} } }
  }
  if (bl === "bosch") { const doms = market==="CA" ? ["www.bosch-home.ca/en","www.bosch-home.com/us"] : ["www.bosch-home.com/us","www.bosch-home.ca/en"]; for (const dom of doms) { try { const u = `https://${dom}/products/${mu}.html`; const r = await fetch(u, { headers: h, method:"HEAD", signal: AbortSignal.timeout(4000), redirect:"manual" }); if (r.status===200||r.status===301||r.status===302) return r.headers.get("location")||u; } catch (_) {} } }
  if (bl === "thermador") { try { const u = `https://www.thermador.com/us/products/${mu}.html`; const r = await fetch(u, { headers: h, method:"HEAD", signal: AbortSignal.timeout(4000), redirect:"manual" }); if (r.status===200||r.status===301||r.status===302) return r.headers.get("location")||u; } catch (_) {} }
  if (bl === "broan" || bl === "broannutone" || bl === "nutone") { const urls = await fetchSitemap("https://broan-nutone.com/en-ca/sitemap.xml", "broan"); for (const u of urls) { if (u.toLowerCase().includes(ml) && u.includes("/product/")) return u; } }
  if (bl === "blomberg") { const urls = await fetchSitemap("https://www.blombergappliances.com/sitemap_products_1.xml?from=6910324637883&to=8455450296507", "blomberg"); for (const u of urls) { if (u.toLowerCase().includes(ml)) return u; } }
  return null;
}

// === DOCUMENT EXTRACTION ===
const DOC_KEYWORDS: Record<string, string> = {
  'manual': 'owners_manual', 'owner': 'owners_manual', 'user-guide': 'owners_manual', 'user_guide': 'owners_manual',
  'installation': 'installation_guide', 'install-guide': 'installation_guide', 'install_guide': 'installation_guide',
  'quick-start': 'quick_start_guide', 'quickstart': 'quick_start_guide',
  'warranty': 'warranty', 'energy': 'energy_guide', 'energyguide': 'energy_guide', 'energy-guide': 'energy_guide',
  'spec-sheet': 'spec_sheet', 'spec_sheet': 'spec_sheet', 'specification': 'spec_sheet',
  'dimensions': 'dimension_guide', 'dimensional': 'dimension_guide', 'cutout': 'dimension_guide',
  'brochure': 'brochure', 'catalog': 'brochure', 'catalogue': 'brochure',
  'datasheet': 'spec_sheet', 'data-sheet': 'spec_sheet',
  'safety': 'safety_info', 'troubleshoot': 'troubleshooting',
  'care': 'care_guide', 'maintenance': 'care_guide',
  'wiring': 'wiring_diagram', 'diagram': 'wiring_diagram',
};

function classifyDocType(url: string, linkText: string): string {
  const combined = (url + ' ' + linkText).toLowerCase();
  for (const [keyword, docType] of Object.entries(DOC_KEYWORDS)) {
    if (combined.includes(keyword)) return docType;
  }
  return 'other';
}

function extractDocuments(html: string, sourceUrl: string): Array<{url: string, title: string, doc_type: string, file_name: string}> {
  const docs: Array<{url: string, title: string, doc_type: string, file_name: string}> = [];
  const seen = new Set<string>();
  const baseUrl = new URL(sourceUrl).origin;
  
  function resolveUrl(u: string): string {
    if (u.startsWith('http')) return u;
    if (u.startsWith('//')) return 'https:' + u;
    if (u.startsWith('/')) return baseUrl + u;
    return baseUrl + '/' + u;
  }
  
  // <a> tags with PDF hrefs
  const linkRx = /<a\s[^>]*href\s*=\s*["']([^"']*\.pdf[^"']*)["'][^>]*>(.*?)<\/a>/gi;
  let m;
  while ((m = linkRx.exec(html)) !== null) {
    const url = resolveUrl(m[1].trim());
    const text = m[2].replace(/<[^>]+>/g, '').trim();
    if (!seen.has(url)) {
      seen.add(url);
      const fileName = url.split('/').pop()?.split('?')[0] || 'document.pdf';
      docs.push({ url, title: text || fileName.replace('.pdf', '').replace(/[-_]/g, ' '), doc_type: classifyDocType(url, text), file_name: fileName });
    }
  }
  // All href PDFs
  const hrefRx = /href\s*=\s*["']([^"']*\.pdf[^"']*)["']/gi;
  while ((m = hrefRx.exec(html)) !== null) {
    const url = resolveUrl(m[1].trim());
    if (!seen.has(url)) { seen.add(url); const fn = url.split('/').pop()?.split('?')[0] || 'document.pdf'; docs.push({ url, title: fn.replace('.pdf', '').replace(/[-_]/g, ' '), doc_type: classifyDocType(url, ''), file_name: fn }); }
  }
  // Inline string PDFs
  const dataRx = /["'](https?:\/\/[^"']*\.pdf[^"']*)["']/gi;
  while ((m = dataRx.exec(html)) !== null) {
    const url = m[1].trim();
    if (!seen.has(url) && !url.includes('webpack') && !url.includes('chunk')) { seen.add(url); const fn = url.split('/').pop()?.split('?')[0] || 'document.pdf'; docs.push({ url, title: fn.replace('.pdf', '').replace(/[-_]/g, ' '), doc_type: classifyDocType(url, ''), file_name: fn }); }
  }
  return docs;
}

// === VIDEO EXTRACTION ===
function extractVideos(html: string, sourceUrl: string): Array<{url: string, embed_url?: string, title?: string, type: string, platform: string, video_id?: string, thumbnail?: string}> {
  const videos: Array<{url: string, embed_url?: string, title?: string, type: string, platform: string, video_id?: string, thumbnail?: string}> = [];
  const seen = new Set<string>();
  let m;
  
  // YouTube embeds: iframe src
  const ytEmbedRx = /(?:src|data-src)\s*=\s*["'](?:https?:)?\/\/(?:www\.)?youtube(?:-nocookie)?\.com\/embed\/([a-zA-Z0-9_-]{11})[^"']*["']/gi;
  while ((m = ytEmbedRx.exec(html)) !== null) {
    const vid = m[1];
    if (!seen.has(vid)) { seen.add(vid); videos.push({ url: `https://www.youtube.com/watch?v=${vid}`, embed_url: `https://www.youtube.com/embed/${vid}`, type: 'product_overview', platform: 'youtube', video_id: vid, thumbnail: `https://img.youtube.com/vi/${vid}/hqdefault.jpg` }); }
  }
  // YouTube links
  const ytLinkRx = /(?:youtube\.com\/watch\?v=|youtu\.be\/)([a-zA-Z0-9_-]{11})/gi;
  while ((m = ytLinkRx.exec(html)) !== null) {
    const vid = m[1];
    if (!seen.has(vid)) { seen.add(vid); videos.push({ url: `https://www.youtube.com/watch?v=${vid}`, embed_url: `https://www.youtube.com/embed/${vid}`, type: 'product_overview', platform: 'youtube', video_id: vid, thumbnail: `https://img.youtube.com/vi/${vid}/hqdefault.jpg` }); }
  }
  // Vimeo embeds
  const vimeoRx = /(?:player\.)?vimeo\.com\/(?:video\/|embed\/)?([0-9]+)/gi;
  while ((m = vimeoRx.exec(html)) !== null) {
    const vid = m[1];
    if (!seen.has('vimeo-'+vid)) { seen.add('vimeo-'+vid); videos.push({ url: `https://vimeo.com/${vid}`, embed_url: `https://player.vimeo.com/video/${vid}`, type: 'product_overview', platform: 'vimeo', video_id: vid }); }
  }
  // Direct video files
  const vidFileRx = /["'](https?:\/\/[^"']+\.(?:mp4|webm|m3u8)[^"']*)["']/gi;
  while ((m = vidFileRx.exec(html)) !== null) {
    const url = m[1];
    if (!seen.has(url) && !url.includes('analytics') && !url.includes('tracking')) { seen.add(url); videos.push({ url, type: 'product_overview', platform: 'direct' }); }
  }
  // Wistia
  const wistiaRx = /wistia\.(?:com|net)\/(?:medias|embed)\/([a-z0-9]+)/gi;
  while ((m = wistiaRx.exec(html)) !== null) {
    const vid = m[1];
    if (!seen.has('wistia-'+vid)) { seen.add('wistia-'+vid); videos.push({ url: `https://fast.wistia.com/medias/${vid}`, embed_url: `https://fast.wistia.com/embed/medias/${vid}`, type: 'product_overview', platform: 'wistia', video_id: vid }); }
  }
  return videos;
}

// === IMAGE EXTRACTION (comprehensive) ===
function extractAllImages(html: string, sourceUrl: string, jsonLdImages?: Array<{url:string,type:string}>): Array<{url:string, type:string, alt?:string}> {
  const images: Array<{url:string, type:string, alt?:string}> = [];
  const seen = new Set<string>();
  const baseUrl = new URL(sourceUrl).origin;
  
  function resolveUrl(u: string): string {
    if (u.startsWith('http')) return u;
    if (u.startsWith('//')) return 'https:' + u;
    if (u.startsWith('/')) return baseUrl + u;
    return u;
  }
  function isGoodImage(u: string): boolean {
    const l = u.toLowerCase();
    return !l.includes('icon') && !l.includes('logo') && !l.includes('favicon') && !l.includes('pixel') &&
           !l.includes('tracking') && !l.includes('analytics') && !l.includes('badge') && !l.includes('flag') &&
           !l.includes('payment') && !l.includes('sprite') && !l.includes('spacer') && !l.includes('placeholder') &&
           !l.includes('data:image') && !l.includes('svg+xml') &&
           (l.includes('.jpg') || l.includes('.jpeg') || l.includes('.png') || l.includes('.webp') || l.includes('.avif'));
  }
  function classifyImage(url: string, alt: string): string {
    const combined = (url + ' ' + alt).toLowerCase();
    if (combined.includes('lifestyle') || combined.includes('kitchen') || combined.includes('room') || combined.includes('installed')) return 'lifestyle';
    if (combined.includes('dimension') || combined.includes('cutout') || combined.includes('spec')) return 'dimension_diagram';
    if (combined.includes('interior') || combined.includes('inside')) return 'interior';
    if (combined.includes('close') || combined.includes('detail') || combined.includes('feature')) return 'feature_detail';
    if (combined.includes('gallery') || combined.includes('alternate') || combined.includes('angle')) return 'gallery';
    if (combined.includes('swatch') || combined.includes('color') || combined.includes('finish')) return 'swatch';
    return 'product';
  }
  
  // 1. JSON-LD images first (highest quality)
  if (jsonLdImages) {
    for (const img of jsonLdImages) {
      const url = resolveUrl(img.url);
      if (!seen.has(url)) { seen.add(url); images.push({ url, type: img.type || 'product' }); }
    }
  }
  
  // 2. OG image
  const ogI = (html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i)||[])[1];
  if (ogI) { const url = resolveUrl(ogI); if (!seen.has(url)) { seen.add(url); images.push({ url, type: 'hero' }); } }
  
  // 3. <img> tags
  const imgRx = /<img\s[^>]*src\s*=\s*["']([^"']+)["'][^>]*/gi;
  let m;
  while ((m = imgRx.exec(html)) !== null) {
    const src = resolveUrl(m[1]);
    const alt = (m[0].match(/alt\s*=\s*["']([^"']*)["']/i)||[])[1] || '';
    if (!seen.has(src) && isGoodImage(src)) {
      seen.add(src);
      images.push({ url: src, type: classifyImage(src, alt), alt });
    }
  }
  // 4. data-src / data-lazy-src (lazy loaded)
  const lazySrcRx = /data-(?:src|lazy-src|original|zoom-image|full-image)\s*=\s*["']([^"']+)["']/gi;
  while ((m = lazySrcRx.exec(html)) !== null) {
    const src = resolveUrl(m[1]);
    if (!seen.has(src) && isGoodImage(src)) { seen.add(src); images.push({ url: src, type: 'product' }); }
  }
  // 5. srcset (grab largest)
  const srcsetRx = /srcset\s*=\s*["']([^"']+)["']/gi;
  while ((m = srcsetRx.exec(html)) !== null) {
    const parts = m[1].split(',').map(s => s.trim()).filter(Boolean);
    if (parts.length > 0) {
      const last = parts[parts.length - 1].split(/\s+/)[0]; // largest
      const src = resolveUrl(last);
      if (!seen.has(src) && isGoodImage(src)) { seen.add(src); images.push({ url: src, type: 'product' }); }
    }
  }
  // 6. background images in style
  const bgRx = /url\(["']?([^"')]+\.(?:jpg|jpeg|png|webp)[^"')]*)["']?\)/gi;
  while ((m = bgRx.exec(html)) !== null) {
    const src = resolveUrl(m[1]);
    if (!seen.has(src) && isGoodImage(src)) { seen.add(src); images.push({ url: src, type: 'lifestyle' }); }
  }
  // 7. JSON strings containing image URLs (React/Vue hydration)
  const jsonImgRx = /["'](https?:\/\/[^"']+\.(?:jpg|jpeg|png|webp|avif)(?:\?[^"']*)?)["']/gi;
  while ((m = jsonImgRx.exec(html)) !== null) {
    const src = m[1];
    if (!seen.has(src) && isGoodImage(src) && images.length < 30) { seen.add(src); images.push({ url: src, type: 'product' }); }
  }
  
  return images;
}

// === FEATURE EXTRACTION ===
function extractFeatures(html: string): string[] {
  const features: string[] = [];
  const seen = new Set<string>();
  let m;
  // Look for feature lists (common patterns)
  // <li> inside feature/benefit sections
  const featureSections = html.match(/(?:features|benefits|highlights|key-features)[^>]*>[\s\S]*?<\/(?:div|section|ul)>/gi) || [];
  for (const section of featureSections) {
    const liRx = /<li[^>]*>(.*?)<\/li>/gi;
    while ((m = liRx.exec(section)) !== null) {
      const text = m[1].replace(/<[^>]+>/g, '').trim();
      if (text.length > 10 && text.length < 300 && !seen.has(text.toLowerCase())) {
        seen.add(text.toLowerCase());
        features.push(text);
      }
    }
  }
  return features;
}

function extractProductData(html: string, sourceUrl: string): Record<string, any> {
  const result: Record<string, any> = { _freeData: true, source_url: sourceUrl };
  let jsonLdImages: Array<{url:string,type:string}> | undefined;
  
  // Standard JSON-LD
  const ldRx = /<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let ldM;
  while ((ldM = ldRx.exec(html)) !== null) {
    try {
      let ld = JSON.parse(ldM[1].trim());
      if (ld["@graph"]) ld = ld["@graph"].find((g: any) => /^product$/i.test(g["@type"])) || ld;
      if (Array.isArray(ld)) ld = ld.find((g: any) => /^product$/i.test(g["@type"])) || ld[0];
      if (/^product$/i.test(ld["@type"])||ld.sku||ld.mpn||ld.gtin13) {
        result.brand_name=ld.brand?.name||ld.brand||"";
        result.model=ld.mpn||ld.sku||ld.model||"";
        result.short_description=ld.description||ld.name||"";
        result.manufacturer_name=ld.manufacturer?.name||ld.brand?.name||ld.brand||"";
        if(ld.name) result.product_name=ld.name;
        if(ld.gtin13) result.gtin13=ld.gtin13;
        if(ld.gtin12) result.upc=ld.gtin12;
        if(ld.image){const i=Array.isArray(ld.image)?ld.image:[ld.image]; jsonLdImages=i.map((u:any)=>({url:typeof u==="string"?u:u.url||u.contentUrl,type:"product"}));}
        const o=ld.offers; if(o){const p=o.price||(Array.isArray(o)?o[0]?.price:null); if(p)result.msrp=parseFloat(p); result.currency=o.priceCurrency||(Array.isArray(o)?o[0]?.priceCurrency:"")||""; const a=o.availability||(Array.isArray(o)?o[0]?.availability:"")||""; if(a)result.availability=a.includes("InStock")?"In Stock":a.includes("OutOfStock")?"Out of Stock":a;}
        if(ld.color)result.color=ld.color;
        if(ld.weight)result.weight_lbs=typeof ld.weight==="object"?parseFloat(ld.weight.value):parseFloat(ld.weight);
        if(ld.width)result.width_inches=typeof ld.width==="object"?parseFloat(ld.width.value):parseFloat(ld.width);
        if(ld.height)result.height_inches=typeof ld.height==="object"?parseFloat(ld.height.value):parseFloat(ld.height);
        if(ld.depth)result.depth_inches=typeof ld.depth==="object"?parseFloat(ld.depth.value):parseFloat(ld.depth);
        if(ld.category)result.category=ld.category;
        if(ld.aggregateRating){result.rating=ld.aggregateRating.ratingValue;result.review_count=ld.aggregateRating.reviewCount;}
        result._jsonld=true;
      }
    } catch(_){}
  }
  // Next.js dehydrated JSON-LD
  if(!result._jsonld){
    const nr=/"type"\s*:\s*"application\/ld\+json"[^}]*"children"\s*:\s*"((?:[^"\\]|\\.)*)"/g; let nm;
    while((nm=nr.exec(html))!==null){
      try{
        const js=nm[1]; if(!js) continue;
        const ld=JSON.parse(js.replace(/\\"/g,'"').replace(/\\\\/g,'\\'));
        if(/^product$/i.test(ld["@type"])||ld.mpn||ld.sku){
          result.brand_name=ld.brand?.name||ld.brand||""; result.model=ld.mpn||ld.sku||ld.model||"";
          result.short_description=ld.description||ld.name||""; result.manufacturer_name=ld.brand?.name||ld.brand||"";
          if(ld.name)result.product_name=ld.name;
          if(ld.image){const i=Array.isArray(ld.image)?ld.image:[ld.image]; jsonLdImages=i.map((u:any)=>({url:typeof u==="string"?u:u.url,type:"product"}));}
          const o=ld.offers; if(o){const p=o.price||(Array.isArray(o)?o[0]?.price:null); if(p)result.msrp=parseFloat(p); result.currency=o.priceCurrency||""; const a=o.availability||""; if(a)result.availability=a.includes("InStock")?"In Stock":"Out of Stock";}
          result._jsonld=true; break;
        }
      } catch(_){}
    }
  }
  // OG + meta
  const ogT=(html.match(/<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']/i)||[])[1];
  const ogD=(html.match(/<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']+)["']/i)||[])[1];
  if(ogT&&!result.short_description)result.short_description=ogT;
  if(ogD)result.og_description=ogD;
  const md=(html.match(/<meta[^>]*name=["']description["'][^>]*content=["']([^"']+)["']/i)||[])[1];
  if(md&&!result.og_description)result.og_description=md;
  const pt=(html.match(/<title[^>]*>([^<]+)<\/title>/i)||[])[1];
  if(pt&&!result.product_name)result.product_name=pt.trim();
  
  // Spec tables
  const specs: Record<string,string>={}; let m;
  const rp=/<t[hd][^>]*>\s*(.*?)\s*<\/t[hd]>\s*<t[hd][^>]*>\s*(.*?)\s*<\/t[hd]>/gi;
  while((m=rp.exec(html))!==null){const k=m[1].replace(/<[^>]+>/g,"").trim();const v=m[2].replace(/<[^>]+>/g,"").trim();if(k&&v&&k.length<80&&v.length<200&&k.length>1)specs[k]=v;}
  const dp=/<dt[^>]*>\s*(.*?)\s*<\/dt>\s*<dd[^>]*>\s*(.*?)\s*<\/dd>/gi;
  while((m=dp.exec(html))!==null){const k=m[1].replace(/<[^>]+>/g,"").trim();const v=m[2].replace(/<[^>]+>/g,"").trim();if(k&&v&&k.length<80&&v.length<200&&k.length>1)specs[k]=v;}
  if(Object.keys(specs).length>0){
    result.specs=specs;
    for(const[k,v]of Object.entries(specs)){const kl=k.toLowerCase();
      if(kl.includes("width")&&!result.width_inches){const n=parseFloat(v);if(n>0&&n<100)result.width_inches=n;}
      if(kl.includes("height")&&!result.height_inches){const n=parseFloat(v);if(n>0&&n<120)result.height_inches=n;}
      if(kl.includes("depth")&&!result.depth_inches){const n=parseFloat(v);if(n>0&&n<100)result.depth_inches=n;}
      if(kl.includes("weight")&&!result.weight_lbs){const n=parseFloat(v);if(n>0)result.weight_lbs=n;}
      if((kl.includes("capacity")||kl.includes("cu"))&&!result.capacity_cu_ft){const n=parseFloat(v);if(n>0&&n<50)result.capacity_cu_ft=n;}
      if(kl.includes("voltage")&&!result.voltage){const n=parseFloat(v);if(n>0)result.voltage=n;}
      if(kl.includes("amperage")||kl.includes("amps")&&!result.amperage){const n=parseFloat(v);if(n>0)result.amperage=n;}
      if(kl.includes("wattage")||kl.includes("watts")&&!result.wattage){const n=parseFloat(v);if(n>0)result.wattage=n;}
      if((kl.includes("upc")||kl.includes("gtin"))&&!result.upc)result.upc=v;
      if(kl.includes("energy star")&&!result.energy_star)result.energy_star=v.toLowerCase().includes('yes')||v.toLowerCase().includes('true');
      if(kl.includes("finish")&&!result.finish)result.finish=v;
      if(kl.includes("color")&&!result.color)result.color=v;
    }
    result._specTable=true; result._specCount=Object.keys(specs).length;
  }
  
  // === COMPREHENSIVE IMAGE EXTRACTION ===
  result.images = extractAllImages(html, sourceUrl, jsonLdImages);
  result._imageCount = result.images.length;
  
  // === DOCUMENT EXTRACTION ===
  const documents = extractDocuments(html, sourceUrl);
  if (documents.length > 0) { result.documents = documents; result._docCount = documents.length; }
  
  // === VIDEO EXTRACTION ===
  const videos = extractVideos(html, sourceUrl);
  if (videos.length > 0) { result.videos = videos; result._videoCount = videos.length; }
  
  // === FEATURE EXTRACTION ===
  const features = extractFeatures(html);
  if (features.length > 0) { result.features = features; result._featureCount = features.length; }
  
  return result;
}

async function fetchPage(url: string): Promise<string|null> {
  try { const c=new AbortController(); const t=setTimeout(()=>c.abort(),20000); const r=await fetch(url,{signal:c.signal,headers:HEADERS,redirect:"follow"}); clearTimeout(t); if(!r.ok)return null; return await r.text(); } catch(_){return null;}
}

return async (req:Request) => {
  if (req.method==="OPTIONS") return new Response("ok",{headers:CORS});
  try {
    if(req.method!=='POST')return new Response(JSON.stringify({error:'method_not_allowed'}),{status:405,headers:CORS});
    const authorization=req.headers.get('Authorization')??'';if(!authorization.startsWith('Bearer '))return new Response(JSON.stringify({error:'authentication_required'}),{status:401,headers:CORS});
    const user=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
    const identity=await user.auth.getUser();if(identity.error||!identity.data?.user)return new Response(JSON.stringify({error:'invalid_session'}),{status:401,headers:CORS});
    const scope=await user.rpc('tj_pim_scraper_context');if(scope.error||!scope.data?.allowed)return new Response(JSON.stringify({error:'product_governance_required'}),{status:403,headers:CORS});
    const raw=await req.text();if(raw.length>8192)return new Response(JSON.stringify({error:'request_too_large'}),{status:413,headers:CORS});
    let body;try{body=JSON.parse(raw);}catch{return new Response(JSON.stringify({error:'invalid_json'}),{status:400,headers:CORS});}
    if(!body||typeof body!=='object'||Array.isArray(body))return new Response(JSON.stringify({error:'invalid_request'}),{status:400,headers:CORS});

    const {url,query,market}=body;
    if(url!==undefined){try{approvedPimUrl(url);}catch{return new Response(JSON.stringify({error:'url_not_allowed'}),{status:400,headers:CORS});}}
    if(query!==undefined&&(typeof query!=='string'||query.length>240)||market!==undefined&&!['CA','US'].includes(market))return new Response(JSON.stringify({error:'invalid_query'}),{status:400,headers:CORS});
    if (url && /^https?:\/\//i.test(url)) {
      const html = await fetchPage(url);
      if (!html||html.length<200) return new Response(JSON.stringify({found:false,error:"Could not fetch page"}),{headers:CORS});
      const result = extractProductData(html, url);result.evidence_status="unreviewed_extraction";result.requires_review=true;
      const ok=(result._jsonld&&result.model)||(result._specTable&&(result._specCount||0)>=5);
      if(ok){result.found=true;result._source="free-extract";return new Response(JSON.stringify(result),{headers:CORS});}
      if(result._jsonld||result._specTable||result.short_description){result._partial=true;result._source="free-extract-partial";return new Response(JSON.stringify(result),{headers:CORS});}
      return new Response(JSON.stringify({found:false,error:"No structured product data found",_source:"free-extract-empty"}),{headers:CORS});
    }
    if (query) {
      const mkt = market||"CA";
      const parts = query.trim().split(/\s+/);
      let brand=""; let modelNum=query.trim();
      if(parts.length>=2){brand=parts[0];modelNum=parts.slice(1).join(" ");}
      if(brand){
        const directUrl = await tryDirectUrl(brand, modelNum, mkt);
        if(directUrl){
          const html = await fetchPage(directUrl);
          if(html&&html.length>200){
            const result = extractProductData(html, directUrl);result.evidence_status="unreviewed_extraction";result.requires_review=true;
            result._searchQuery=query;
            const ok=(result._jsonld&&result.model)||(result._specTable&&(result._specCount||0)>=5);
            if(ok){result.found=true;result._source="free-direct-url";return new Response(JSON.stringify(result),{headers:CORS});}
            if(result._jsonld||result._specTable||result.short_description){result._partial=true;result._source="free-direct-partial";return new Response(JSON.stringify(result),{headers:CORS});}
          }
        }
      }
      try{
        const sq=encodeURIComponent(query+" product specifications");
        const r=await fetch(`https://lite.duckduckgo.com/lite/?q=${sq}`,{headers:{"User-Agent":UA,"Accept":"text/html"},signal:AbortSignal.timeout(10000)});
        if(r.ok){
          const shtml=await r.text(); const urls:string[]=[]; let m;
          const p1=/uddg=([^&"]+)/g;
          while((m=p1.exec(shtml))!==null){try{urls.push(decodeURIComponent(m[1]));}catch(_){}}
          for(const u of urls){
            try{approvedPimUrl(u);}catch{continue;}
            const l=u.toLowerCase();
            if(!l.includes("amazon")&&!l.includes("youtube")&&!l.includes("reddit")&&!l.includes("homedepot")&&!l.includes("lowes")&&!l.includes("bestbuy")&&!l.includes("walmart")&&!l.includes("costco")&&!l.includes("duckduckgo")){
              const html=await fetchPage(u);
              if(html&&html.length>200){
                const result=extractProductData(html,u);result.evidence_status="unreviewed_extraction";result.requires_review=true; result._searchQuery=query;
                const ok=(result._jsonld&&result.model)||(result._specTable&&(result._specCount||0)>=5);
                if(ok){result.found=true;result._source="free-search-extract";return new Response(JSON.stringify(result),{headers:CORS});}
                if(result._jsonld||result._specTable){result._partial=true;result._source="free-search-partial";return new Response(JSON.stringify(result),{headers:CORS});}
              }
              break;
            }
          }
        }
      }catch(_){}
      return new Response(JSON.stringify({found:false,error:"Could not find product via direct URL or search",_source:"search-miss"}),{headers:CORS});
    }
    return new Response(JSON.stringify({found:false,error:"Provide 'url' or 'query'"}),{headers:CORS});
  } catch(e){
    return new Response(JSON.stringify({found:false,error:`Error: ${(e as Error).message}`}),{headers:CORS});
  }
};
}
