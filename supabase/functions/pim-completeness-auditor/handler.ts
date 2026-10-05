const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
type Product = Record<string, any>;

const WEIGHTS = {
  dimensions: 24,
  price: 10,
  identifiers: 8,
  sourceConfidence: 8,
  description: 5,
  features: 15,
  documents: 10,
  images: 10,
  dimensionRecord: 10,
};

export function createHandler({createClient,env}:{createClient:any;env:(name:string)=>string|undefined}) {
return async (req: Request) => {
try {
  if(req.method==="OPTIONS")return new Response("ok",{headers:CORS});
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "authentication_required" }, 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); if(!body || typeof body!=="object" || Array.isArray(body)) throw new Error("body"); } catch { return json({error:"invalid_json"},400); }

  const limit = Math.min(Math.max(Number(body.limit ?? 100), 1), 500);
  const category = body.category ? String(body.category) : null;
  const maxScore = body.max_score == null ? 100 : Math.min(Math.max(Number(body.max_score), 0), 100);

  const url = env("SUPABASE_URL") ?? "";
  const anonKey = env("SUPABASE_ANON_KEY") ?? "";
  const user = createClient(url, anonKey, { global: { headers: { Authorization: auth } }, auth:{persistSession:false,autoRefreshToken:false} });
  const admin = user.schema("tj");

  const { data: userData, error: userErr } = await user.auth.getUser();
  if (userErr || !userData.user) return json({ error: "invalid_session" }, 401);

  const {data:context,error:contextError}=await user.rpc("tj_runtime_my_platform_context");
  if(contextError || !context?.organization_id)return json({error:"active_mapped_organization_required"},403);
  if(body.organization_id && body.organization_id!==context.organization_id)return json({error:"organization_access_denied"},403);
  const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if(!Number.isInteger(limit)||!Number.isFinite(maxScore)|| (category && category.length>120) || (body.after_id && !uuid.test(String(body.after_id))))return json({error:"invalid_audit_filters"},400);
  let productQuery = admin.from("aiq_products_app").select("id,brand_name,model,category,short_description,width_inches,height_inches,depth_inches,msrp,map_price,sale_price,lowest_price,upc,ean,gtin,source_confidence,public_visible,approval_status,status,is_discontinued,is_end_of_life,updated_at",{count:"exact"}).eq("organization_id",context.organization_id).order("id").limit(1000);
  if(body.after_id)productQuery=productQuery.gt("id",body.after_id);
  if (category) productQuery = productQuery.eq("category", category);
  const { data: products, error: productErr, count:totalRemaining } = await productQuery;
  if (productErr) return json({ error: "product_query_failed", detail: "scoped_product_read_failed" }, 500);

  const ids = (products ?? []).map((p: Product) => p.id);
  if (!ids.length) return json({ summary: { total_products: 0 }, products: [] });

  // PostgREST caps rows per response. Read child tables in bounded product batches
  // and paginate, rather than treating a truncated response as a complete count.
  const collect=async(table:string,columns:string)=>{
    const rows:any[]=[];
    for(let i=0;i<ids.length;i+=100){
      const group=ids.slice(i,i+100);
      for(let offset=0;;){
        const result=await admin.from(table).select(columns,{count:"exact"}).in("product_id",group).order("id").range(offset,offset+999);
        if(result.error)throw new Error("catalog_child_read_failed");
        rows.push(...(result.data??[]));
        const length=(result.data??[]).length;
        offset+=length;
        if(typeof result.count!=="number")throw new Error("catalog_child_count_missing");
        if(offset>=result.count)break;
        if(!length || offset>=10000)throw new Error("catalog_child_page_limit");
      }
    }
    return {data:rows};
  };
  const [features,documents,images,dimensions,retailerPrices]=await Promise.all([
    collect("pim_product_features","product_id,id"),
    collect("pim_product_documents","product_id,id,is_current,approved"),
    collect("pim_product_images","product_id,id,approved"),
    collect("pim_product_dimensions","product_id,id"),
    collect("pim_retailer_prices","product_id,id,checked_at,in_stock"),
  ]);

  const countMap = (rows: any[] | null, predicate?: (row: any) => boolean) => {
    const map = new Map<string, number>();
    for (const row of rows ?? []) {
      if (predicate && !predicate(row)) continue;
      map.set(row.product_id, (map.get(row.product_id) ?? 0) + 1);
    }
    return map;
  };

  const featureCounts = countMap(features.data);
  const documentCounts = countMap(documents.data, (r) => r.is_current === true && r.approved === true);
  const imageCounts = countMap(images.data, (r) => r.approved === true);
  const dimensionCounts = countMap(dimensions.data);
  const priceCounts = countMap(retailerPrices.data);

  const scored = (products ?? []).map((p: Product) => scoreProduct(p, {
    feature_count: featureCounts.get(p.id) ?? 0,
    document_count: documentCounts.get(p.id) ?? 0,
    image_count: imageCounts.get(p.id) ?? 0,
    dimension_record_count: dimensionCounts.get(p.id) ?? 0,
    retailer_price_count: priceCounts.get(p.id) ?? 0,
  })).filter((p) => p.completeness_score <= maxScore)
    .sort((a, b) => a.completeness_score - b.completeness_score || a.brand_name.localeCompare(b.brand_name) || a.model.localeCompare(b.model));

  const categorySummary = new Map<string, { count: number; total: number }>();
  for (const p of scored) {
    const key = p.category || "uncategorized";
    const item = categorySummary.get(key) ?? { count: 0, total: 0 };
    item.count += 1; item.total += p.completeness_score;
    categorySummary.set(key, item);
  }

  const missingTotals: Record<string, number> = {};
  for (const p of scored) for (const field of p.missing) missingTotals[field] = (missingTotals[field] ?? 0) + 1;

  const average = scored.length ? Math.round((scored.reduce((s, p) => s + p.completeness_score, 0) / scored.length) * 10) / 10 : 0;

  return json({
    generated_at: new Date().toISOString(),
    scoring_version: "1.1",
    organization_id:context.organization_id,
    scanned_products:products?.length??0,
    next_cursor:(totalRemaining??0)>(products?.length??0)?products[products.length-1].id:null,
    scope_note:"Completeness describes accessible records in this organization and page; it does not certify accuracy.",
    summary: {
      total_products: scored.length,
      average_completeness_score: average,
      ready_for_customer_ai: scored.filter((p) => p.readiness === "ready").length,
      needs_review: scored.filter((p) => p.readiness === "review").length,
      blocked: scored.filter((p) => p.readiness === "blocked").length,
      missing_totals: Object.entries(missingTotals).sort((a, b) => b[1] - a[1]).map(([field, count]) => ({ field, count })),
      by_category: [...categorySummary.entries()].map(([category, v]) => ({ category, products: v.count, average_score: Math.round((v.total / v.count) * 10) / 10 })).sort((a, b) => a.average_score - b.average_score),
    },
    products: scored.slice(0, limit),
  });
} catch { return json({error:"catalog_audit_unavailable"},502); }
};
}

function scoreProduct(p: Product, counts: Record<string, number>) {
  let score = 0;
  const missing: string[] = [];
  const warnings: string[] = [];

  const hasWidth = positive(p.width_inches);
  const hasHeight = positive(p.height_inches);
  const hasDepth = positive(p.depth_inches);
  score += (hasWidth ? 8 : 0) + (hasHeight ? 8 : 0) + (hasDepth ? 8 : 0);
  if (!hasWidth) missing.push("width");
  if (!hasHeight) missing.push("height");
  if (!hasDepth) missing.push("depth");

  const price = [p.sale_price,p.lowest_price,p.map_price,p.msrp].find(positive);
  if (positive(price)) score += WEIGHTS.price; else missing.push("price");

  if (p.upc || p.ean || p.gtin) score += WEIGHTS.identifiers; else missing.push("upc_ean_gtin");
  if (typeof p.source_confidence==="number" && Number.isFinite(p.source_confidence) && p.source_confidence>=0 && p.source_confidence<=100) score += WEIGHTS.sourceConfidence; else missing.push("source_confidence");
  if (p.short_description?.trim()) score += WEIGHTS.description; else missing.push("short_description");
  if (counts.feature_count > 0) score += WEIGHTS.features; else missing.push("features");
  if (counts.document_count > 0) score += WEIGHTS.documents; else missing.push("current_documents");
  if (counts.image_count > 0) score += WEIGHTS.images; else missing.push("approved_images");
  if (counts.dimension_record_count > 0) score += WEIGHTS.dimensionRecord; else missing.push("dimension_record");

  if (counts.retailer_price_count === 0) warnings.push("no_retailer_price_observations");
  if (p.is_discontinued || p.is_end_of_life) warnings.push("not_current_product");
  if (p.status && !["active", "published"].includes(String(p.status).toLowerCase())) warnings.push(`status_${p.status}`);

  const criticalMissing = missing.filter((m) => ["width", "height", "depth", "price", "features", "current_documents"].includes(m));
  const publishable = p.public_visible===true && p.approval_status==="approved" && ["active","published"].includes(p.status) && !p.is_discontinued && !p.is_end_of_life;
  if(!publishable) warnings.push("not_approved_for_customer_use");
  const readiness = publishable && score >= 80 && criticalMissing.length === 0 ? "ready" : score >= 50 ? "review" : "blocked";
  const priority = score < 30 ? "urgent" : score < 50 ? "high" : score < 80 ? "medium" : "low";

  return {
    product_id: p.id,
    brand_name: p.brand_name ?? "Unknown",
    model: p.model ?? "Unknown",
    category: p.category ?? "uncategorized",
    completeness_score: score,
    readiness,
    priority,
    missing,
    warnings,
    counts,
    recommended_next_actions: missing.slice(0, 5).map((field) => actionFor(field)),
    updated_at: p.updated_at,
  };
}

function actionFor(field: string): string {
  const actions: Record<string, string> = {
    width: "Add verified product width in inches",
    height: "Add verified product height in inches",
    depth: "Add verified product depth in inches",
    price: "Add a current MSRP, MAP, sale, or verified market price",
    upc_ean_gtin: "Add at least one global product identifier",
    source_confidence: "Assign and verify the source-confidence score",
    short_description: "Add a customer-facing short description",
    features: "Extract and review product features",
    current_documents: "Attach a current approved spec sheet or manual",
    approved_images: "Attach at least one approved product image",
    dimension_record: "Create the detailed dimensional record",
  };
  return actions[field] ?? `Complete ${field}`;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function positive(v:unknown):boolean{return typeof v==="number" && Number.isFinite(v) && v>0;}
