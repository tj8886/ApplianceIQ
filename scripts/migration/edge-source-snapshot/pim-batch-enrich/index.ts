// pim-batch-enrich v2 — JWT-protected
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface BrandConfig {
  domain: string;
  slugs: string[];
  buildUrl: (model: string, slug: string) => string;
}

const BRANDS: Record<string, BrandConfig> = {
  LG: {
    domain: "lg.com/us",
    slugs: ["cooking-appliances/ranges", "refrigerators", "refrigerators/french-door", "refrigerators/side-by-side", "refrigerators/bottom-freezer", "refrigerators/zero-clearance", "dishwashers", "dishwashers/front-control", "dishwashers/top-control", "laundry/washers", "laundry/dryers", "laundry/washtower", "cooking-appliances/wall-ovens", "cooking-appliances/cooktops", "cooking-appliances/microwave-ovens", "cooking-appliances/hoods"],
    buildUrl: (model, slug) => `https://www.lg.com/us/${slug}/${model.toLowerCase()}/`,
  },
  Bosch: {
    domain: "bosch-home.com/us",
    slugs: [""],
    buildUrl: (model) => `https://www.bosch-home.com/us/products/${model}.html`,
  },
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ ok: false, detail: "POST only" }, 405);

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const admin = createClient(url, service);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* */ }

  const brandName = String(body.brand ?? "LG");
  const limit = Math.min(Number(body.limit ?? 10), 20);
  const config = BRANDS[brandName];

  if (!config) {
    return reply({ ok: false, detail: `No config for ${brandName}. Available: ${Object.keys(BRANDS).join(", ")}` }, 400);
  }

  const { data: products } = await admin
    .from("aiq_products")
    .select("id,model,brand_name,category,short_description,msrp")
    .eq("brand_name", brandName)
    .or("short_description.is.null,msrp.is.null")
    .limit(limit);

  if (!products?.length) {
    return reply({ ok: true, brand: brandName, message: "No sparse products found", enriched: 0 });
  }

  const results: Array<{ model: string; status: string; fields_updated: string[] }> = [];

  for (const product of products) {
    const model = product.model;
    let enriched = false;
    let fieldsUpdated: string[] = [];

    for (const slug of config.slugs) {
      const productUrl = config.buildUrl(model, slug);
      try {
        const resp = await fetch(productUrl, {
          headers: { "User-Agent": "Mozilla/5.0 (compatible; ApplianceIQ/1.0; product-enrichment)", Accept: "text/html" },
          redirect: "follow",
        });
        if (!resp.ok) continue;
        const html = await resp.text();
        if (html.length < 1000) continue;

        const jsonLdMatches = [...html.matchAll(/<script type="application\/ld\+json">(.*?)<\/script>/gs)];
        let productData: Record<string, any> | null = null;
        for (const match of jsonLdMatches) {
          try {
            const parsed = JSON.parse(match[1]);
            const items = Array.isArray(parsed) ? parsed : [parsed];
            for (const item of items) {
              if (item["@type"] === "Product" || item["@type"]?.includes?.("Product")) { productData = item; break; }
            }
          } catch { continue; }
          if (productData) break;
        }
        if (!productData) {
          const descMatch = html.match(/<meta\s+(?:name|property)="(?:og:description|description)"\s+content="([^"]+)"/i);
          const priceMatch = html.match(/"price"\s*:\s*["']?([\d.]+)/i);
          const titleMatch = html.match(/<meta\s+(?:name|property)="og:title"\s+content="([^"]+)"/i);
          if (descMatch || priceMatch) productData = { description: descMatch?.[1], name: titleMatch?.[1], offers: priceMatch ? { price: priceMatch[1] } : undefined };
        }
        if (productData) {
          const updates: Record<string, any> = {};
          const desc = productData.description ?? productData.name;
          if (desc && (!product.short_description || product.short_description === "")) { updates.short_description = String(desc).slice(0, 500); fieldsUpdated.push("short_description"); }
          const price = productData.offers?.price ?? productData.offers?.lowPrice ?? productData.offers?.[0]?.price;
          if (price && !product.msrp) { const numPrice = parseFloat(String(price)); if (numPrice > 0 && numPrice < 50000) { updates.msrp = numPrice; fieldsUpdated.push("msrp"); } }
          if (Object.keys(updates).length > 0) { updates.updated_at = new Date().toISOString(); await admin.from("aiq_products").update(updates).eq("id", product.id); enriched = true; }
          results.push({ model, status: enriched ? "enriched" : "no_new_data", fields_updated: fieldsUpdated });
          break;
        }
      } catch { continue; }
    }
    if (!enriched) results.push({ model, status: "not_found", fields_updated: [] });
    await new Promise(r => setTimeout(r, 500));
  }

  return reply({ ok: true, brand: brandName, processed: results.length, enriched: results.filter(r => r.status === "enriched").length, results });
});

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}
