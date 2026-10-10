type Json = Record<string, unknown>;
type Filters = {
  category?: string | null; brand?: string | null; model?: string | null;
  max_price?: number | null; min_price?: number | null;
  max_width?: number | null; max_height?: number | null; max_depth?: number | null;
  min_capacity?: number | null; finish?: string | null;
  energy_star?: boolean | null; installation_type?: string | null;
  required_terms?: string[]; excluded_terms?: string[];
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function createHandler({ createClient, env, fetchImpl = fetch }: { createClient: any; env: (name: string) => string | undefined; fetchImpl?: typeof fetch }) {
return async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "method_not_allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return reply({ error: "authentication_required" }, 401);

  let body: Json;
  try { body = await req.json(); if (!isValidBody(body)) throw new Error("body"); } catch { return reply({ error: "invalid_json" }, 400); }
  const queryText = String(body.query ?? body.prompt ?? "").trim();
  const suppliedFilters = isObject(body.filters) ? body.filters as Filters : {};
  const limit = Math.max(1, Math.min(Math.trunc(Number(body.limit ?? 5) || 5), 12));
  const country = String(body.country ?? "CA").toUpperCase();
  const retailerName = body.retailer_name ? String(body.retailer_name) : null;
  if (queryText.length < 3 && Object.keys(suppliedFilters).length === 0) {
    return reply({ error: "query_or_filters_required" }, 400);
  }

  const url = env("SUPABASE_URL") ?? "";
  const anonKey = env("SUPABASE_ANON_KEY") ?? "";
  const anthropicKey = env("ANTHROPIC_API_KEY") ?? "";
  const user = createClient(url, anonKey, { global: { headers: { Authorization: auth } } });
  // All catalog reads use the caller JWT and the migrated RLS policies.
  const admin = user.schema("tj");

  const { data: userData, error: userErr } = await user.auth.getUser();
  if (userErr || !userData?.user) return reply({ error: "invalid_session" }, 401);

  const { data: context, error: contextError } = await user.rpc("tj_runtime_my_platform_context");
  if (contextError || !context?.organization_id) return reply({ error: "active_mapped_organization_required" }, 403);
  if (queryText.length > 4000 || !/^[A-Z]{2}$/.test(country) || !validFilters(suppliedFilters)) return reply({ error: "invalid_query_or_filters" }, 400);
  const parsed = queryText && anthropicKey && env("AI_MODEL_LIGHT") ? await parseIntent(queryText, anthropicKey, env("AI_MODEL_LIGHT")!, fetchImpl) : {};
  const filters: Filters = { ...parsed, ...suppliedFilters };

  let q = admin.from("aiq_products_app").select(
    "id,brand_name,manufacturer_name,category,product_family,product_line,series,model,status,msrp,sale_price,lowest_price,price_currency,price_checked_at,short_description,long_description,finish,color,color_family,energy_star,ada_compliant,width_inches,height_inches,depth_inches,depth_with_handles,depth_without_handles,capacity_cu_ft,voltage,amperage,wattage,installation_type,market,country_availability,public_visible,approval_status,is_discontinued,is_clearance,is_end_of_life,specs_json,source_reference,source_confidence,source_review_status,updated_at"
  ).eq("public_visible", true).neq("is_discontinued", true).neq("is_end_of_life", true).limit(120);

  if (filters.category) q = q.ilike("category", `%${safe(filters.category)}%`);
  if (filters.brand) q = q.ilike("brand_name", `%${safe(filters.brand)}%`);
  if (filters.model) q = q.ilike("model", `%${safe(filters.model)}%`);
  if (filters.finish) q = q.or(`finish.ilike.%${safe(filters.finish)}%,color.ilike.%${safe(filters.finish)}%,color_family.ilike.%${safe(filters.finish)}%`);
  if (filters.installation_type) q = q.ilike("installation_type", `%${safe(filters.installation_type)}%`);
  if (filters.energy_star === true) q = q.eq("energy_star", true);
  if (num(filters.max_width)) q = q.lte("width_inches", filters.max_width!);
  if (num(filters.max_height)) q = q.lte("height_inches", filters.max_height!);
  if (num(filters.max_depth)) q = q.lte("depth_inches", filters.max_depth!);
  if (num(filters.min_capacity)) q = q.gte("capacity_cu_ft", filters.min_capacity!);

  const { data: products, error: productErr } = await q;
  if (productErr) return reply({ error: "product_query_failed", detail: "catalog_read_failed" }, 500);

  const ranked = (products ?? []).map((p: Json) => scoreProduct(p, filters, queryText, country))
    .filter((x) => x.hardPass)
    .sort((a, b) => b.score - a.score)
    .slice(0, Math.max(limit * 3, limit));
  const ids = ranked.map((x) => String(x.product.id));

  const [featuresRes, dimsRes, docsRes, imagesRes, pricesRes] = ids.length ? await Promise.all([
    admin.from("pim_product_features").select("product_id,feature_category,feature_name,feature_value,feature_description,is_key_feature,is_differentiator,display_order").in("product_id", ids).order("display_order"),
    admin.from("pim_product_dimensions").select("product_id,dimension_type,width_inches,height_inches,depth_inches,depth_with_door_inches,depth_with_handle_inches,cutout_width,cutout_height,cutout_depth,door_swing_clearance,door_swing_direction,dim_drawing_url,notes").in("product_id", ids),
    admin.from("pim_product_documents").select("product_id,doc_type,title,file_url,language,locale,is_current,approved,verification_status,manufacturer_verified").in("product_id", ids).eq("is_current", true).eq("approved", true),
    admin.from("pim_product_images").select("product_id,image_type,file_url,cdn_url,alt_text,is_primary,approved,verification_status,manufacturer_verified").in("product_id", ids).eq("approved", true).order("is_primary", { ascending: false }),
    retailerName
      ? admin.from("pim_retailer_prices").select("product_id,retailer_name,product_url,price,regular_price,on_sale,sale_label,in_stock,stock_note,price_currency,checked_at,country").in("product_id", ids).ilike("retailer_name", `%${safe(retailerName)}%`).eq("country", country)
      : admin.from("pim_retailer_prices").select("product_id,retailer_name,product_url,price,regular_price,on_sale,sale_label,in_stock,stock_note,price_currency,checked_at,country").in("product_id", ids).eq("country", country),
  ]) : [{data:[]},{data:[]},{data:[]},{data:[]},{data:[]}];

  if ([featuresRes, dimsRes, docsRes, imagesRes, pricesRes].some((r: any) => r.error)) return reply({ error: "catalog_enrichment_failed" }, 500);

  const enriched = ranked.map((r) => {
    const id = String(r.product.id);
    const features = (featuresRes.data ?? []).filter((x: Json) => x.product_id === id);
    const dimensions = (dimsRes.data ?? []).filter((x: Json) => x.product_id === id);
    const documents = (docsRes.data ?? []).filter((x: Json) => x.product_id === id);
    const images = (imagesRes.data ?? []).filter((x: Json) => x.product_id === id);
    const retailerPrices = (pricesRes.data ?? []).filter((x: Json) => x.product_id === id);
    return { ...r, features, dimensions, documents, images, retailer_prices: retailerPrices };
  }).slice(0, limit);

  const installCategories = [...new Set(enriched.map((x) => String(x.product.category ?? "")).filter(Boolean))];
  const { data: installation, error: installationError } = installCategories.length
    ? await admin.from("installation_requirements").select("product_category,subcategory,electrical_voltage,electrical_amperage,electrical_circuit,gas_connection,water_connection,drain_required,ventilation_cfm,min_clearances,typical_install_time,licensed_trades_required,common_issues,notes,country").in("product_category", installCategories).eq("country", country)
    : { data: [], error: null };

  if (installationError) return reply({ error: "installation_read_failed" }, 500);

  const answer = anthropicKey && (env("AI_MODEL_STANDARD") || env("AI_MODEL")) && enriched.length
    ? await explainResults(queryText, filters, enriched, installation ?? [], anthropicKey, (env("AI_MODEL_STANDARD") || env("AI_MODEL"))!, fetchImpl)
    : null;

  return reply({
    engine: "applianceiq-product-intelligence-v1",
    query: queryText,
    parsed_filters: filters,
    result_count: enriched.length,
    products: enriched,
    installation_requirements: installation ?? [],
    answer,
    confidence_notes: buildConfidenceNotes(enriched),
    generated_at: new Date().toISOString(),
  });
};
}

async function parseIntent(text: string, key: string, model: string, fetchImpl: typeof fetch): Promise<Filters> {
  const system = `Convert an appliance shopping request into JSON only. Allowed keys: category, brand, model, max_price, min_price, max_width, max_height, max_depth, min_capacity, finish, energy_star, installation_type, required_terms, excluded_terms. Use inches and CAD amounts as numbers. Use null or omit unknown fields. Map everyday terms to appliance categories where reasonable. Never invent constraints.`;
  try {
    const r = await fetchImpl("https://api.anthropic.com/v1/messages", { method: "POST", headers: {"content-type":"application/json","x-api-key":key,"anthropic-version":"2023-06-01"}, body: JSON.stringify({model,max_tokens:500,system,messages:[{role:"user",content:text}]}) });
    if (!r.ok) return {};
    const d = await r.json();
    const raw = (d.content ?? []).filter((b: Json) => b.type === "text").map((b: Json) => b.text).join("").replace(/^```json\s*|```$/g, "").trim();
    const parsed = JSON.parse(raw); return isObject(parsed) && validFilters(parsed) ? parsed as Filters : {};
  } catch { return {}; }
}

function scoreProduct(product: Json, f: Filters, text: string, country: string) {
  let score = 0; const reasons: string[] = []; const unknowns: string[] = []; let hardPass = true;
  const price = Number(product.sale_price ?? product.lowest_price ?? product.msrp ?? NaN);
  const width = Number(product.width_inches ?? NaN), height = Number(product.height_inches ?? NaN), depth = Number(product.depth_inches ?? NaN), cap = Number(product.capacity_cu_ft ?? NaN);
  if (num(f.max_price)) { if (Number.isFinite(price) && price <= f.max_price!) { score += 25; reasons.push(`price ${price} is within budget`); } else if (Number.isFinite(price)) hardPass = false; else unknowns.push("verified price"); }
  if (num(f.min_price) && Number.isFinite(price) && price < f.min_price!) hardPass = false;
  for (const [label, actual, max] of [["width",width,f.max_width],["height",height,f.max_height],["depth",depth,f.max_depth]] as const) {
    if (num(max)) { if (Number.isFinite(actual) && actual <= max!) { score += 20; reasons.push(`${label} ${actual} in fits the limit`); } else if (Number.isFinite(actual)) hardPass = false; else unknowns.push(label); }
  }
  if (num(f.min_capacity)) { if (Number.isFinite(cap) && cap >= f.min_capacity!) { score += 12; reasons.push(`capacity ${cap} cu. ft. meets minimum`); } else if (Number.isFinite(cap)) hardPass = false; else unknowns.push("capacity"); }
  const hay = JSON.stringify(product).toLowerCase();
  if ((f.excluded_terms ?? []).some(t => hay.includes(t.toLowerCase()))) hardPass = false;
  const terms = [...(f.required_terms ?? []), ...text.toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 4)];
  const matched = [...new Set(terms.filter((t) => hay.includes(t.toLowerCase())))]; score += Math.min(matched.length * 3, 18);
  if (matched.length) reasons.push(`matches: ${matched.slice(0,5).join(", ")}`);
  if (f.energy_star === true && product.energy_star === true) { score += 8; reasons.push("ENERGY STAR certified"); }
  if (product.source_review_status === "approved" || Number(product.source_confidence ?? 0) >= 80) score += 7;
  const countries = Array.isArray(product.country_availability) ? product.country_availability.map(String) : [];
  if (countries.includes(country) || String(product.market ?? "").toUpperCase().includes(country)) score += 5;
  if (product.is_clearance) score -= 3;
  return { product, score, match_reasons: reasons, unknowns: [...new Set(unknowns)], hardPass };
}

async function explainResults(query: string, filters: Filters, results: Json[], installation: Json[], key: string, model: string, fetchImpl: typeof fetch): Promise<string | null> {
  const compact = results.map((r: Json) => ({ score:r.score, reasons:r.match_reasons, unknowns:r.unknowns, product:r.product, features:(r.features as Json[] ?? []).slice(0,12), dimensions:(r.dimensions as Json[] ?? []).slice(0,3), retailer_prices:(r.retailer_prices as Json[] ?? []).slice(0,4), documents:(r.documents as Json[] ?? []).slice(0,6) }));
  const system = `You are Appliance IQ Product Expert. Explain the best matches using only supplied records. Never invent specs, stock, prices, compatibility, reviews, or delivery dates. Clearly label missing data. Prefer three options when available: best overall, best value, and best fit. Mention installation cautions. Cite records inline using [MODEL], [MODEL feature], [MODEL dimensions], [MODEL price], or [installation category]. Be direct and consumer-friendly.`;
  try {
    const r = await fetchImpl("https://api.anthropic.com/v1/messages", { method:"POST", headers:{"content-type":"application/json","x-api-key":key,"anthropic-version":"2023-06-01"}, body:JSON.stringify({model,max_tokens:1600,system,messages:[{role:"user",content:JSON.stringify({query,filters,results:compact,installation})}]}) });
    if (!r.ok) return null; const d = await r.json();
    return (d.content ?? []).filter((b: Json) => b.type === "text").map((b: Json) => String(b.text ?? "")).join("\n") || null;
  } catch { return null; }
}

function buildConfidenceNotes(results: Json[]): string[] {
  const notes: string[] = [];
  if (!results.length) notes.push("No products met all hard constraints in the current PIM dataset.");
  if (results.some((r: Json) => Array.isArray(r.unknowns) && r.unknowns.length)) notes.push("Some candidate records are missing fit or price fields; those unknowns are exposed per product.");
  if (results.some((r: Json) => !(r.retailer_prices as Json[] ?? []).length)) notes.push("Retailer-specific stock and price are unavailable for some results.");
  return notes;
}
function isObject(v: unknown): v is Json { return !!v && typeof v === "object" && !Array.isArray(v); }
function num(v: unknown): v is number { return typeof v === "number" && Number.isFinite(v); }
function safe(v: unknown): string { return String(v ?? "").replace(/[,%()]/g, " ").trim(); }
function reply(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } }); }

function isValidBody(v: unknown): v is Json { return !!v && typeof v === "object" && !Array.isArray(v); }

function validFilters(f: Json): boolean {
  const texts = ["category","brand","model","finish","installation_type"];
  const numbers = ["max_price","min_price","max_width","max_height","max_depth","min_capacity"];
  const keys = new Set([...texts,...numbers,"energy_star","required_terms","excluded_terms"]);
  if (Object.keys(f).some(k => !keys.has(k))) return false;
  if (texts.some(k => f[k] != null && (typeof f[k] !== "string" || String(f[k]).length > 120))) return false;
  if (numbers.some(k => f[k] != null && (!num(f[k]) || Number(f[k]) <= 0))) return false;
  if (f.energy_star != null && typeof f.energy_star !== "boolean") return false;
  return ["required_terms","excluded_terms"].every(k => f[k] == null || (Array.isArray(f[k]) && f[k].length <= 20 && f[k].every(t => typeof t === "string" && t.length > 0 && t.length <= 120)));
}
