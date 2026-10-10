// fetch-intelligence v2 — JWT-protected, server-side API key only
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const { query, type } = await req.json();
    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
    if (!anthropicKey) return json({ error: "ANTHROPIC_API_KEY not configured in Edge Function Secrets" }, 500);

    const sbUrl = Deno.env.get("SUPABASE_URL")!;
    const sbKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(sbUrl, sbKey);

    let systemPrompt = "";
    let userPrompt = "";

    if (type === "news") {
      systemPrompt = `You are an appliance industry intelligence analyst. Search for the latest appliance industry news from the past 30 days. Return ONLY a JSON array of news items, each with: headline (string), company_name (string), category (one of: financial, product_launch, regulation, technology, partnership, recall, market_trend), source_name (string), published_date (YYYY-MM-DD), summary (1-2 sentences). Find 5-10 recent items.`;
      userPrompt = query || "Latest appliance industry news, product launches, market trends, regulations, tariffs affecting home appliances in North America";
    } else if (type === "recalls") {
      systemPrompt = `You are a product safety analyst. Search for the latest appliance recalls from CPSC, Health Canada, and manufacturer announcements in the past 90 days. Return ONLY a JSON array of recalls, each with: brand_name (string), title (string), product_name (string), hazard (string), remedy (string), recall_date (YYYY-MM-DD), country (US or CA), source (string), url (string), units_affected (string or null).`;
      userPrompt = query || "Latest home appliance recalls from CPSC and Health Canada";
    } else {
      systemPrompt = `You are an appliance industry intelligence analyst. Search for the requested information and return structured data. Return ONLY a JSON object with: type, items (array with headline/title, company_name/brand_name, category, source, date, summary, url).`;
      userPrompt = query;
    }

    const claudeResp = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
      body: JSON.stringify({ model: "claude-haiku-4-5-20251001", max_tokens: 4096, system: systemPrompt, tools: [{ type: "web_search_20250305", name: "web_search" }], messages: [{ role: "user", content: userPrompt }] }),
    });
    if (!claudeResp.ok) return json({ error: "Claude API error", details: await claudeResp.text() }, 502);

    const claudeData = await claudeResp.json();
    const textBlocks = claudeData.content?.filter((b: any) => b.type === "text")?.map((b: any) => b.text)?.join("\n") || "";

    let parsed;
    try { parsed = JSON.parse(textBlocks.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim()); }
    catch { return json({ error: "Could not parse response", raw: textBlocks.slice(0, 1000) }, 422); }

    const items = Array.isArray(parsed) ? parsed : (parsed.items || []);
    let saved = 0;

    if (type === "news") {
      for (const item of items) {
        if (!item.headline) continue;
        const { error } = await sb.from("intel_news").upsert({ headline: item.headline, company_name: item.company_name || "Industry", category: item.category || "market_trend", source_name: item.source_name || "AI Research", published_date: item.published_date || null, summary: item.summary || null, scraped_at: new Date().toISOString() }, { onConflict: "headline", ignoreDuplicates: true });
        if (!error) saved++;
      }
    } else if (type === "recalls") {
      for (const item of items) {
        if (!item.title && !item.brand_name) continue;
        const { error } = await sb.from("aiq_recalls").upsert({ brand_name: item.brand_name || "Unknown", title: item.title || "", product_name: item.product_name || null, hazard: item.hazard || null, remedy: item.remedy || null, recall_date: item.recall_date || null, country: item.country || "US", source: item.source || "AI Research", url: item.url || null, units_affected: item.units_affected || null, is_appliance_related: true }, { onConflict: "title", ignoreDuplicates: true });
        if (!error) saved++;
      }
    }

    return json({ success: true, items_found: items.length, items_saved: saved, results: items });
  } catch (err: any) {
    return json({ error: err.message }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}
