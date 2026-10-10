// enrich-from-spec v2 — JWT-protected, server-side API key only
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { product_id, mode } = await req.json();
    const sbUrl = Deno.env.get("SUPABASE_URL")!;
    const sbKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    const sb = createClient(sbUrl, sbKey);

    if (mode === "find") {
      const { data: products } = await sb.from("aiq_products").select("id, model, brand_name, category").eq("status", "active").or("specs_json.is.null,specs_json.eq.{}").limit(200);
      const ids = (products || []).map((p: any) => p.id);
      if (!ids.length) return json({ products: [], count: 0 });
      const { data: docs } = await sb.from("pim_product_documents").select("product_id, file_url, doc_type").eq("doc_type", "spec_sheet").in("product_id", ids).not("file_url", "is", null);
      const docMap = new Map();
      (docs || []).forEach((d: any) => { if (d.file_url?.includes(".pdf")) docMap.set(d.product_id, d.file_url); });
      const enrichable = (products || []).filter((p: any) => docMap.has(p.id)).map((p: any) => ({ id: p.id, model: p.model, brand_name: p.brand_name, category: p.category, spec_sheet_url: docMap.get(p.id) }));
      return json({ products: enrichable, count: enrichable.length });
    }

    if (!product_id) return json({ error: "product_id required" }, 400);
    if (!anthropicKey) return json({ error: "ANTHROPIC_API_KEY not configured in Edge Function Secrets" }, 500);

    const { data: product } = await sb.from("aiq_products").select("id, model, brand_name, category, short_description").eq("id", product_id).single();
    if (!product) return json({ error: "Product not found" }, 404);

    const { data: docs } = await sb.from("pim_product_documents").select("file_url, doc_type, title").eq("product_id", product_id).in("doc_type", ["spec_sheet", "specification_sheet"]).not("file_url", "is", null).limit(3);
    if (!docs?.length) {
      const { data: anyDocs } = await sb.from("pim_product_documents").select("file_url, doc_type, title").eq("product_id", product_id).not("file_url", "is", null).limit(3);
      if (!anyDocs?.length) return json({ error: "No documents found" }, 404);
      docs!.push(...anyDocs);
    }

    let pdfBase64: string | null = null;
    let specSheetUrl = "";
    let fetchedFromUrl = false;
    for (const doc of docs!) {
      if (!doc.file_url) continue;
      specSheetUrl = doc.file_url;
      try {
        const pdfResp = await fetch(doc.file_url, { headers: { "User-Agent": "ApplianceIQ-PIM/1.0" }, redirect: "follow" });
        if (pdfResp.ok && (pdfResp.headers.get("content-type") || "").includes("pdf")) {
          const bytes = new Uint8Array(await pdfResp.arrayBuffer());
          let binary = ""; for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
          pdfBase64 = btoa(binary); fetchedFromUrl = true; break;
        }
      } catch { continue; }
    }

    const systemPrompt = `You are a product data extraction expert for the appliance industry. Extract structured specifications from product documents.
Return ONLY a JSON object with two keys:
1. "fields" - width_inches, height_inches, depth_inches, weight_lbs, voltage, amperage, wattage, capacity_cu_ft, color, finish, energy_star, installation_type, series, upc, made_in (null if not found)
2. "specs" - ALL other specifications as clean key-value pairs
Return ONLY valid JSON.`;

    const userContent: any[] = [];
    if (pdfBase64) {
      userContent.push({ type: "document", source: { type: "base64", media_type: "application/pdf", data: pdfBase64 } });
      userContent.push({ type: "text", text: `Extract all specs from this spec sheet for ${product.brand_name} ${product.model} (${product.category || "appliance"}).` });
    } else {
      userContent.push({ type: "text", text: `Find and extract specs for ${product.brand_name} ${product.model} (${product.category || "appliance"}). Spec sheet URL: ${specSheetUrl}\n${product.short_description || ""}` });
    }

    const claudeResp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: "claude-haiku-4-5-20251001", max_tokens: 4096, system: systemPrompt, messages: [{ role: "user", content: userContent }], ...(pdfBase64 ? {} : { tools: [{ type: "web_search_20250305", name: "web_search" }] }) }),
    });
    if (!claudeResp.ok) return json({ error: "Claude API error", details: await claudeResp.text() }, 502);

    const claudeData = await claudeResp.json();
    const textBlocks = claudeData.content?.filter((b: any) => b.type === "text")?.map((b: any) => b.text)?.join("\n") || "";

    let extracted;
    try { extracted = JSON.parse(textBlocks.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim()); }
    catch { return json({ error: "Failed to parse response", raw: textBlocks.slice(0, 500) }, 422); }

    const update: any = {};
    const fields = extracted.fields || {};
    for (const [k, v] of Object.entries(fields)) { if (v != null) update[k] = v; }
    if (extracted.specs && Object.keys(extracted.specs).length > 0) {
      const { data: existing } = await sb.from("aiq_products").select("specs_json").eq("id", product_id).single();
      update.specs_json = { ...(existing?.specs_json || {}), ...extracted.specs };
    }
    update.updated_at = new Date().toISOString();

    const { error: updateError } = await sb.from("aiq_products").update(update).eq("id", product_id);
    if (updateError) return json({ error: "Update failed", details: updateError.message }, 500);

    return json({ success: true, product_id, model: product.model, brand: product.brand_name, fields_updated: Object.keys(update).length, specs_extracted: extracted.specs ? Object.keys(extracted.specs).length : 0, pdf_fetched: fetchedFromUrl, extracted });
  } catch (err: any) {
    return json({ error: err.message || "Unknown error" }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
