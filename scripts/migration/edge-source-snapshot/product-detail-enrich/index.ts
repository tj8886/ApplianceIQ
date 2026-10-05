import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SB_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  
  try {
    const { product_id, url, batch_size } = await req.json();
    const sb = createClient(SB_URL, SB_KEY);
    let results: any[] = [];

    // MODE 1: Enrich a single product by ID
    if (product_id) {
      const r = await enrichProduct(sb, product_id, url);
      return new Response(JSON.stringify(r), { headers: CORS });
    }

    // MODE 2: Batch — find products needing enrichment and process them
    const limit = Math.min(batch_size || 10, 50);
    
    // Find products with retailer URLs but no images AND no specs
    const { data: candidates } = await sb.rpc('get_enrichment_candidates', { p_limit: limit });
    
    // Fallback if RPC doesn't exist: direct query
    let toEnrich = candidates;
    if (!toEnrich || toEnrich.length === 0) {
      const { data } = await sb
        .from('pim_retailer_prices')
        .select('product_id, product_url')
        .not('product_url', 'is', null)
        .not('product_id', 'is', null)
        .order('product_id')
        .limit(limit * 3);
      
      if (data) {
        // Deduplicate by product_id, pick first URL
        const seen = new Set<string>();
        const unique: any[] = [];
        for (const row of data) {
          if (!seen.has(row.product_id)) {
            seen.add(row.product_id);
            unique.push(row);
          }
        }
        // Filter to products without images
        const filtered: any[] = [];
        for (const row of unique) {
          if (filtered.length >= limit) break;
          const { count } = await sb.from('pim_product_images').select('id', { count: 'exact', head: true }).eq('product_id', row.product_id);
          if ((count || 0) === 0) filtered.push(row);
        }
        toEnrich = filtered;
      }
    }

    if (!toEnrich || toEnrich.length === 0) {
      return new Response(JSON.stringify({ message: 'No candidates found', enriched: 0 }), { headers: CORS });
    }

    for (const candidate of toEnrich) {
      try {
        const r = await enrichProduct(sb, candidate.product_id, candidate.product_url);
        results.push(r);
      } catch (e) {
        results.push({ product_id: candidate.product_id, error: (e as Error).message });
      }
    }

    return new Response(JSON.stringify({ enriched: results.filter(r => r.success).length, total: results.length, results }), { headers: CORS });

  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), { headers: CORS, status: 500 });
  }
});

async function enrichProduct(sb: any, productId: string, overrideUrl?: string): Promise<any> {
  // Get product
  const { data: product } = await sb.from('aiq_products').select('id, brand_name, model, specs_json').eq('id', productId).maybeSingle();
  if (!product) return { product_id: productId, success: false, error: 'Product not found' };

  // Get best URL: prefer manufacturer sites, then major retailers
  let pageUrl = overrideUrl;
  if (!pageUrl) {
    const { data: prices } = await sb
      .from('pim_retailer_prices')
      .select('product_url, retailer_name')
      .eq('product_id', productId)
      .not('product_url', 'is', null)
      .order('retailer_name');
    
    if (!prices || prices.length === 0) return { product_id: productId, success: false, error: 'No URLs' };
    
    // Prefer CAS, Trail, Tasco, Goemans (richer pages), then others
    const priority = ['Canadian Appliance Source', 'Trail Appliances BC', 'Trail Appliances AB', 'Tasco Appliances', 'Goemans Appliances', 'Appliance Canada', 'TA Appliance'];
    let best = prices[0];
    for (const pref of priority) {
      const found = prices.find((p: any) => p.retailer_name === pref);
      if (found) { best = found; break; }
    }
    pageUrl = best.product_url;
  }

  if (!pageUrl) return { product_id: productId, success: false, error: 'No URL found' };

  // Call free-extract on the URL
  const extractUrl = `${SB_URL}/functions/v1/free-extract`;
  const extractResp = await fetch(extractUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ url: pageUrl }),
  });
  const extracted = await extractResp.json();

  if (!extracted || (!extracted.found && !extracted._partial)) {
    return { product_id: productId, success: false, error: 'Extraction returned no data', url: pageUrl };
  }

  let imagesAdded = 0, docsAdded = 0, videosAdded = 0, featuresAdded = 0, specsUpdated = false;

  // 1. Write specs back to aiq_products (only fill blanks)
  const updates: Record<string, any> = {};
  if (extracted.width_inches && !product.width_inches) updates.width_inches = extracted.width_inches;
  if (extracted.height_inches && !product.height_inches) updates.height_inches = extracted.height_inches;
  if (extracted.depth_inches && !product.depth_inches) updates.depth_inches = extracted.depth_inches;
  if (extracted.weight_lbs && !product.weight_lbs) updates.weight_lbs = extracted.weight_lbs;
  if (extracted.capacity_cu_ft && !product.capacity_cu_ft) updates.capacity_cu_ft = extracted.capacity_cu_ft;
  if (extracted.voltage && !product.voltage) updates.voltage = String(extracted.voltage);
  if (extracted.color && !product.color) updates.color = extracted.color;
  if (extracted.finish && !product.finish) updates.finish = extracted.finish;
  if (extracted.energy_star !== undefined && product.energy_star === null) updates.energy_star = extracted.energy_star;
  if (extracted.upc && !product.upc) updates.upc = extracted.upc;
  if (extracted.short_description && (!product.short_description || product.short_description.length < 20)) updates.short_description = extracted.short_description;
  
  // Merge specs_json
  if (extracted.specs && Object.keys(extracted.specs).length > 0) {
    const existing = (product.specs_json && typeof product.specs_json === 'object') ? product.specs_json : {};
    const merged = { ...extracted.specs, ...existing }; // existing takes priority
    if (Object.keys(merged).length > Object.keys(existing).length) {
      updates.specs_json = merged;
      specsUpdated = true;
    }
  }

  if (Object.keys(updates).length > 0) {
    await sb.from('aiq_products').update(updates).eq('id', productId);
  }

  // 2. Write images to pim_product_images (skip duplicates)
  if (extracted.images && extracted.images.length > 0) {
    for (const img of extracted.images.slice(0, 20)) {
      if (!img.url || img.url.length > 2000) continue;
      const { error } = await sb.from('pim_product_images').upsert({
        product_id: productId,
        file_url: img.url,
        cdn_url: img.url,
        image_type: img.type || 'product',
        alt_text: img.alt || `${product.brand_name} ${product.model}`,
        is_primary: img.type === 'hero',
      }, { onConflict: 'product_id,file_url', ignoreDuplicates: true });
      if (!error) imagesAdded++;
    }
  }

  // 3. Write documents to pim_product_documents (skip duplicates)
  if (extracted.documents && extracted.documents.length > 0) {
    for (const doc of extracted.documents.slice(0, 15)) {
      if (!doc.url || doc.url.length > 2000) continue;
      const { data: existing } = await sb.from('pim_product_documents').select('id').eq('product_id', productId).eq('file_url', doc.url).maybeSingle();
      if (!existing) {
        await sb.from('pim_product_documents').insert({
          product_id: productId,
          file_url: doc.url,
          file_name: doc.file_name || 'document.pdf',
          doc_type: doc.doc_type || 'other',
          title: doc.title || doc.file_name || 'Document',
          mime_type: 'application/pdf',
        });
        docsAdded++;
      }
    }
  }

  // 4. Write videos to pim_product_videos (skip duplicates)
  if (extracted.videos && extracted.videos.length > 0) {
    for (const vid of extracted.videos.slice(0, 10)) {
      const { data: existing } = await sb.from('pim_product_videos').select('id').eq('product_id', productId).eq('video_url', vid.url).maybeSingle();
      if (!existing) {
        await sb.from('pim_product_videos').insert({
          product_id: productId,
          video_url: vid.url,
          embed_url: vid.embed_url || null,
          title: vid.title || `${product.brand_name} ${product.model} Video`,
          thumbnail_url: vid.thumbnail || null,
          video_type: vid.type || 'product_overview',
          platform: vid.platform || 'other',
        });
        videosAdded++;
      }
    }
  }

  // 5. Write features to pim_product_features (skip duplicates)
  if (extracted.features && extracted.features.length > 0) {
    for (const feat of extracted.features.slice(0, 30)) {
      const { data: existing } = await sb.from('pim_product_features').select('id').eq('product_id', productId).eq('feature_text', feat).maybeSingle();
      if (!existing) {
        await sb.from('pim_product_features').insert({
          product_id: productId,
          feature_text: feat,
          feature_category: 'general',
        });
        featuresAdded++;
      }
    }
  }

  return {
    product_id: productId,
    success: true,
    url: pageUrl,
    images_added: imagesAdded,
    docs_added: docsAdded,
    videos_added: videosAdded,
    features_added: featuresAdded,
    specs_updated: specsUpdated,
    spec_count: extracted._specCount || 0,
  };
}
