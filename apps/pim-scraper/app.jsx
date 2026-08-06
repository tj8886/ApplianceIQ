const { useState, useCallback, useRef } = React;

const SUPABASE_URL = "https://fumwwhyozeouoqscolke.supabase.co";
const SUPABASE_KEY = "sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV";

// ── Model Configuration ──
const MODEL_CONFIG = {
  luna:   { name: "Luna",   provider: "openai",   model: "gpt-4.1-nano",              cost: "~0.1¢", color: "#74b9ff" },
  terra:  { name: "Terra",  provider: "openai",   model: "gpt-4.1-mini",              cost: "~0.4¢", color: "#fdcb6e" },
  haiku:  { name: "Haiku",  provider: "anthropic", model: "claude-haiku-4-5-20251001", cost: "~0.3¢", color: "#00b894" },
  sonnet: { name: "Sonnet", provider: "anthropic", model: "claude-sonnet-4-6",         cost: "~1.5¢", color: "#6c5ce7" },
};

const CATEGORIES = [
  "refrigeration","cooking","dishwashers","laundry","ventilation",
  "wine_refrigeration","beverage_centers","ice_makers","outdoor","small_appliances"
];

const SCRAPE_PROMPT = `You are an appliance product data extraction assistant. Search the web for the given appliance product. Go to the MANUFACTURER'S OWN WEBSITE (e.g. lg.com, whirlpool.com, samsung.com) AND major Canadian retailers (bestbuy.ca, homedepot.ca, lowes.ca) to get complete data.

IMPORTANT INSTRUCTIONS:
- Visit the manufacturer's product page directly. Look at the page source and gallery.
- Extract EVERY product image URL you can find — hero shots, angle views, interior shots, detail close-ups, lifestyle images, dimension diagrams. Most appliance pages have 5-10+ images. Get them ALL. Use full absolute URLs (https://...).
- Extract ALL available color/finish options with their model numbers.
- PRICING: Get THREE prices: 1) MSRP (manufacturer suggested retail), 2) current sale/promo price if on sale, 3) lowest price you can find on any major retailer. Search "[brand] [model] price canada" to find retailer pricing.
- PRODUCT CONDITION: Check if the product is flagged as any of these: discontinued, clearance, end-of-life, last chance, open box, refurbished, B-stock, scratch & dent, floor model, closeout, limited stock, while supplies last, no longer available. Look for banners, badges, or labels on the product page.

Return ONLY valid JSON, no markdown, no backticks, no preamble:

{
  "found": true,
  "source_url": "manufacturer product page URL",
  "manufacturer_name": "",
  "brand_name": "",
  "model": "",
  "category": "one of: refrigeration, cooking, dishwashers, laundry, ventilation, wine_refrigeration, beverage_centers, ice_makers, outdoor, small_appliances",
  "product_line": "",
  "series": "",
  "short_description": "one-line product title from the page",
  "long_description": "fuller marketing description",
  "features": ["feature 1", "feature 2", "...all features listed"],
  "pricing": {
    "msrp": null,
    "sale_price": null,
    "lowest_price": null,
    "lowest_price_source": "",
    "price_currency": "CAD",
    "on_sale": false,
    "sale_ends": null,
    "price_checked_sources": ["lg.com", "bestbuy.ca", "homedepot.ca"]
  },
  "condition": {
    "status": "active",
    "flags": [],
    "is_discontinued": false,
    "is_clearance": false,
    "is_end_of_life": false,
    "is_open_box": false,
    "is_refurbished": false,
    "replacement_model": null,
    "notes": ""
  },
  "upc": null,
  "ean": null,
  "finish": "finish of this specific model",
  "color": "color name",
  "color_family": "e.g. stainless, black, white",
  "available_colors": [
    {"color": "Stainless Steel", "finish": "PrintProof Stainless Steel", "model_number": "LRMVS3006S", "msrp": null, "sale_price": null},
    {"color": "Black Stainless", "finish": "PrintProof Black Stainless", "model_number": "LRMVS3006D", "msrp": null, "sale_price": null}
  ],
  "energy_star": null,
  "ada_compliant": null,
  "width_inches": null,
  "height_inches": null,
  "depth_inches": null,
  "weight_lbs": null,
  "country_availability": ["CA", "US"],
  "made_in": "",
  "specs": {
    "capacity_cu_ft": null,
    "voltage": null,
    "amperage": null,
    "wattage": null,
    "frequency_hz": null,
    "btu": null,
    "cfm": null,
    "sones": null,
    "decibels": null,
    "annual_energy_kwh": null,
    "depth_with_handles": null,
    "depth_without_handles": null,
    "cutout_width": null,
    "cutout_height": null,
    "cutout_depth": null,
    "installation_type": "",
    "door_swing": "",
    "reversible_door": null,
    "cord_length_inches": null,
    "water_connection": "",
    "gas_type": "",
    "duct_size_inches": null
  },
  "images": [
    {"url": "https://full-url-to-image.jpg", "type": "hero", "alt": "description"},
    {"url": "https://...", "type": "front", "alt": ""},
    {"url": "https://...", "type": "angle", "alt": ""},
    {"url": "https://...", "type": "interior", "alt": ""},
    {"url": "https://...", "type": "detail", "alt": ""},
    {"url": "https://...", "type": "lifestyle", "alt": ""},
    {"url": "https://...", "type": "dimensions", "alt": ""}
  ],
  "documents": [
    {"type": "spec_sheet", "url": "", "title": ""},
    {"type": "installation_guide", "url": "", "title": ""},
    {"type": "owners_manual", "url": "", "title": ""},
    {"type": "energy_guide", "url": "", "title": ""},
    {"type": "warranty", "url": "", "title": ""}
  ]
}

Return ALL images, ALL color variants. Check "condition.status" carefully: "active", "discontinued", "clearance", "end_of_life", "open_box", "refurbished". Set the flags array too (e.g. ["clearance", "limited_stock"]).`;

const DISCOVER_PROMPT = `You are an appliance product discovery assistant. Find product model numbers from a manufacturer's website.

Search the manufacturer's CANADIAN website thoroughly. Check category pages, "view all" pages, product listing pages, and filters.

IMPORTANT: Keep each product entry SHORT. Only return model number, product name, and URL. Do NOT include specs or descriptions.

Return ONLY valid JSON, no markdown, no backticks:

{
  "found": true,
  "brand": "LG",
  "category": "french door refrigerators",
  "source_url": "the listing page URL",
  "products": [
    {"model": "LRMVS3006S", "name": "30 cu ft Smart French Door", "url": "https://..."},
    {"model": "LRFXS2503S", "name": "25 cu ft Smart French Door", "url": "https://..."}
  ]
}

List EVERY model you find. Keep entries minimal — model, name, url only.`;

const APPLIANCE_CATEGORIES = [
  "refrigerators", "dishwashers", "ranges", "wall-ovens", "cooktops",
  "microwaves", "ventilation", "washers", "dryers", "wine-coolers",
  "beverage-centers", "ice-makers", "freezers", "outdoor-grills", "rangetops",
  "warming-drawers", "trash-compactors", "disposers",
];

function supaFetch(path, opts = {}) {
  return fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...opts,
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
      Prefer: opts.prefer || "return=representation",
      ...opts.headers,
    },
  });
}

function extractJSON(text) {
  try { return JSON.parse(text.trim()); } catch {}
  const stripped = text.replace(/```json\s*/g, "").replace(/```\s*/g, "").trim();
  try { return JSON.parse(stripped); } catch {}
  const start = stripped.indexOf("{");
  const end = stripped.lastIndexOf("}");
  if (start !== -1 && end > start) {
    try { return JSON.parse(stripped.slice(start, end + 1)); } catch {}
  }
  return null;
}

// ── AI Call Router ──
async function callAI(systemPrompt, userMsg, modelKey, retries = 2) {
  const config = MODEL_CONFIG[modelKey] || MODEL_CONFIG.haiku;
  if (config.provider === "openai") {
    return callOpenAI(systemPrompt, userMsg, config.model, retries);
  }
  return callClaude(systemPrompt, userMsg, config.model, retries);
}

// ── Anthropic ──
async function callClaude(systemPrompt, userMsg, model = "claude-sonnet-4-6", retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const res = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          max_tokens: 8000,
          system: systemPrompt,
          messages: [{ role: "user", content: userMsg }],
          tools: [{ type: "web_search_20250305", name: "web_search" }],
        }),
      });
      if (!res.ok) {
        const errText = await res.text();
        if (attempt < retries) { await new Promise(r => setTimeout(r, 2000)); continue; }
        return { found: false, error: `API error ${res.status}: ${errText.slice(0, 200)}` };
      }
      const data = await res.json();
      const allText = (data.content || [])
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("\n");
      const parsed = extractJSON(allText);
      if (parsed && (parsed.found === true || parsed.model || parsed.brand_name)) {
        parsed.found = true;
        return parsed;
      }
      if (attempt < retries) { await new Promise(r => setTimeout(r, 1500)); continue; }
      return { found: false, error: "Could not parse product data from response", raw: allText.slice(0, 500) };
    } catch (e) {
      if (attempt < retries) { await new Promise(r => setTimeout(r, 2000)); continue; }
      return { found: false, error: e.message };
    }
  }
}

// ── OpenAI ──
async function callOpenAI(systemPrompt, userMsg, model = "gpt-4.1-nano", retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const body = {
        model,
        max_tokens: 8000,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userMsg },
        ],
      };
      // Luna/Terra support web search via tools
      if (model.includes("4.1")) {
        body.tools = [{ type: "web_search_preview" }];
      }
      const res = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!res.ok) {
        const errText = await res.text();
        // Fallback to chat completions if responses endpoint fails
        if (res.status === 404) {
          const fallbackRes = await fetch("https://api.openai.com/v1/chat/completions", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              model,
              max_tokens: 8000,
              messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: userMsg },
              ],
            }),
          });
          if (!fallbackRes.ok) {
            if (attempt < retries) { await new Promise(r => setTimeout(r, 2000)); continue; }
            return { found: false, error: `OpenAI error ${fallbackRes.status}` };
          }
          const fbData = await fallbackRes.json();
          const fbText = fbData.choices?.[0]?.message?.content || "";
          const fbParsed = extractJSON(fbText);
          if (fbParsed && (fbParsed.found === true || fbParsed.model || fbParsed.brand_name)) {
            fbParsed.found = true;
            return fbParsed;
          }
        }
        if (attempt < retries) { await new Promise(r => setTimeout(r, 2000)); continue; }
        return { found: false, error: `OpenAI error ${res.status}: ${errText.slice(0, 200)}` };
      }
      const data = await res.json();
      // Handle responses API format
      const allText = data.output
        ? data.output.filter(b => b.type === "message").map(b => b.content?.map(c => c.text).join("")).join("\n")
        : data.choices?.[0]?.message?.content || "";
      const parsed = extractJSON(allText);
      if (parsed && (parsed.found === true || parsed.model || parsed.brand_name)) {
        parsed.found = true;
        return parsed;
      }
      if (attempt < retries) { await new Promise(r => setTimeout(r, 1500)); continue; }
      return { found: false, error: "Could not parse product data from OpenAI response", raw: allText.slice(0, 500) };
    } catch (e) {
      if (attempt < retries) { await new Promise(r => setTimeout(r, 2000)); continue; }
      return { found: false, error: e.message };
    }
  }
}

// ── Free Data Pass: Extract structured data from HTML without AI ──
async function freeExtract(url) {
  if (!url || !url.startsWith("http")) return null;
  try {
    const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0" } });
    if (!res.ok) return null;
    const html = await res.text();
    const result = { found: false, source_url: url, extraction_method: "free_parse" };

    // Extract JSON-LD Product schema
    const jsonLdMatch = html.match(/<script[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi);
    if (jsonLdMatch) {
      for (const match of jsonLdMatch) {
        try {
          const content = match.replace(/<script[^>]*>/i, "").replace(/<\/script>/i, "").trim();
          const ld = JSON.parse(content);
          const product = ld["@type"] === "Product" ? ld : (Array.isArray(ld["@graph"]) ? ld["@graph"].find(g => g["@type"] === "Product") : null);
          if (product) {
            result.found = true;
            result.brand_name = product.brand?.name || product.brand || null;
            result.model = product.model || product.sku || null;
            result.short_description = product.name || null;
            result.long_description = product.description || null;
            if (product.image) {
              const imgs = Array.isArray(product.image) ? product.image : [product.image];
              result.images = imgs.map((u, i) => ({ url: typeof u === "string" ? u : u.url, type: i === 0 ? "hero" : "product", alt: "" }));
            }
            if (product.offers) {
              const offer = Array.isArray(product.offers) ? product.offers[0] : product.offers;
              result.pricing = { msrp: offer.price || null, price_currency: offer.priceCurrency || "CAD" };
              result.msrp = offer.price || null;
            }
            if (product.width) result.width_inches = parseFloat(product.width.value || product.width) || null;
            if (product.height) result.height_inches = parseFloat(product.height.value || product.height) || null;
            if (product.depth) result.depth_inches = parseFloat(product.depth.value || product.depth) || null;
            if (product.weight) result.weight_lbs = parseFloat(product.weight.value || product.weight) || null;
            if (product.color) result.color = product.color;
            if (product.gtin13) result.ean = product.gtin13;
            if (product.gtin12) result.upc = product.gtin12;
          }
        } catch {}
      }
    }

    // Extract Open Graph meta tags
    const ogTitle = html.match(/<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']/i);
    const ogDesc = html.match(/<meta[^>]*property=["']og:description["'][^>]*content=["']([^"']+)["']/i);
    const ogImage = html.match(/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i);
    if (ogTitle && !result.short_description) result.short_description = ogTitle[1];
    if (ogDesc && !result.long_description) result.long_description = ogDesc[1];
    if (ogImage) {
      if (!result.images) result.images = [];
      const ogUrl = ogImage[1];
      if (!result.images.some(i => i.url === ogUrl)) {
        result.images.unshift({ url: ogUrl, type: "hero", alt: result.short_description || "" });
      }
    }

    // Extract spec tables (label/value pairs in <table> or <dl>)
    const specs = {};
    // <tr><td>Label</td><td>Value</td></tr> pattern
    const trMatches = html.matchAll(/<tr[^>]*>\s*<t[dh][^>]*>([^<]+)<\/t[dh]>\s*<t[dh][^>]*>([^<]+)<\/t[dh]>\s*<\/tr>/gi);
    for (const m of trMatches) {
      const key = m[1].trim().toLowerCase().replace(/[^a-z0-9]+/g, "_");
      const val = m[2].trim();
      if (key && val && val.length < 200) specs[key] = val;
    }
    // <dt>/<dd> pattern
    const dlMatches = html.matchAll(/<dt[^>]*>([^<]+)<\/dt>\s*<dd[^>]*>([^<]+)<\/dd>/gi);
    for (const m of dlMatches) {
      const key = m[1].trim().toLowerCase().replace(/[^a-z0-9]+/g, "_");
      const val = m[2].trim();
      if (key && val && val.length < 200) specs[key] = val;
    }
    if (Object.keys(specs).length > 0) {
      result.found = true;
      result.specs = specs;
      // Try to pull dimensions from specs
      for (const [k, v] of Object.entries(specs)) {
        if (!result.width_inches && (k.includes("width") || k.includes("w_in"))) result.width_inches = parseFloat(v) || null;
        if (!result.height_inches && (k.includes("height") || k.includes("h_in"))) result.height_inches = parseFloat(v) || null;
        if (!result.depth_inches && (k.includes("depth") || k.includes("d_in"))) result.depth_inches = parseFloat(v) || null;
        if (!result.weight_lbs && k.includes("weight")) result.weight_lbs = parseFloat(v) || null;
      }
    }

    return result.found ? result : null;
  } catch {
    return null;
  }
}

async function scrapeProduct(query, modelKey) {
  // Pass 1: If it's a URL, try free extraction first (no AI cost)
  if (query.startsWith("http")) {
    const freeResult = await freeExtract(query);
    if (freeResult && freeResult.found && freeResult.short_description) {
      freeResult.extraction_method = "free_parse";
      return freeResult;
    }
  }

  // Pass 2: AI-powered extraction
  let result = await callAI(SCRAPE_PROMPT, `Find all product specifications for: ${query}`, modelKey);
  if (result.found) { result.extraction_method = "ai"; return result; }
  
  const fallbackPrompt = `Search the web for this appliance product and return a JSON object with the product data. Search for the manufacturer's website specifically. Return ONLY valid JSON, no other text.

The JSON must have: found (true/false), source_url, manufacturer_name, brand_name, model, category, short_description, msrp, finish, color, available_colors (array of {color, finish, model_number, msrp}), width_inches, height_inches, depth_inches, weight_lbs, energy_star, features (array of strings), images (array of {url, type, alt}), specs (object with capacity_cu_ft, voltage, amperage, installation_type etc).

Return ALL image URLs from the product gallery. Return ALL color/finish options.`;
  
  result = await callAI(fallbackPrompt, `${query} — search the manufacturer website for full specs, all images, all colors, and MSRP price`, modelKey);
  if (result.found) { result.extraction_method = "ai_fallback"; return result; }
  
  return { found: false, query, error: result.error || "Product not found after multiple attempts" };
}

// ── Styles ──
const palette = {
  bg: "#0f1117", card: "#181a22", cardHover: "#1e2130", border: "#2a2d3a",
  accent: "#6c5ce7", accentSoft: "#6c5ce720", accentText: "#a29bfe",
  text: "#e4e6ed", textDim: "#8b8fa3", textMuted: "#5a5e72",
  green: "#00b894", greenSoft: "#00b89420", red: "#e17055", redSoft: "#e1705520",
  yellow: "#fdcb6e", yellowSoft: "#fdcb6e20", blue: "#74b9ff",
};

const s = {
  app: { background: palette.bg, color: palette.text, minHeight: "100vh", fontFamily: "'Inter', -apple-system, sans-serif", padding: "0" },
  header: { padding: "24px 32px", borderBottom: `1px solid ${palette.border}`, display: "flex", alignItems: "center", justifyContent: "space-between" },
  logo: { fontSize: 20, fontWeight: 700, letterSpacing: "-0.5px", color: palette.text },
  logoAccent: { color: palette.accent },
  main: { maxWidth: 1100, margin: "0 auto", padding: "32px" },
  inputRow: { display: "flex", gap: 12, marginBottom: 24 },
  input: { flex: 1, padding: "12px 16px", background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, color: palette.text, fontSize: 14, outline: "none" },
  textarea: { width: "100%", padding: "12px 16px", background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, color: palette.text, fontSize: 13, outline: "none", fontFamily: "monospace", resize: "vertical", minHeight: 80 },
  btn: { padding: "12px 24px", background: palette.accent, color: "#fff", border: "none", borderRadius: 8, fontSize: 14, fontWeight: 600, cursor: "pointer" },
  btnSm: { padding: "8px 16px", fontSize: 13 },
  btnOutline: { background: "transparent", border: `1px solid ${palette.border}`, color: palette.textDim },
  btnGreen: { background: palette.green },
  btnRed: { background: palette.red },
  card: { background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 12, padding: 24, marginBottom: 16 },
  label: { fontSize: 11, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.5px", color: palette.textMuted, marginBottom: 4 },
  val: { fontSize: 14, color: palette.text },
  grid: { display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))", gap: 16 },
  badge: { display: "inline-block", padding: "2px 8px", borderRadius: 4, fontSize: 11, fontWeight: 600 },
  tab: { padding: "8px 16px", background: "transparent", border: "none", color: palette.textDim, fontSize: 13, fontWeight: 500, cursor: "pointer", borderBottom: "2px solid transparent" },
  tabActive: { color: palette.accent, borderBottom: `2px solid ${palette.accent}` },
  stat: { textAlign: "center" },
  statNum: { fontSize: 28, fontWeight: 700, color: palette.accent },
  statLabel: { fontSize: 11, color: palette.textMuted, textTransform: "uppercase", letterSpacing: "0.5px" },
  spinner: { display: "inline-block", width: 16, height: 16, border: `2px solid ${palette.border}`, borderTopColor: palette.accent, borderRadius: "50%", animation: "spin 0.8s linear infinite" },
};

function Badge({ children, color = "accent" }) {
  const colors = { accent: { bg: palette.accentSoft, fg: palette.accentText }, green: { bg: palette.greenSoft, fg: palette.green }, red: { bg: palette.redSoft, fg: palette.red }, yellow: { bg: palette.yellowSoft, fg: palette.yellow } };
  const c = colors[color] || colors.accent;
  return <span style={{ ...s.badge, background: c.bg, color: c.fg }}>{children}</span>;
}

function Field({ label, value, editable, onChange }) {
  if (value === null || value === undefined || value === "") return null;
  return (
    <div>
      <div style={s.label}>{label}</div>
      {editable ? (
        <input style={{ ...s.input, padding: "6px 10px", fontSize: 13 }} value={value ?? ""} onChange={(e) => onChange(e.target.value)} />
      ) : (
        <div style={s.val}>{typeof value === "boolean" ? (value ? "Yes" : "No") : String(value)}</div>
      )}
    </div>
  );
}

// ── Model Selector Component ──
function ModelSelector({ selected, onChange }) {
  const [open, setOpen] = useState(false);
  const config = MODEL_CONFIG[selected] || MODEL_CONFIG.haiku;
  return (
    <div style={{ position: "relative" }}>
      <button onClick={() => setOpen(!open)}
        style={{ ...s.btn, ...s.btnSm, background: config.color + "20", border: `1px solid ${config.color}40`, color: config.color, display: "flex", alignItems: "center", gap: 6, minWidth: 120 }}>
        <span style={{ width: 8, height: 8, borderRadius: "50%", background: config.color, display: "inline-block" }} />
        {config.name} <span style={{ fontSize: 10, opacity: 0.7 }}>{config.cost}</span>
        <span style={{ fontSize: 10, marginLeft: 4 }}>▾</span>
      </button>
      {open && (
        <div style={{ position: "absolute", top: "100%", right: 0, marginTop: 4, background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, padding: 4, zIndex: 100, minWidth: 180 }}>
          {Object.entries(MODEL_CONFIG).map(([key, cfg]) => (
            <button key={key} onClick={() => { onChange(key); setOpen(false); }}
              style={{ display: "flex", alignItems: "center", gap: 8, width: "100%", padding: "8px 12px", background: selected === key ? cfg.color + "15" : "transparent", border: "none", borderRadius: 6, color: palette.text, cursor: "pointer", fontSize: 13, textAlign: "left" }}>
              <span style={{ width: 8, height: 8, borderRadius: "50%", background: cfg.color }} />
              <span style={{ flex: 1, fontWeight: selected === key ? 600 : 400 }}>{cfg.name}</span>
              <span style={{ fontSize: 11, color: palette.textMuted }}>{cfg.cost}</span>
              <span style={{ fontSize: 10, color: palette.textMuted }}>{cfg.provider}</span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function ResultCard({ result, onSave, onDiscard, saving }) {
  const [editing, setEditing] = useState(false);
  const [data, setData] = useState(result);
  const upd = (k, v) => setData((d) => ({ ...d, [k]: v }));

  if (!data.found) {
    return (
      <div style={{ ...s.card, borderColor: palette.red }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ color: palette.red, fontWeight: 600 }}>Not found: {data.query}</span>
          <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={onDiscard}>Dismiss</button>
        </div>
        {data.error && <div style={{ color: palette.textDim, fontSize: 13, marginTop: 8 }}>{data.error}</div>}
      </div>
    );
  }

  return (
    <div style={s.card}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
        <div>
          <div style={{ fontSize: 16, fontWeight: 600 }}>{data.brand_name} {data.model}</div>
          <div style={{ fontSize: 13, color: palette.textDim }}>{data.short_description}</div>
          {data.extraction_method && (
            <Badge color={data.extraction_method === "free_parse" ? "green" : "accent"}>
              {data.extraction_method === "free_parse" ? "⚡ Free parse" : data.extraction_method === "ai" ? "🤖 AI" : "🤖 AI fallback"}
            </Badge>
          )}
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          <Badge color={(!data.condition?.is_discontinued && !data.condition?.is_clearance && !data.condition?.is_end_of_life) ? "green" : 
            data.condition?.is_discontinued ? "red" : "yellow"}>
            {data.condition?.status || data.status || "active"}
          </Badge>
          {data.condition?.is_clearance && <Badge color="yellow">🏷️ Clearance</Badge>}
          {data.condition?.is_end_of_life && <Badge color="yellow">⚠️ End of Life</Badge>}
          {data.condition?.is_open_box && <Badge color="yellow">📦 Open Box</Badge>}
          {data.condition?.is_refurbished && <Badge color="yellow">🔧 Refurbished</Badge>}
          {data.condition?.flags?.filter(f => !["clearance","end_of_life","open_box","refurbished","discontinued"].includes(f)).map((f,i) => (
            <Badge key={i} color="yellow">{f.replace(/_/g," ")}</Badge>
          ))}
          {data.condition?.replacement_model && (
            <span style={{ fontSize: 11, color: palette.textDim }}>→ replaced by <strong>{data.condition.replacement_model}</strong></span>
          )}
          <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={() => setEditing(!editing)}>{editing ? "Done" : "Edit"}</button>
          <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline, ...s.btnRed, border: "none", color: "#fff" }} onClick={onDiscard}>Skip</button>
          <button style={{ ...s.btn, ...s.btnSm, ...s.btnGreen }} onClick={() => onSave(data)} disabled={saving}>
            {saving ? "Saving…" : "Save to PIM"}
          </button>
        </div>
      </div>

      {data.source_url && <div style={{ fontSize: 12, color: palette.blue, marginBottom: 16 }}>Source: <a href={data.source_url} target="_blank" rel="noreferrer" style={{ color: palette.blue }}>{data.source_url}</a></div>}

      <div style={s.grid}>
        <Field label="Brand" value={data.brand_name} editable={editing} onChange={(v) => upd("brand_name", v)} />
        <Field label="Model" value={data.model} editable={editing} onChange={(v) => upd("model", v)} />
        <Field label="Category" value={data.category} editable={editing} onChange={(v) => upd("category", v)} />
        <Field label="Series" value={data.series} editable={editing} onChange={(v) => upd("series", v)} />
        <Field label="Product Line" value={data.product_line} editable={editing} onChange={(v) => upd("product_line", v)} />
        <Field label="MSRP" value={data.msrp} editable={editing} onChange={(v) => upd("msrp", v)} />
        <Field label="UPC" value={data.upc} editable={editing} onChange={(v) => upd("upc", v)} />
        <Field label="Finish" value={data.finish} editable={editing} onChange={(v) => upd("finish", v)} />
        <Field label="Color" value={data.color} editable={editing} onChange={(v) => upd("color", v)} />
        <Field label="Width (in)" value={data.width_inches} editable={editing} onChange={(v) => upd("width_inches", v)} />
        <Field label="Height (in)" value={data.height_inches} editable={editing} onChange={(v) => upd("height_inches", v)} />
        <Field label="Depth (in)" value={data.depth_inches} editable={editing} onChange={(v) => upd("depth_inches", v)} />
        <Field label="Weight (lbs)" value={data.weight_lbs} editable={editing} onChange={(v) => upd("weight_lbs", v)} />
        <Field label="Energy Star" value={data.energy_star} />
        <Field label="ADA" value={data.ada_compliant} />
        <Field label="Made In" value={data.made_in} editable={editing} onChange={(v) => upd("made_in", v)} />
      </div>

      {data.specs && Object.keys(data.specs).some((k) => data.specs[k] !== null) && (
        <div style={{ marginTop: 16 }}>
          <div style={{ ...s.label, marginBottom: 12 }}>Specifications</div>
          <div style={s.grid}>
            {Object.entries(data.specs).map(([k, v]) => v !== null && v !== "" && (
              <Field key={k} label={k.replace(/_/g, " ")} value={v} />
            ))}
          </div>
        </div>
      )}

      <div style={{ display: "flex", gap: 12, marginTop: 16, flexWrap: "wrap", alignItems: "stretch" }}>
        {(data.pricing?.msrp || data.msrp) && (
          <div style={{ padding: "10px 20px", background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, minWidth: 120 }}>
            <div style={{ fontSize: 10, color: palette.textMuted, textTransform: "uppercase", letterSpacing: "0.5px" }}>MSRP</div>
            <div style={{ fontSize: 22, fontWeight: 700, color: palette.text }}>${parseFloat(data.pricing?.msrp || data.msrp).toLocaleString()}</div>
          </div>
        )}
        {data.pricing?.sale_price && (
          <div style={{ padding: "10px 20px", background: palette.redSoft, border: `1px solid ${palette.red}40`, borderRadius: 8, minWidth: 120 }}>
            <div style={{ fontSize: 10, color: palette.red, textTransform: "uppercase", letterSpacing: "0.5px" }}>Sale Price</div>
            <div style={{ fontSize: 22, fontWeight: 700, color: palette.red }}>${parseFloat(data.pricing.sale_price).toLocaleString()}</div>
            {data.pricing.sale_ends && <div style={{ fontSize: 10, color: palette.textMuted }}>ends {data.pricing.sale_ends}</div>}
          </div>
        )}
        {data.pricing?.lowest_price && (
          <div style={{ padding: "10px 20px", background: palette.greenSoft, border: `1px solid ${palette.green}40`, borderRadius: 8, minWidth: 120 }}>
            <div style={{ fontSize: 10, color: palette.green, textTransform: "uppercase", letterSpacing: "0.5px" }}>Lowest Found</div>
            <div style={{ fontSize: 22, fontWeight: 700, color: palette.green }}>${parseFloat(data.pricing.lowest_price).toLocaleString()}</div>
            {data.pricing.lowest_price_source && <div style={{ fontSize: 10, color: palette.textMuted }}>{data.pricing.lowest_price_source}</div>}
          </div>
        )}
        {data.pricing?.msrp && data.pricing?.lowest_price && parseFloat(data.pricing.lowest_price) < parseFloat(data.pricing.msrp) && (
          <div style={{ padding: "10px 20px", background: palette.accentSoft, borderRadius: 8, display: "flex", flexDirection: "column", justifyContent: "center", minWidth: 100 }}>
            <div style={{ fontSize: 10, color: palette.textMuted, textTransform: "uppercase", letterSpacing: "0.5px" }}>Savings</div>
            <div style={{ fontSize: 18, fontWeight: 700, color: palette.accent }}>
              {Math.round((1 - parseFloat(data.pricing.lowest_price) / parseFloat(data.pricing.msrp)) * 100)}% off
            </div>
            <div style={{ fontSize: 11, color: palette.textDim }}>${(parseFloat(data.pricing.msrp) - parseFloat(data.pricing.lowest_price)).toLocaleString()} saved</div>
          </div>
        )}
        {data.finish && (
          <div style={{ padding: "10px 20px", background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, display: "flex", flexDirection: "column", justifyContent: "center" }}>
            <div style={{ fontSize: 10, color: palette.textMuted, textTransform: "uppercase" }}>Finish</div>
            <div style={{ fontSize: 14, fontWeight: 600, color: palette.text }}>{data.finish}</div>
          </div>
        )}
        {data.pricing?.price_checked_sources?.length > 0 && (
          <div style={{ padding: "10px 20px", display: "flex", flexDirection: "column", justifyContent: "center" }}>
            <div style={{ fontSize: 10, color: palette.textMuted, textTransform: "uppercase" }}>Checked</div>
            <div style={{ fontSize: 11, color: palette.textDim }}>{data.pricing.price_checked_sources.join(", ")}</div>
          </div>
        )}
      </div>

      {data.condition?.notes && (
        <div style={{ marginTop: 8, padding: "6px 12px", background: palette.yellowSoft, borderRadius: 6, fontSize: 12, color: palette.yellow }}>
          ℹ️ {data.condition.notes}
        </div>
      )}

      {data.available_colors && data.available_colors.length > 0 && (
        <div style={{ marginTop: 16 }}>
          <div style={{ ...s.label, marginBottom: 8 }}>Available Colors & Finishes ({data.available_colors.length})</div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            {data.available_colors.map((c, i) => (
              <div key={i} style={{ padding: "8px 14px", background: palette.card, border: `1px solid ${palette.border}`, borderRadius: 8, fontSize: 13 }}>
                <div style={{ fontWeight: 600, color: palette.text }}>{c.color || c.finish}</div>
                {c.model_number && <div style={{ fontSize: 11, color: palette.textMuted, fontFamily: "monospace" }}>{c.model_number}</div>}
                <div style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 2 }}>
                  {c.msrp && <span style={{ fontSize: 12, color: c.sale_price ? palette.textMuted : palette.accent, fontWeight: 600, textDecoration: c.sale_price ? "line-through" : "none" }}>${parseFloat(c.msrp).toLocaleString()}</span>}
                  {c.sale_price && <span style={{ fontSize: 12, color: palette.red, fontWeight: 600 }}>${parseFloat(c.sale_price).toLocaleString()}</span>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {data.images && data.images.filter((img) => (typeof img === "string" ? img : img?.url)).length > 0 && (
        <div style={{ marginTop: 16 }}>
          <div style={{ ...s.label, marginBottom: 8 }}>Product Images ({data.images.filter((img) => (typeof img === "string" ? img : img?.url)).length})</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))", gap: 10 }}>
            {data.images.filter((img) => (typeof img === "string" ? img : img?.url)).map((img, i) => {
              const url = typeof img === "string" ? img : img.url;
              const type = typeof img === "string" ? (i === 0 ? "hero" : "product") : (img.type || "product");
              return (
                <div key={i} style={{ position: "relative" }}>
                  <a href={url} target="_blank" rel="noreferrer">
                    <img src={url} alt={`Product ${i + 1}`} style={{ width: "100%", height: 140, objectFit: "contain", borderRadius: 8, background: "#fff", border: `1px solid ${palette.border}`, display: "block" }}
                      onError={(e) => { e.target.parentElement.parentElement.style.display = "none"; }} />
                  </a>
                  <div style={{ position: "absolute", top: 6, left: 6, ...s.badge, background: "rgba(0,0,0,0.75)", color: "#fff", fontSize: 9 }}>{type}</div>
                  {i === 0 && <div style={{ position: "absolute", top: 6, right: 6, ...s.badge, background: palette.accent, color: "#fff", fontSize: 9 }}>PRIMARY</div>}
                </div>
              );
            })}
          </div>
        </div>
      )}

      {data.features && data.features.length > 0 && (
        <div style={{ marginTop: 16 }}>
          <div style={{ ...s.label, marginBottom: 8 }}>Features ({data.features.length})</div>
          <ul style={{ margin: 0, paddingLeft: 20, fontSize: 13, color: palette.textDim, columns: data.features.length > 6 ? 2 : 1, columnGap: 24 }}>
            {data.features.map((f, i) => <li key={i} style={{ marginBottom: 4 }}>{f}</li>)}
          </ul>
        </div>
      )}

      {data.documents && data.documents.filter((d) => d.url).length > 0 && (
        <div style={{ marginTop: 16 }}>
          <div style={{ ...s.label, marginBottom: 8 }}>Documents Found</div>
          <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            {data.documents.filter((d) => d.url).map((d, i) => (
              <a key={i} href={d.url} target="_blank" rel="noreferrer" style={{ ...s.badge, background: palette.accentSoft, color: palette.accentText, textDecoration: "none", padding: "4px 10px" }}>
                📄 {d.type?.replace(/_/g, " ") || "doc"} ↗
              </a>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function PIMScraper() {
  const [mode, setMode] = useState("single");
  const [query, setQuery] = useState("");
  const [bulkText, setBulkText] = useState("");
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState({ current: 0, total: 0, currentQuery: "" });
  const [saved, setSaved] = useState([]);
  const [errors, setErrors] = useState([]);
  const [existingProducts, setExistingProducts] = useState([]);
  const [savingIdx, setSavingIdx] = useState(null);
  const abortRef = useRef(false);
  const [selectedModel, setSelectedModel] = useState("haiku");
  
  const [discoverBrand, setDiscoverBrand] = useState("");
  const [discoverCategory, setDiscoverCategory] = useState("");
  const [discoverUrl, setDiscoverUrl] = useState("");
  const [discovered, setDiscovered] = useState([]);
  const [discoverPhase, setDiscoverPhase] = useState("idle");
  const [selectedModels, setSelectedModels] = useState(new Set());
  const [allBrands, setAllBrands] = useState([]);
  const [brandSearch, setBrandSearch] = useState("");

  const loadBrands = useCallback(async () => {
    try {
      const res = await supaFetch("brand_catalog?is_active=eq.true&select=brand_name,parent_company&order=brand_name&limit=500");
      const data = await res.json();
      setAllBrands(data || []);
    } catch {}
  }, []);

  const brandsLoaded = useRef(false);
  if (!brandsLoaded.current) { brandsLoaded.current = true; loadBrands(); }

  const loadExisting = useCallback(async () => {
    setLoading(true);
    try {
      const res = await supaFetch("aiq_products?select=id,model,brand_name,category,width_inches,height_inches,depth_inches,msrp,finish,color,status&order=brand_name,model&limit=500");
      const data = await res.json();
      setExistingProducts(data || []);
    } catch (e) { setErrors((p) => [...p, e.message]); }
    setLoading(false);
  }, []);

  const [autoSave, setAutoSave] = useState(true);
  const [saveQueue, setSaveQueue] = useState([]);
  const saveCountRef = useRef({ saved: 0, failed: 0 });

  const doSave = async (data) => {
    try {
      const checkRes = await supaFetch(`aiq_products?model=eq.${encodeURIComponent(data.model)}&brand_name=eq.${encodeURIComponent(data.brand_name)}&select=id,organization_id`);
      const existing = await checkRes.json();
      const pricing = data.pricing || {};
      const cond = data.condition || {};
      const specs = data.specs || {};

      const productData = {
        manufacturer_name: data.manufacturer_name || data.brand_name,
        brand_name: data.brand_name, model: data.model,
        category: data.category || "refrigeration",
        product_line: data.product_line || null, series: data.series || null,
        short_description: data.short_description || null, long_description: data.long_description || null,
        features_html: data.features ? "<ul>" + data.features.map(f => "<li>" + f + "</li>").join("") + "</ul>" : null,
        msrp: pricing.msrp ? parseFloat(pricing.msrp) : (data.msrp ? parseFloat(data.msrp) : null),
        map_price: pricing.sale_price ? parseFloat(pricing.sale_price) : null,
        sale_price: pricing.sale_price ? parseFloat(pricing.sale_price) : null,
        lowest_price: pricing.lowest_price ? parseFloat(pricing.lowest_price) : null,
        lowest_price_source: pricing.lowest_price_source || null,
        price_currency: pricing.price_currency || "CAD",
        price_checked_at: new Date().toISOString(),
        upc: data.upc || null, ean: data.ean || null,
        finish: data.finish || null, color: data.color || null, color_family: data.color_family || null,
        available_colors: data.available_colors ? JSON.stringify(data.available_colors) : "[]",
        energy_star: data.energy_star, ada_compliant: data.ada_compliant,
        width_inches: data.width_inches ? parseFloat(data.width_inches) : null,
        height_inches: data.height_inches ? parseFloat(data.height_inches) : null,
        depth_inches: data.depth_inches ? parseFloat(data.depth_inches) : null,
        weight_lbs: data.weight_lbs ? parseFloat(data.weight_lbs) : null,
        depth_with_handles: specs.depth_with_handles ? parseFloat(specs.depth_with_handles) : null,
        depth_without_handles: specs.depth_without_handles ? parseFloat(specs.depth_without_handles) : null,
        capacity_cu_ft: specs.capacity_cu_ft ? parseFloat(specs.capacity_cu_ft) : null,
        voltage: specs.voltage || null, amperage: specs.amperage ? parseFloat(specs.amperage) : null,
        wattage: specs.wattage ? parseFloat(specs.wattage) : null, frequency_hz: specs.frequency_hz || null,
        installation_type: specs.installation_type || null, specs_json: JSON.stringify(specs),
        status: cond.status || data.status || "active",
        condition_flags: cond.flags || [], is_discontinued: cond.is_discontinued || false,
        is_clearance: cond.is_clearance || false, is_end_of_life: cond.is_end_of_life || false,
        is_open_box: cond.is_open_box || false, is_refurbished: cond.is_refurbished || false,
        replacement_model: cond.replacement_model || null, condition_notes: cond.notes || null,
        made_in: data.made_in || null, country_availability: data.country_availability || ["CA", "US"],
        source_type: "web_scrape", source_reference: data.source_url || null,
        source_confidence: 0.85, source_extracted_at: new Date().toISOString(),
        source_review_status: "approved", updated_at: new Date().toISOString(),
      };

      let productId;
      if (existing && existing.length > 0) {
        productId = existing[0].id;
        const res = await supaFetch(`aiq_products?id=eq.${productId}`, { method: "PATCH", body: JSON.stringify(productData) });
        if (!res.ok) throw new Error(await res.text());
        setSaved(p => [...p, { model: data.model, action: "updated", id: productId }]);
      } else {
        const orgRes = await supaFetch("organizations?select=id&limit=1");
        const orgs = await orgRes.json();
        if (!orgs.length) throw new Error("No organization found");
        productData.organization_id = orgs[0].id;
        productData.approval_status = "approved";
        productData.public_visible = true;
        productData.version_number = 1;
        const res = await supaFetch("aiq_products", { method: "POST", body: JSON.stringify(productData) });
        if (!res.ok) throw new Error(await res.text());
        const created = await res.json();
        productId = created[0]?.id;
        setSaved(p => [...p, { model: data.model, action: "created", id: productId }]);
      }
      if (!productId) {
        const lookup = await supaFetch(`aiq_products?model=eq.${encodeURIComponent(data.model)}&brand_name=eq.${encodeURIComponent(data.brand_name)}&select=id`);
        productId = (await lookup.json())?.[0]?.id;
      }
      if (productId) {
        if (data.images) {
          await supaFetch(`pim_product_images?product_id=eq.${productId}&source=eq.web_scrape`, { method: "DELETE", headers: { Prefer: "return=minimal" } }).catch(() => {});
          const imgs = data.images.map(img => typeof img === "string" ? { url: img, type: "product" } : img).filter(img => img?.url);
          for (let i = 0; i < imgs.length; i++) {
            await supaFetch("pim_product_images", { method: "POST", body: JSON.stringify({
              product_id: productId, image_type: imgs[i].type || (i === 0 ? "hero" : "product"),
              file_url: imgs[i].url, alt_text: imgs[i].alt || `${data.brand_name} ${data.model}`,
              is_primary: i === 0, display_order: i + 1, source: "web_scrape",
              approved: true, audience_tiers: ["public"], embargoed: false,
            }), headers: { Prefer: "return=minimal" } }).catch(() => {});
          }
        }
        if (data.documents) {
          for (const doc of data.documents.filter(d => d.url)) {
            const existDoc = await supaFetch(`pim_product_documents?product_id=eq.${productId}&doc_type=eq.${encodeURIComponent(doc.type)}&select=id`).then(r => r.json()).catch(() => []);
            if (existDoc.length === 0) {
              await supaFetch("pim_product_documents", { method: "POST", body: JSON.stringify({
                product_id: productId, doc_type: doc.type,
                title: doc.title || `${data.brand_name} ${data.model} ${doc.type.replace(/_/g, " ")}`,
                file_url: doc.url, file_name: doc.url.split("/").pop() || `${doc.type}.pdf`,
                mime_type: doc.url.endsWith(".pdf") ? "application/pdf" : "text/html",
                language: "en", locale: "en-CA", is_current: true, source: "web_scrape",
                approved: true, audience_tiers: ["public"], embargoed: false,
              }), headers: { Prefer: "return=minimal" } }).catch(() => {});
            }
          }
        }
        if (data.features?.length) {
          await supaFetch(`pim_product_features?product_id=eq.${productId}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }).catch(() => {});
          for (let i = 0; i < data.features.length; i++) {
            await supaFetch("pim_product_features", { method: "POST", body: JSON.stringify({
              product_id: productId, feature_category: "general", feature_name: data.features[i],
              feature_value: "true", is_key_feature: i < 5, is_differentiator: false, display_order: i + 1,
            }), headers: { Prefer: "return=minimal" } }).catch(() => {});
          }
        }
        if (data.width_inches || data.height_inches || data.depth_inches || specs.cutout_width) {
          const existDim = await supaFetch(`pim_product_dimensions?product_id=eq.${productId}&select=id`).then(r => r.json()).catch(() => []);
          const dimData = {
            product_id: productId, dimension_type: "product",
            width_inches: data.width_inches ? parseFloat(data.width_inches) : null,
            height_inches: data.height_inches ? parseFloat(data.height_inches) : null,
            depth_inches: data.depth_inches ? parseFloat(data.depth_inches) : null,
            depth_with_handle_inches: specs.depth_with_handles ? parseFloat(specs.depth_with_handles) : null,
            weight_lbs: data.weight_lbs ? parseFloat(data.weight_lbs) : null,
            cutout_width: specs.cutout_width ? parseFloat(specs.cutout_width) : null,
            cutout_height: specs.cutout_height ? parseFloat(specs.cutout_height) : null,
            cutout_depth: specs.cutout_depth ? parseFloat(specs.cutout_depth) : null,
            door_swing_direction: specs.door_swing || null, ada_compliant: data.ada_compliant || false,
          };
          if (existDim.length > 0) {
            await supaFetch(`pim_product_dimensions?id=eq.${existDim[0].id}`, { method: "PATCH", body: JSON.stringify(dimData), headers: { Prefer: "return=minimal" } }).catch(() => {});
          } else {
            await supaFetch("pim_product_dimensions", { method: "POST", body: JSON.stringify(dimData), headers: { Prefer: "return=minimal" } }).catch(() => {});
          }
        }
        if (data.energy_star || specs.annual_energy_kwh || specs.decibels) {
          const existCert = await supaFetch(`pim_product_certifications?product_id=eq.${productId}&cert_type=eq.energy&select=id`).then(r => r.json()).catch(() => []);
          const certData = {
            product_id: productId, cert_type: "energy", cert_body: data.energy_star ? "ENERGY STAR" : "NRCan",
            is_current: true, energy_star_rating: data.energy_star ? 1 : 0,
            annual_energy_kwh: specs.annual_energy_kwh ? parseFloat(specs.annual_energy_kwh) : null,
            noise_level_dba: specs.decibels ? parseFloat(specs.decibels) : null,
          };
          if (existCert.length > 0) {
            await supaFetch(`pim_product_certifications?id=eq.${existCert[0].id}`, { method: "PATCH", body: JSON.stringify(certData), headers: { Prefer: "return=minimal" } }).catch(() => {});
          } else {
            await supaFetch("pim_product_certifications", { method: "POST", body: JSON.stringify(certData), headers: { Prefer: "return=minimal" } }).catch(() => {});
          }
        }
        if (pricing.msrp || pricing.sale_price || pricing.lowest_price) {
          await supaFetch("pim_price_history", { method: "POST", body: JSON.stringify({
            product_id: productId, msrp: pricing.msrp ? parseFloat(pricing.msrp) : null,
            sale_price: pricing.sale_price ? parseFloat(pricing.sale_price) : null,
            lowest_price: pricing.lowest_price ? parseFloat(pricing.lowest_price) : null,
            lowest_price_source: pricing.lowest_price_source || null,
            price_currency: pricing.price_currency || "CAD", source_url: data.source_url || null,
          }), headers: { Prefer: "return=minimal" } }).catch(() => {});
        }
      }
      saveCountRef.current.saved++;
      return true;
    } catch (e) {
      setErrors(p => [...p, `Auto-save ${data.model}: ${e.message}`]);
      saveCountRef.current.failed++;
      return false;
    }
  };

  const runScrape = async (q) => {
    try {
      const r = await scrapeProduct(q, selectedModel);
      r.query = q;
      return r;
    } catch (e) { return { found: false, query: q, error: e.message }; }
  };

  const scrapeAndMaybeSave = async (q) => {
    const r = await runScrape(q);
    if (autoSave && r.found) {
      await doSave(r);
    } else {
      setResults(p => [...p, r]);
    }
    return r;
  };

  const handleSingle = async () => {
    if (!query.trim()) return;
    setLoading(true);
    setProgress({ current: 1, total: 1, currentQuery: query + " (searching & extracting…)" });
    await scrapeAndMaybeSave(query);
    setLoading(false);
  };

  const handleBulk = async () => {
    const lines = bulkText.split("\n").map((l) => l.trim()).filter(Boolean);
    if (!lines.length) return;
    setLoading(true);
    abortRef.current = false;
    saveCountRef.current = { saved: 0, failed: 0 };
    for (let i = 0; i < lines.length; i++) {
      if (abortRef.current) break;
      setProgress({ current: i + 1, total: lines.length, currentQuery: lines[i] });
      await scrapeAndMaybeSave(lines[i]);
      if (i < lines.length - 1) await new Promise((r) => setTimeout(r, 1500));
    }
    setLoading(false);
  };

  const handleEnrichExisting = async () => {
    if (!existingProducts.length) await loadExisting();
    const incomplete = existingProducts.filter((p) => !p.width_inches || !p.msrp || !p.finish);
    if (!incomplete.length) { setErrors((p) => [...p, "All products already have specs"]); return; }
    const lines = incomplete.slice(0, 20).map((p) => `${p.brand_name} ${p.model}`);
    setBulkText(lines.join("\n"));
    setMode("bulk");
  };

  const REFRIG_SUBCATS = ["french door refrigerators", "side-by-side refrigerators", "top freezer refrigerators", "bottom freezer refrigerators", "counter-depth refrigerators", "compact refrigerators"];
  const COOKING_SUBCATS = ["gas ranges", "electric ranges", "induction ranges", "double oven ranges", "slide-in ranges"];
  const LAUNDRY_SUBCATS = ["front load washers", "top load washers", "dryers", "washer dryer combos"];

  const getSubcats = (category) => {
    if (!category) return [""];
    const c = category.toLowerCase();
    if (c.includes("refrig")) return REFRIG_SUBCATS;
    if (c.includes("range")) return COOKING_SUBCATS;
    if (c.includes("washer") || c.includes("laundry")) return LAUNDRY_SUBCATS;
    return [category];
  };

  const handleDiscover = async () => {
    const brand = discoverBrand.trim();
    const category = discoverCategory.trim();
    const url = discoverUrl.trim();
    if (!brand && !url) return;
    
    setDiscoverPhase("discovering");
    setLoading(true);
    setDiscovered([]);
    setSelectedModels(new Set());
    
    let allProducts = [];

    if (url) {
      setProgress({ current: 1, total: 1, currentQuery: "Scanning page…" });
      const result = await callAI(DISCOVER_PROMPT, `Find all product model numbers listed on: ${url}`, selectedModel);
      if (result.found && result.products) allProducts = result.products;
    } else {
      const subcats = getSubcats(category);
      for (let i = 0; i < subcats.length; i++) {
        if (abortRef.current) break;
        const subcat = subcats[i];
        setProgress({ current: i + 1, total: subcats.length, currentQuery: `${brand} ${subcat || "all products"}` });
        
        const searchQuery = subcat
          ? `Find ALL ${brand} ${subcat} currently available on the ${brand} Canadian website. List every model number.`
          : `Find ALL ${brand} ${category || "appliance"} products on the ${brand} Canadian website. List every model number. Search each subcategory.`;
        
        const result = await callAI(DISCOVER_PROMPT, searchQuery, selectedModel);
        if (result.found && result.products) {
          allProducts = [...allProducts, ...result.products];
        }
        if (i < subcats.length - 1) await new Promise(r => setTimeout(r, 1500));
      }
    }

    const seen = new Set();
    const deduped = [];
    for (const p of allProducts) {
      const key = p.model?.toUpperCase();
      if (key && !seen.has(key)) { seen.add(key); deduped.push(p); }
    }

    if (deduped.length > 0) {
      if (!existingProducts.length) {
        try {
          const res = await supaFetch("aiq_products?select=model,brand_name&limit=1000");
          const ep = await res.json();
          setExistingProducts(ep || []);
        } catch {}
      }
      const existingModels2 = new Set(existingProducts.map(p => p.model?.toUpperCase()));
      const products = deduped.map(p => ({
        ...p,
        inPIM: existingModels2.has(p.model?.toUpperCase()),
      }));
      setDiscovered(products);
      setSelectedModels(new Set(products.filter(p => !p.inPIM).map(p => p.model)));
      setDiscoverPhase("discovered");
    } else {
      setErrors(p => [...p, `No products found for ${brand} ${category}`]);
      setDiscoverPhase("idle");
    }
    setLoading(false);
  };

  const handleScrapeSelected = async () => {
    const toScrape = discovered.filter(p => selectedModels.has(p.model));
    if (!toScrape.length) return;
    
    setDiscoverPhase("scraping");
    setLoading(true);
    abortRef.current = false;
    saveCountRef.current = { saved: 0, failed: 0 };
    
    for (let i = 0; i < toScrape.length; i++) {
      if (abortRef.current) break;
      const p = toScrape[i];
      const q = p.url || `${discoverBrand} ${p.model}`;
      setProgress({ current: i + 1, total: toScrape.length, currentQuery: `${p.model} — ${p.name || ""}` });
      const r = await runScrape(q);
      if (r.found) {
        if (!r.model) r.model = p.model;
        if (!r.brand_name && discoverBrand) r.brand_name = discoverBrand;
        if (autoSave) {
          await doSave(r);
        } else {
          setResults(prev => [...prev, r]);
        }
      } else {
        setResults(prev => [...prev, r]);
      }
      if (i < toScrape.length - 1) await new Promise(r => setTimeout(r, 2000));
    }
    
    setLoading(false);
    setDiscoverPhase("discovered");
  };

  const toggleModel = (model) => {
    setSelectedModels(prev => {
      const next = new Set(prev);
      next.has(model) ? next.delete(model) : next.add(model);
      return next;
    });
  };

  const toggleAll = () => {
    if (selectedModels.size === discovered.filter(p => !p.inPIM).length) {
      setSelectedModels(new Set());
    } else {
      setSelectedModels(new Set(discovered.filter(p => !p.inPIM).map(p => p.model)));
    }
  };

  const missCount = existingProducts.filter((p) => !p.width_inches || !p.msrp || !p.finish).length;

  return (
    <div style={s.app}>
      <style>{`@keyframes spin { to { transform: rotate(360deg) } } ::placeholder { color: ${palette.textMuted} } input:focus, textarea:focus { border-color: ${palette.accent} }`}</style>

      <div style={s.header}>
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <div style={s.logo}>PIM <span style={s.logoAccent}>Scraper</span></div>
          <div style={{ display: "flex", gap: 4 }}>
            {[
              ["single", "Single"], ["bulk", "Bulk"], ["discover", "🌐 Site Scrape"],
              ["price", "💰 Price Check"], ["retailer", "🏪 Retailer Prices"],
              ["intel", "🔍 Intelligence"], ["media", "📸 Media"],
              ["existing", "Enrich Existing"],
            ].map(([m, label]) => (
              <button key={m} style={{ ...s.tab, ...(mode === m ? s.tabActive : {}) }} onClick={() => { setMode(m); if (m === "existing") loadExisting(); }}>{label}</button>
            ))}
          </div>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, padding: "6px 12px", background: autoSave ? palette.greenSoft : palette.card, border: `1px solid ${autoSave ? palette.green + "40" : palette.border}`, borderRadius: 8, cursor: "pointer" }}
            onClick={() => setAutoSave(!autoSave)}>
            <div style={{ width: 36, height: 20, borderRadius: 10, background: autoSave ? palette.green : palette.border, position: "relative", transition: "background 0.2s" }}>
              <div style={{ width: 16, height: 16, borderRadius: 8, background: "#fff", position: "absolute", top: 2, left: autoSave ? 18 : 2, transition: "left 0.2s" }} />
            </div>
            <span style={{ fontSize: 12, fontWeight: 600, color: autoSave ? palette.green : palette.textMuted }}>Auto-save to PIM</span>
          </div>
          <ModelSelector selected={selectedModel} onChange={setSelectedModel} />
        </div>
      </div>

      <div style={s.main}>
        {(saved.length > 0 || results.length > 0) && (
          <div style={{ display: "flex", gap: 32, marginBottom: 24, alignItems: "center" }}>
            <div style={s.stat}><div style={s.statNum}>{results.filter((r) => r.found).length}</div><div style={s.statLabel}>Pending review</div></div>
            <div style={s.stat}><div style={{ ...s.statNum, color: palette.green }}>{saved.length}</div><div style={s.statLabel}>Saved to PIM</div></div>
            <div style={s.stat}><div style={{ ...s.statNum, color: palette.red }}>{results.filter((r) => !r.found).length}</div><div style={s.statLabel}>Not found</div></div>
            {results.filter(r => r.found).length > 0 && (
              <button style={{ ...s.btn, ...s.btnGreen, marginLeft: "auto" }}
                onClick={async () => {
                  const found = results.filter(r => r.found);
                  for (const r of found) { await doSave(r); }
                  setResults(prev => prev.filter(r => !r.found));
                }}>
                Save All {results.filter(r => r.found).length} to PIM
              </button>
            )}
            {results.length > 0 && (
              <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }}
                onClick={() => setResults([])}>
                Clear All
              </button>
            )}
          </div>
        )}

        {mode === "single" && (
          <div style={s.inputRow}>
            <input style={s.input} placeholder="Brand + Model (e.g. Whirlpool WRF555SDFZ) or product page URL" value={query} onChange={(e) => setQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && !loading && handleSingle()} />
            <button style={s.btn} onClick={handleSingle} disabled={loading}>
              {loading ? <span style={s.spinner} /> : "Scrape"}
            </button>
          </div>
        )}

        {mode === "bulk" && (
          <div style={{ marginBottom: 24 }}>
            <textarea style={s.textarea} rows={6} placeholder={"One product per line:\nWhirlpool WRF555SDFZ\nKitchenAid KRFC704FPS\nMaytag MFI2570FEZ"} value={bulkText} onChange={(e) => setBulkText(e.target.value)} />
            <div style={{ display: "flex", gap: 8, marginTop: 12, alignItems: "center" }}>
              <button style={s.btn} onClick={handleBulk} disabled={loading}>
                {loading ? `Scraping ${progress.current}/${progress.total}…` : `Scrape ${bulkText.split("\n").filter(Boolean).length} Products`}
              </button>
              {loading && <button style={{ ...s.btn, ...s.btnOutline }} onClick={() => { abortRef.current = true; }}>Stop</button>}
              {loading && <span style={{ fontSize: 13, color: palette.textDim }}>{progress.currentQuery}</span>}
            </div>
          </div>
        )}

        {mode === "existing" && (
          <div style={{ ...s.card, marginBottom: 24 }}>
            <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 8 }}>Enrich Existing Products</div>
            <div style={{ fontSize: 13, color: palette.textDim, marginBottom: 16 }}>
              {existingProducts.length} products in PIM{missCount > 0 && <>, <span style={{ color: palette.yellow }}>{missCount} missing specs</span></>}
            </div>
            {missCount > 0 && (
              <button style={s.btn} onClick={handleEnrichExisting}>
                Scrape top 20 incomplete products
              </button>
            )}
            {existingProducts.length > 0 && (
              <div style={{ marginTop: 16, maxHeight: 300, overflow: "auto" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
                  <thead><tr style={{ borderBottom: `1px solid ${palette.border}` }}>
                    {["Brand","Model","Category","Width","MSRP","Finish","Status"].map((h) => (
                      <th key={h} style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted, fontWeight: 500 }}>{h}</th>
                    ))}
                  </tr></thead>
                  <tbody>{existingProducts.map((p) => (
                    <tr key={p.id} style={{ borderBottom: `1px solid ${palette.border}20` }}>
                      <td style={{ padding: "6px 8px" }}>{p.brand_name}</td>
                      <td style={{ padding: "6px 8px", fontFamily: "monospace", fontSize: 11 }}>{p.model}</td>
                      <td style={{ padding: "6px 8px" }}>{p.category}</td>
                      <td style={{ padding: "6px 8px", color: p.width_inches ? palette.green : palette.red }}>{p.width_inches || "—"}</td>
                      <td style={{ padding: "6px 8px", color: p.msrp ? palette.green : palette.red }}>{p.msrp ? `$${p.msrp}` : "—"}</td>
                      <td style={{ padding: "6px 8px", color: p.finish ? palette.green : palette.red }}>{p.finish || "—"}</td>
                      <td style={{ padding: "6px 8px" }}><Badge color={p.status === "active" ? "green" : "yellow"}>{p.status}</Badge></td>
                    </tr>
                  ))}</tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {mode === "discover" && (
          <div style={{ marginBottom: 24 }}>
            <div style={s.card}>
              <div style={{ fontSize: 15, fontWeight: 600, marginBottom: 4 }}>Discover Products from Manufacturer Site</div>
              <div style={{ fontSize: 13, color: palette.textDim, marginBottom: 16 }}>Pick a brand and category — or paste a URL — and the scraper will find every product listed.</div>

              <div style={{ ...s.label, marginBottom: 8 }}>Brand ({allBrands.length})</div>
              <input style={{ ...s.input, marginBottom: 8 }} placeholder="Search brands…" value={brandSearch}
                onChange={e => setBrandSearch(e.target.value)} />
              <div style={{ display: "flex", gap: 6, flexWrap: "wrap", marginBottom: 16, maxHeight: brandSearch ? 200 : 80, overflow: "auto" }}>
                {allBrands
                  .filter(b => !brandSearch || b.brand_name.toLowerCase().includes(brandSearch.toLowerCase()) || b.parent_company?.toLowerCase().includes(brandSearch.toLowerCase()))
                  .map(b => (
                  <button key={b.brand_name} onClick={() => { setDiscoverBrand(b.brand_name); setDiscoverCategory(""); setDiscoverUrl(""); setDiscoverPhase("idle"); setDiscovered([]); setBrandSearch(""); }}
                    style={{ ...s.btn, ...s.btnSm, ...(discoverBrand === b.brand_name ? {} : { ...s.btnOutline }), padding: "5px 10px", fontSize: 11 }}>
                    {b.brand_name}
                  </button>
                ))}
              </div>

              {discoverBrand && (
                <div style={{ marginBottom: 16 }}>
                  <div style={{ ...s.label, marginBottom: 8 }}>Category</div>
                  <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
                    <button onClick={() => setDiscoverCategory("")}
                      style={{ ...s.btn, ...s.btnSm, ...(!discoverCategory ? {} : { ...s.btnOutline }), padding: "5px 10px", fontSize: 11 }}>
                      All
                    </button>
                    {APPLIANCE_CATEGORIES.map(c => (
                      <button key={c} onClick={() => setDiscoverCategory(c)}
                        style={{ ...s.btn, ...s.btnSm, ...(discoverCategory === c ? {} : { ...s.btnOutline }), padding: "5px 10px", fontSize: 11 }}>
                        {c.replace(/-/g, " ")}
                      </button>
                    ))}
                  </div>
                </div>
              )}

              <div style={{ ...s.label, marginBottom: 8 }}>Or paste a product listing URL</div>
              <div style={s.inputRow}>
                <input style={s.input} placeholder="e.g. https://www.lg.com/ca/refrigerators/" value={discoverUrl} onChange={e => setDiscoverUrl(e.target.value)} />
              </div>

              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <button style={s.btn} onClick={handleDiscover} disabled={loading || discoverPhase === "discovering"}>
                  {discoverPhase === "discovering" ? (
                    <><span style={s.spinner} /> Discovering… {progress.current}/{progress.total}</>
                  ) : (
                    `🔍 Discover ${discoverBrand || ""}${discoverCategory ? " " + discoverCategory.replace(/-/g, " ") : ""} Products`
                  )}
                </button>
                {discoverPhase === "discovering" && <span style={{ fontSize: 13, color: palette.textDim }}>{progress.currentQuery}</span>}
                {discoverPhase === "discovering" && <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={() => { abortRef.current = true; }}>Stop</button>}
              </div>
            </div>

            {discovered.length > 0 && (
              <div style={s.card}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 16 }}>
                  <div>
                    <div style={{ fontSize: 15, fontWeight: 600 }}>{discovered.length} Products Found</div>
                    <div style={{ fontSize: 13, color: palette.textDim }}>
                      <span style={{ color: palette.green }}>{discovered.filter(p => p.inPIM).length} already in PIM</span>
                      {" · "}
                      <span style={{ color: palette.yellow }}>{discovered.filter(p => !p.inPIM).length} new</span>
                      {" · "}
                      <span style={{ color: palette.accent }}>{selectedModels.size} selected</span>
                    </div>
                  </div>
                  <div style={{ display: "flex", gap: 8 }}>
                    <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={toggleAll}>
                      {selectedModels.size === discovered.filter(p => !p.inPIM).length ? "Deselect All" : "Select All New"}
                    </button>
                    <button style={{ ...s.btn, ...s.btnSm, ...s.btnGreen }} onClick={handleScrapeSelected}
                      disabled={loading || selectedModels.size === 0}>
                      {discoverPhase === "scraping" ? `Scraping ${progress.current}/${progress.total}…` : `Scrape ${selectedModels.size} Selected`}
                    </button>
                    {discoverPhase === "scraping" && (
                      <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={() => { abortRef.current = true; }}>Stop</button>
                    )}
                  </div>
                </div>

                {discoverPhase === "scraping" && progress.currentQuery && (
                  <div style={{ fontSize: 13, color: palette.accent, marginBottom: 12 }}>⏳ {progress.currentQuery}</div>
                )}

                <div style={{ maxHeight: 400, overflow: "auto" }}>
                  <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
                    <thead><tr style={{ borderBottom: `1px solid ${palette.border}` }}>
                      <th style={{ padding: "6px 8px", width: 30 }}></th>
                      <th style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted }}>Model</th>
                      <th style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted }}>Name</th>
                      <th style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted }}>Category</th>
                      <th style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted }}>Status</th>
                      <th style={{ padding: "6px 8px", textAlign: "left", color: palette.textMuted }}>PIM</th>
                    </tr></thead>
                    <tbody>{discovered.map((p, i) => (
                      <tr key={i} style={{ borderBottom: `1px solid ${palette.border}20`, opacity: p.inPIM ? 0.5 : 1 }}
                        onClick={() => !p.inPIM && toggleModel(p.model)}>
                        <td style={{ padding: "6px 8px", cursor: p.inPIM ? "default" : "pointer" }}>
                          {p.inPIM ? (
                            <span style={{ color: palette.green }}>✓</span>
                          ) : (
                            <input type="checkbox" checked={selectedModels.has(p.model)} readOnly
                              style={{ cursor: "pointer", accentColor: palette.accent }} />
                          )}
                        </td>
                        <td style={{ padding: "6px 8px", fontFamily: "monospace", fontSize: 11, fontWeight: 600 }}>{p.model}</td>
                        <td style={{ padding: "6px 8px", maxWidth: 300, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{p.name}</td>
                        <td style={{ padding: "6px 8px" }}>{p.category}</td>
                        <td style={{ padding: "6px 8px" }}><Badge color={p.status === "active" ? "green" : "yellow"}>{p.status || "active"}</Badge></td>
                        <td style={{ padding: "6px 8px" }}>
                          {p.inPIM ? <Badge color="green">In PIM</Badge> : <Badge color="yellow">New</Badge>}
                        </td>
                      </tr>
                    ))}</tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        )}

        {errors.length > 0 && (
          <div style={{ ...s.card, borderColor: palette.red, marginBottom: 16 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
              <span style={{ color: palette.red, fontWeight: 600, fontSize: 13 }}>Errors</span>
              <button style={{ ...s.btn, ...s.btnSm, ...s.btnOutline }} onClick={() => setErrors([])}>Clear</button>
            </div>
            {errors.slice(-5).map((e, i) => <div key={i} style={{ fontSize: 12, color: palette.textDim, marginBottom: 4 }}>{e}</div>)}
          </div>
        )}

        {saved.length > 0 && (
          <div style={{ marginBottom: 16, display: "flex", gap: 8, flexWrap: "wrap" }}>
            {saved.map((s2, i) => (
              <span key={i} style={{ ...s.badge, background: palette.greenSoft, color: palette.green }}>
                ✓ {s2.model} {s2.action}
              </span>
            ))}
          </div>
        )}

        {results.map((r, i) => (
          <ResultCard key={`${r.model || r.query}-${i}`} result={r} saving={savingIdx === i}
            onSave={async (d) => { setSavingIdx(i); await doSave(d); setResults(p => p.filter((_, j) => j !== i)); setSavingIdx(null); }}
            onDiscard={() => setResults((p) => p.filter((_, j) => j !== i))} />
        ))}

        {!loading && results.length === 0 && saved.length === 0 && (
          <div style={{ textAlign: "center", padding: "64px 0", color: palette.textMuted }}>
            <div style={{ fontSize: 40, marginBottom: 16 }}>🔍</div>
            <div style={{ fontSize: 15, marginBottom: 8 }}>Enter a brand + model number to scrape product specs</div>
            <div style={{ fontSize: 13 }}>Data is pulled from manufacturer websites via web search, then you review and save to PIM</div>
          </div>
        )}
      </div>
    </div>
  );
}
