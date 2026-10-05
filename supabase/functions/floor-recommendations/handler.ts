// floor-recommendations v1
// Deterministic math from Postgres + AI narrative layer.
// All numbers come from the RPC — the model only writes reasoning and actions.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Confidence gates — below these thresholds we do not make a recommendation.
const MIN_UNITS_SOLD = 2;        // need at least this many sales in a category
const MIN_GAP_PTS = 4;           // gap must exceed this to be actionable
const MIN_UNIT_DELTA = 1;        // must justify at least ~1 floor unit of change
const MIN_REVENUE = 500;         // ignore trivial revenue

type Rec = {
  id: string;
  type: string;
  scope: string;
  subject: string;
  severity: "critical" | "high" | "medium" | "low";
  headline: string;
  evidence: string[];
  metrics: Record<string, unknown>;
  confidence: "high" | "medium" | "low";
  suggested_action: string;
};

function fmtMoney(n: number) {
  return "$" + Math.round(n).toLocaleString("en-US");
}

function titleCase(s: string) {
  return (s || "").replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

// ── Build validated, deterministic recommendations ──
function buildRecommendations(data: any): Rec[] {
  const recs: Rec[] = [];
  const totalFloor = Number(data.total_floor_units || 0);
  const totalRev = Number(data.total_revenue || 0);
  if (totalFloor <= 0) return recs;

  // ── 1. CATEGORY UNDER-FLOORED (sales outpacing space) ──
  for (const c of (data.categories || [])) {
    const gap = Number(c.gap_pts || 0);
    const unitDelta = Number(c.unit_delta || 0);
    const unitsSold = Number(c.units_sold || 0);
    const rev = Number(c.sales_revenue || 0);

    if (gap >= MIN_GAP_PTS && unitDelta >= MIN_UNIT_DELTA && unitsSold >= MIN_UNITS_SOLD && rev >= MIN_REVENUE) {
      const conf = unitsSold >= 5 && gap >= 8 ? "high" : unitsSold >= 3 ? "medium" : "low";
      recs.push({
        id: `cat-under-${c.category}`,
        type: "expand_category",
        scope: "category",
        subject: titleCase(c.category),
        severity: gap >= 10 ? "high" : "medium",
        headline: `Increase ${titleCase(c.category)} floor presence`,
        evidence: [
          `${titleCase(c.category)} occupies ${c.floor_pct}% of floor but drives ${c.sales_pct}% of revenue`,
          `Gap of ${gap.toFixed(1)} percentage points in favour of sales`,
          `${fmtMoney(rev)} across ${unitsSold} unit${unitsSold !== 1 ? "s" : ""} sold`,
          c.revenue_per_unit ? `${fmtMoney(Number(c.revenue_per_unit))} revenue per floor unit` : "",
        ].filter(Boolean),
        metrics: {
          floor_pct: c.floor_pct, sales_pct: c.sales_pct, gap_pts: gap,
          current_units: c.floor_units, target_units: c.target_units, unit_delta: unitDelta,
          revenue: rev, units_sold: unitsSold,
        },
        confidence: conf,
        suggested_action: `Add roughly ${unitDelta.toFixed(1)} floor units of ${titleCase(c.category).toLowerCase()} (from ${c.floor_units} to about ${c.target_units}) to bring space in line with demand.`,
      });
    }

    // ── 2. CATEGORY OVER-FLOORED (space not earning) ──
    if (gap <= -MIN_GAP_PTS && unitDelta <= -MIN_UNIT_DELTA && Number(c.floor_units || 0) > 0) {
      const conf = Math.abs(gap) >= 8 ? "medium" : "low";
      recs.push({
        id: `cat-over-${c.category}`,
        type: "reduce_category",
        scope: "category",
        subject: titleCase(c.category),
        severity: Math.abs(gap) >= 10 ? "medium" : "low",
        headline: `${titleCase(c.category)} is over-floored relative to sales`,
        evidence: [
          `${c.floor_pct}% of floor generating only ${c.sales_pct}% of revenue`,
          `${Math.abs(gap).toFixed(1)} point gap against the category`,
          c.revenue_per_unit ? `Only ${fmtMoney(Number(c.revenue_per_unit))} per floor unit` : "",
        ].filter(Boolean),
        metrics: {
          floor_pct: c.floor_pct, sales_pct: c.sales_pct, gap_pts: gap,
          current_units: c.floor_units, target_units: c.target_units, unit_delta: unitDelta,
          revenue: rev, units_sold: unitsSold,
        },
        confidence: conf,
        suggested_action: `Consider reallocating about ${Math.abs(unitDelta).toFixed(1)} floor units from ${titleCase(c.category).toLowerCase()} to a higher-yielding category.`,
      });
    }
  }

  // ── 3. TOP SELLERS NOT ON FLOOR ──
  for (const p of (data.top_sellers_not_floored || [])) {
    const rev = Number(p.revenue || 0);
    const pct = Number(p.pct_of_total_rev || 0);
    if (rev < MIN_REVENUE) continue;
    const conf = pct >= 5 ? "high" : pct >= 2 ? "medium" : "low";
    recs.push({
      id: `sku-float-${p.model}`,
      type: "add_sku_to_floor",
      scope: "sku",
      subject: `${p.brand || ""} ${p.model}`.trim(),
      severity: pct >= 5 ? "high" : "medium",
      headline: `Floor the ${p.brand || ""} ${p.model} — selling without a display`.trim(),
      evidence: [
        `${fmtMoney(rev)} in revenue (${pct}% of total) with no showroom presence`,
        `${p.units_sold} unit${p.units_sold !== 1 ? "s" : ""} sold from catalogue or special order`,
        p.category ? `Category: ${titleCase(p.category)}` : "",
      ].filter(Boolean),
      metrics: { revenue: rev, units_sold: p.units_sold, pct_of_revenue: pct, model: p.model, brand: p.brand, category: p.category },
      confidence: conf,
      suggested_action: `Add ${p.model}${p.product_name ? ` (${p.product_name})` : ""} to the floor — it is already proving demand without a display to support it.`,
    });
  }

  // ── 4. DEAD SPACE (floored brands with zero sales) ──
  for (const b of (data.dead_space || [])) {
    const units = Number(b.floor_units || 0);
    if (units < 1) continue;
    recs.push({
      id: `dead-${b.brand}`,
      type: "dead_space",
      scope: "brand",
      subject: b.brand,
      severity: units >= 5 ? "high" : "medium",
      headline: `${b.brand} holds ${units.toFixed(1)} floor units with no recorded sales`,
      evidence: [
        `${b.floor_pct}% of total floor space`,
        `${b.sku_count} SKU${b.sku_count !== 1 ? "s" : ""} on display`,
        `Zero attributed revenue in the period`,
      ],
      metrics: { floor_units: units, floor_pct: b.floor_pct, sku_count: b.sku_count, revenue: 0 },
      confidence: "medium",
      suggested_action: `Verify sales attribution for ${b.brand}. If the revenue is genuinely absent, reallocate this space or refresh the assortment and rep training on this line.`,
    });
  }

  // ── 5. BRAND MISMATCH ──
  for (const b of (data.brands || [])) {
    const gap = Number(b.gap_pts || 0);
    const rev = Number(b.sales_revenue || 0);
    const floorPct = Number(b.floor_pct || 0);
    if (floorPct <= 0 || rev < MIN_REVENUE) continue;

    if (gap <= -MIN_GAP_PTS && floorPct >= 5) {
      recs.push({
        id: `brand-under-${b.brand}`,
        type: "brand_underperforming",
        scope: "brand",
        subject: b.brand,
        severity: Math.abs(gap) >= 12 ? "high" : "medium",
        headline: `${b.brand} is underperforming its floor allocation`,
        evidence: [
          `${b.floor_pct}% of floor returning ${b.sales_pct}% of revenue`,
          `${Math.abs(gap).toFixed(1)} point shortfall`,
          b.revenue_per_unit ? `${fmtMoney(Number(b.revenue_per_unit))} per floor unit` : "",
        ].filter(Boolean),
        metrics: { floor_pct: b.floor_pct, sales_pct: b.sales_pct, gap_pts: gap, revenue: rev, floor_units: b.floor_units },
        confidence: rev >= 2000 ? "medium" : "low",
        suggested_action: `Review ${b.brand} merchandising, pricing, and rep product knowledge before reducing space — the display may be underserved rather than the brand underperforming.`,
      });
    }

    if (gap >= MIN_GAP_PTS * 2 && floorPct > 0) {
      recs.push({
        id: `brand-over-${b.brand}`,
        type: "brand_overperforming",
        scope: "brand",
        subject: b.brand,
        severity: "medium",
        headline: `${b.brand} is outperforming its footprint`,
        evidence: [
          `${b.floor_pct}% of floor driving ${b.sales_pct}% of revenue`,
          `+${gap.toFixed(1)} points above allocation`,
          b.revenue_per_unit ? `${fmtMoney(Number(b.revenue_per_unit))} per floor unit` : "",
        ].filter(Boolean),
        metrics: { floor_pct: b.floor_pct, sales_pct: b.sales_pct, gap_pts: gap, revenue: rev, floor_units: b.floor_units },
        confidence: rev >= 5000 ? "high" : "medium",
        suggested_action: `Expanding ${b.brand} display space is likely to lift total revenue — it converts better per unit than the floor average.`,
      });
    }
  }

  // Rank: severity, then confidence, then revenue impact
  const sevRank: Record<string, number> = { critical: 0, high: 1, medium: 2, low: 3 };
  const confRank: Record<string, number> = { high: 0, medium: 1, low: 2 };
  recs.sort((a, b) => {
    const s = sevRank[a.severity] - sevRank[b.severity];
    if (s !== 0) return s;
    const c = confRank[a.confidence] - confRank[b.confidence];
    if (c !== 0) return c;
    return Number(b.metrics.revenue || 0) - Number(a.metrics.revenue || 0);
  });

  return recs;
}

export function createFloorHandler({ createClient, env, fetchImpl = fetch }: { createClient: any; env: (name: string) => string | undefined; fetchImpl?: typeof fetch }) {
return async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return json({ error: "Auth required" }, 401);

  let body: any;
  try { body = await req.json(); if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error("body"); } catch { return json({ error: "Invalid JSON" }, 400); }

  const orgId = body.organization_id;
  const storeId = body.store_id ?? null;
  const wantNarrative = body.narrative !== false;
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (typeof orgId !== "string" || !uuid.test(orgId) || (storeId !== null && (typeof storeId !== "string" || !uuid.test(storeId)))) return json({ error: "invalid_organization_or_store" }, 400);

  const sbUrl = env("SUPABASE_URL") ?? "";
  const anonKey = env("SUPABASE_ANON_KEY") ?? "";
  const admin = createClient(sbUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: auth } },
  });
  const { data: { user }, error: authError } = await admin.auth.getUser();
  if (authError || !user) return json({ error: "Auth required" }, 401);

  // 1. Pull deterministic data
  const { data: floorData, error: rpcErr } = await admin.rpc("tj_floor_recommendation_data", {
    p_org_id: orgId,
    p_store_id: storeId,
  });
  if (rpcErr) return json({ error: "floor_data_unavailable" }, rpcErr.code === "42501" ? 403 : 500);
  if (!floorData || Number(floorData.total_floor_units || 0) === 0) {
    return json({ recommendations: [], summary: null, data: floorData, note: "No floor data available" });
  }

  // 2. Build validated recommendations from hard math
  const recs = buildRecommendations(floorData);

  // 3. Optional AI narrative — reasoning only, never new numbers
  let summary: string | null = null;
  if (wantNarrative && recs.length > 0) {
    const anthropicKey = env("ANTHROPIC_API_KEY") ?? "";
    const openaiKey = env("OPENAI_API_KEY") ?? "";

    const prompt = `You are a retail floor-planning analyst for an appliance retailer.

Below are VALIDATED findings computed from the retailer's actual floor and sales data. Every number is already verified.

FINDINGS:
${JSON.stringify(recs.map((r) => ({
      headline: r.headline,
      evidence: r.evidence,
      action: r.suggested_action,
      confidence: r.confidence,
    })), null, 2)}

CONTEXT:
- Total floor units: ${floorData.total_floor_units}
- Total attributed revenue: ${fmtMoney(Number(floorData.total_revenue || 0))}
- Open floor holes: ${floorData.holes?.open_holes ?? 0}

Write a concise executive summary (3-5 sentences) for the store manager. Rules:
- Use ONLY the numbers given above. Never invent or estimate figures.
- Lead with the single highest-impact move.
- Be direct and practical, as a merchandising expert would speak to an operator.
- No preamble, no bullet points, no headings. Plain prose only.
- If confidence is low on a finding, say so plainly.`;

    try {
      const model = env("AI_MODEL_STANDARD") ?? env("AI_MODEL") ?? "";
      if (anthropicKey && model) {
        const r = await fetchImpl("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: { "Content-Type": "application/json", "x-api-key": anthropicKey, "anthropic-version": "2023-06-01" },
          body: JSON.stringify({
            model,
            max_tokens: 500,
            messages: [{ role: "user", content: prompt }],
          }),
        });
        const d = await r.json();
        if (r.ok) summary = d.content?.[0]?.text ?? null;
      }
      if (!summary && openaiKey && model && !anthropicKey) {
        const r = await fetchImpl("https://api.openai.com/v1/chat/completions", {
          method: "POST",
          headers: { "Content-Type": "application/json", "Authorization": `Bearer ${openaiKey}` },
          body: JSON.stringify({
            model,
            messages: [{ role: "user", content: prompt }],
            max_completion_tokens: 500,
          }),
        });
        const d = await r.json();
        if (r.ok) summary = d.choices?.[0]?.message?.content ?? null;
      }
    } catch (_e) {
      // Narrative is optional — recommendations stand on their own.
    }
  }

  return json({
    recommendations: recs,
    summary,
    totals: {
      total_floor_units: floorData.total_floor_units,
      total_revenue: floorData.total_revenue,
      open_holes: floorData.holes?.open_holes ?? 0,
    },
    categories: floorData.categories,
    brands: floorData.brands,
    generated_at: floorData.generated_at,
  });
};
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}