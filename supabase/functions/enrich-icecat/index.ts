import { createClient } from "npm:@supabase/supabase-js@2"
import { requireJobAuth } from "../_shared/requireJobAuth.ts"
import { beginInvocation, finishInvocation, type Invocation } from "../_shared/edgeInvocationLog.ts"

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
)

async function fetchIcecat(username: string, brand: string, productCode: string) {
  const url = `https://live.icecat.biz/api?shopname=${encodeURIComponent(username)}&lang=en&Brand=${encodeURIComponent(brand)}&ProductCode=${encodeURIComponent(productCode)}`
  const res = await fetch(url, { headers: { "User-Agent": "ApplianceIQ/1.0" } })
  const text = await res.text()
  let data: Record<string, unknown> | null = null
  try { data = JSON.parse(text) } catch { /* non-JSON */ }

  if (res.status === 404) return { status: "not_found" as const, reason: `HTTP 404: ${text.slice(0,200)}` }
  if (!res.ok) return { status: "error" as const, reason: `HTTP ${res.status}: ${text.slice(0,200)}` }
  if (!data) return { status: "error" as const, reason: `non-JSON: ${text.slice(0,200)}` }
  if (data.statusCode === 404) return { status: "not_found" as const, reason: String(data.message ?? "statusCode 404").slice(0,200) }
  if (!data.data) return { status: "error" as const, reason: String(data.msg ?? data.message ?? "no data field").slice(0,200) }
  return { status: "ok" as const, data: data.data as Record<string, unknown>, reason: "" }
}

function extractSpecs(d: Record<string, unknown>): Record<string, Record<string, string>> {
  const groups = (d.FeaturesGroups ?? []) as Record<string, unknown>[]
  const specs: Record<string, Record<string, string>> = {}
  for (const g of groups) {
    const groupName = ((g.FeatureGroup as Record<string, Record<string,string>>)?.Name?.Value ?? "General") as string
    const feats = (g.Features ?? []) as Record<string, unknown>[]
    for (const f of feats) {
      const name = ((f.Feature as Record<string, Record<string,string>>)?.Name?.Value ?? "") as string
      const value = (f.PresentationValue ?? f.RawValue ?? "") as string
      if (!name || !value) continue
      specs[groupName] ??= {}
      specs[groupName][name] = String(value).slice(0, 300)
    }
  }
  return specs
}

function extractPdf(d: Record<string, unknown>): string | null {
  const media = (d.Multimedia ?? []) as Record<string, unknown>[]
  const byType = media.find(m => /leaflet|data\s*sheet|specification/i.test(String(m.Type ?? "")) && String(m.URL ?? "").length > 0)
  if (byType?.URL) return String(byType.URL)
  const anyPdf = media.find(m => String(m.URL ?? "").toLowerCase().endsWith(".pdf") || /pdf/i.test(String(m.ContentType ?? "")))
  return anyPdf?.URL ? String(anyPdf.URL) : null
}

async function enrichProduct(p: { id: string; brand_name: string; model_number: string }, username: string) {
  const result = await fetchIcecat(username, p.brand_name, p.model_number)

  if (result.status !== "ok") {
    await supabase.from("products").update({ icecat_status: result.status, icecat_enriched_at: new Date().toISOString() }).eq("id", p.id)
    return { model: p.model_number, brand: p.brand_name, status: result.status, reason: result.reason }
  }

  const d = result.data
  const general = (d.GeneralInfo ?? {}) as Record<string, unknown>
  const image = (d.Image ?? {}) as Record<string, unknown>
  const gallery = ((d.Gallery ?? []) as Record<string, unknown>[]).map(g => String(g.Pic ?? "")).filter(Boolean).slice(0, 8)
  const specs = extractSpecs(d)
  const pdf = extractPdf(d)
  const title = ((general.Title ?? general.ProductName) ?? "") as string

  const update: Record<string, unknown> = {
    icecat_status: "enriched",
    icecat_enriched_at: new Date().toISOString(),
    icecat_id: String(general.IcecatId ?? "") || null,
  }
  if (Object.keys(specs).length > 0) update.specs = specs
  if (image.HighPic) update.image_url = String(image.HighPic)
  else if (image.LowPic) update.image_url = String(image.LowPic)
  if (gallery.length > 0) update.gallery_urls = gallery
  if (pdf) update.spec_sheet_url = pdf
  if (title && title.length > 10) update.product_name = title.slice(0, 300)

  const { error } = await supabase.from("products").update(update).eq("id", p.id)
  if (error) return { model: p.model_number, status: "db_error", reason: error.message }

  return { model: p.model_number, status: "enriched", got_image: !!update.image_url, got_specs: Object.keys(specs).length, got_pdf: !!pdf }
}

// FU-6: lifted into a named handler so the authenticated Deno.serve wrapper can
// record a confirmed-failure row when it throws. Success rows are written at
// each completion point inside.
const handler = async (req: Request, inv: Invocation): Promise<Response> => {
  const body = await req.json().catch(() => ({}))
  const username = Deno.env.get("ICECAT_USERNAME") ?? ""
  if (body.status_only === true) {
    await finishInvocation(supabase, inv, "completed", { readiness_only: true, configured: !!username })
    return Response.json({ configured: !!username, pim_first: true })
  }
  if (!username) {
    await finishInvocation(supabase, inv, "failed", { error: "ICECAT_USERNAME not configured" })
    return Response.json({ error: "ICECAT_USERNAME not configured" }, { status: 503 })
  }

  // Targeted mode: enrich one specific product (re-attempts regardless of status)
  if (body.product_id) {
    const { data: p } = await supabase.from("products").select("id, brand_name, model_number").eq("id", body.product_id).single()
    if (!p) return new Response(JSON.stringify({ error: "product not found" }), { status: 404 })
    const result = await enrichProduct(p, username)
    return new Response(JSON.stringify(result, null, 2), { headers: { "Content-Type": "application/json" } })
  }

  const batchSize = Math.min(body.batch_size ?? 25, 50)
  const { data: pending } = await supabase
    .from("products")
    .select("id, brand_name, model_number")
    .eq("status", "active")
    .or("icecat_enriched_at.is.null,icecat_enriched_at.lt." + new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
    .order("icecat_enriched_at", { ascending: true, nullsFirst: true })
    .limit(batchSize)

  if (!pending || pending.length === 0) {
    // Completed with nothing to do. "Ran and found no work" and "never ran" are
    // different facts and only this row can tell them apart.
    await finishInvocation(supabase, inv, "completed", { processed: 0, enriched: 0, reason: "no_pending" })
    return new Response(JSON.stringify({ enriched: 0, message: "No products pending enrichment" }), { headers: { "Content-Type": "application/json" } })
  }

  const results = []
  for (const p of pending) {
    try { results.push(await enrichProduct(p, username)) }
    catch (e) { results.push({ model: p.model_number, status: "error", reason: String(e).slice(0, 200) }) }
    await new Promise(r => setTimeout(r, 400))
  }

  const enriched = results.filter(r => r.status === "enriched").length
  const notFound = results.filter(r => r.status === "not_found").length
  console.log(`[enrich-icecat] ${enriched} enriched, ${notFound} not found, of ${results.length}`)
  await finishInvocation(supabase, inv, "completed", { processed: results.length, enriched, not_found: notFound })
  return new Response(JSON.stringify({ processed: results.length, enriched, not_found: notFound, results }, null, 2), { headers: { "Content-Type": "application/json" } })
}

Deno.serve(async (req: Request) => {
  const gate = await requireJobAuth(req, { fn: "enrich-icecat" })
  if (gate instanceof Response) return gate
  const inv = beginInvocation(req, "enrich-icecat", supabase)
  try {
    return await handler(req, inv)
  } catch (e) {
    // Confirmed failure, written before the re-raise so a throwing handler
    // leaves a record rather than an ambiguous absence.
    await finishInvocation(supabase, inv, "failed", { error: String(e).slice(0, 500) })
    throw e
  }
})
