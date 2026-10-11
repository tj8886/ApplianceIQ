// image-audit: fetches candidate product images server-side, computes pixel metrics,
// writes rows to image_audit_results. Verdicts are derived in SQL (image_audit_classified).
// Invoked with {batch, chain}. Responds 202 immediately; work runs in background
// (EdgeRuntime.waitUntil); bounded runs log actual result persistence and completion.
import { createClient } from "npm:@supabase/supabase-js@2.117.2";
import { requireJobAuth } from "../_shared/requireJobAuth.ts";
import { beginInvocation, finishInvocation, type Invocation } from "../_shared/edgeInvocationLog.ts";
import { Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";

const sb = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36";
const WALL_BUDGET_MS = 70_000;
const MAX_PRODUCTS = 4;

function downscaleUrl(url: string): string {
  try {
    const u = new URL(url);
    const h = u.hostname;
    // Whirlpool-family Scene7 servers accept resize params
    if (/(whirlpool|maytag|kitchenaid|amana)\.com$/.test(h.replace(/^www\./, "")) || h.includes("is/image")) {
      u.searchParams.set("wid", "420");
      u.searchParams.set("fmt", "jpg");
      return u.toString();
    }
    // BigCommerce stencil size segment
    if (h === "cdn11.bigcommerce.com") {
      return url.replace(/\/stencil\/\d+x\d+\//, "/stencil/320x320/");
    }
    return url;
  } catch {
    return url;
  }
}

async function fetchBytes(url: string, deadline = Date.now() + WALL_BUDGET_MS): Promise<{ status: number; ct: string | null; buf: Uint8Array | null }> {
  const resp = await fetch(url, {
    // Prefer JPEG/PNG: some CDNs (gstatic) content-negotiate to WebP, which we cannot decode
    headers: { "User-Agent": UA, "Accept": "image/jpeg,image/png;q=0.9,image/*;q=0.5,*/*;q=0.1" },
    signal: AbortSignal.timeout(Math.max(1, Math.min(8_000, deadline - Date.now() - 3_000))),
    redirect: "follow",
  });
  if (!resp.ok) {
    await resp.body?.cancel();
    return { status: resp.status, ct: resp.headers.get("content-type"), buf: null };
  }
  const ab = await resp.arrayBuffer();
  if (ab.byteLength > 15_000_000) return { status: resp.status, ct: resp.headers.get("content-type"), buf: null };
  return { status: resp.status, ct: resp.headers.get("content-type"), buf: new Uint8Array(ab) };
}

function metricsFrom(img: Image) {
  const W = img.width, H = img.height;
  const bm = img.bitmap; // RGBA
  let white = 0, mid = 0, total = 0;
  let bWhite = 0, bTotal = 0;
  let sumRg = 0, sumYb = 0, sumRg2 = 0, sumYb2 = 0;
  const mx = Math.max(2, Math.round(W * 0.06));
  const my = Math.max(2, Math.round(H * 0.06));
  // Sample at most 128 x 128 pixels without allocating another resized bitmap.
  const stepX = Math.max(1, Math.ceil(W / 128));
  const stepY = Math.max(1, Math.ceil(H / 128));
  for (let y = 0; y < H; y += stepY) {
    for (let x = 0; x < W; x += stepX) {
      const i = (y * W + x) * 4;
      const r = bm[i], g = bm[i + 1], b = bm[i + 2];
      const lum = 0.299 * r + 0.587 * g + 0.114 * b;
      total++;
      if (r > 235 && g > 235 && b > 235) white++;
      if (lum > 40 && lum < 215) mid++;
      const rg = r - g, yb = (r + g) / 2 - b;
      sumRg += rg; sumYb += yb; sumRg2 += rg * rg; sumYb2 += yb * yb;
      if (x < mx || x >= W - mx || y < my || y >= H - my) {
        bTotal++;
        if (r > 230 && g > 230 && b > 230) bWhite++;
      }
    }
  }
  const mRg = sumRg / total, mYb = sumYb / total;
  const vRg = sumRg2 / total - mRg * mRg, vYb = sumYb2 / total - mYb * mYb;
  const colorfulness = Math.sqrt(Math.max(vRg, 0) + Math.max(vYb, 0)) + 0.3 * Math.sqrt(mRg * mRg + mYb * mYb);
  return {
    white_frac: +(white / total).toFixed(4),
    midtone_frac: +(mid / total).toFixed(4),
    border_white_frac: +(bWhite / bTotal).toFixed(4),
    colorfulness: +colorfulness.toFixed(2),
  };
}

function tryDecode(buf: Uint8Array): Promise<Image | null> {
  return Image.decode(buf)
    .then((d) => (d instanceof Image ? d : (d as unknown as { frames: Image[] }).frames?.[0] ?? null))
    .catch(() => null);
}

async function auditUrl(productId: string, url: string, kind: string, galleryIndex: number | null, deadline: number) {
  if (Date.now() >= deadline - 3_000) throw new Error("audit_budget_exhausted");
  const row: Record<string, unknown> = {
    product_id: productId, url, kind, gallery_index: galleryIndex,
    fetch_status: null, content_type: null, bytes: null, width: null, height: null,
    border_white_frac: null, white_frac: null, midtone_frac: null, colorfulness: null,
    decode_ok: false, error: null, audited_at: new Date().toISOString(),
  };
  try {
    const small = downscaleUrl(url);
    let res = await fetchBytes(small, deadline);
    if ((res.status !== 200 || !res.buf) && small !== url) res = await fetchBytes(url, deadline);
    row.fetch_status = res.status;
    row.content_type = res.ct;

    let img: Image | null = null;
    if (res.buf) {
      row.bytes = res.buf.byteLength;
      img = await tryDecode(res.buf);
    }
    // Fallback: WebP/AVIF or blocked CDN -> re-encode to JPEG via images.weserv.nl
    if (!img) {
      try {
        const prox = `https://images.weserv.nl/?url=${encodeURIComponent(url)}&output=jpg&w=420&fit=inside`;
        const pres = await fetchBytes(prox, deadline);
        if (pres.status === 200 && pres.buf) {
          img = await tryDecode(pres.buf);
          if (img) {
            row.fetch_status = 200;
            row.content_type = (res.ct ?? "") + " -> jpeg(weserv)";
            row.bytes = pres.buf.byteLength;
            row.error = null;
          }
        }
      } catch { /* keep original failure info */ }
    }
    if (img) {
      row.width = img.width;
      row.height = img.height;
      Object.assign(row, metricsFrom(img));
      row.decode_ok = true;
    } else if (res.buf && !row.error) {
      row.error = "decode: unsupported image type (weserv fallback failed too)";
    }
  } catch (e) {
    row.error = `fetch: ${String(e).slice(0, 180)}`;
  }
  const { error } = await sb.from("image_audit_results").upsert(row, { onConflict: "product_id,url" });
  if (error) throw new Error("audit_result_write_failed");
  return row.decode_ok === true;
}

async function auditProduct(p: { id: string; image_url: string | null; gallery_urls: string[] | null }, deadline: number) {
  const seen = new Set<string>();
  const urls: {url:string;kind:string;index:number|null}[] = [];
  if (p.image_url) { seen.add(p.image_url); urls.push({url:p.image_url,kind:"primary",index:null}); }
  (p.gallery_urls ?? []).slice(0, 8).forEach((url, index) => {
    if (url && !seen.has(url)) { seen.add(url); urls.push({url,kind:"gallery",index}); }
  });
  let valid = 0;
  // Sequential decoding bounds memory; all selected URLs must persist before done.
  for (const item of urls) {
    if (await auditUrl(p.id,item.url,item.kind,item.index,deadline)) valid++;
  }
  return { images:urls.length, valid, invalid:urls.length-valid };
}

async function finishClaim(id: string, claimedAt: string, status: string, errorCode: string | null) {
  const {data,error} = await sb.from("image_audit_queue").update({
    status,finished_at:new Date().toISOString(),last_error:errorCode,
  }).eq("product_id",id).eq("status","processing").eq("claimed_at",claimedAt).select("product_id");
  if (error || !data || data.length !== 1) throw new Error("audit_queue_write_failed");
}

async function run(batch: number, chain: number, invocation: Invocation) {
  const deadline = Date.now() + WALL_BUDGET_MS;
  const stats = { products:0, images:0, valid:0, invalid:0, errors:0, chained:0 };
  let code: string | null = null;
  try {
    for (let n=0; n<batch && Date.now()<deadline-15_000; n++) {
      // Never strand a batch of claimed products when this invocation stops.
      const {data:ids,error} = await sb.rpc("claim_image_audit_batch",{n:1});
      if (error) throw new Error("audit_claim_failed");
      if (!ids?.length) break;
      const id = ids[0];
      const {data:claims,error:ce} = await sb.from("image_audit_queue")
        .select("product_id,claimed_at").eq("product_id",id).eq("status","processing");
      if (ce || !claims || claims.length!==1) throw new Error("audit_claim_read_failed");
      const claimedAt = claims[0].claimed_at;
      try {
        const {data:prods,error:pe} = await sb.from("products")
          .select("id,image_url,gallery_urls").in("id",[id]);
        if (pe || !prods || prods.length!==1) throw new Error("audit_product_read_failed");
        const result = await auditProduct(prods[0],deadline);
        await finishClaim(id,claimedAt,"done",null);
        stats.products++; stats.images+=result.images; stats.valid+=result.valid; stats.invalid+=result.invalid;
      } catch (e) {
        const raw = e instanceof Error ? e.message : "audit_product_failed";
        code = /^audit_[a-z_]+$/.test(raw) ? raw : "audit_product_failed";
        stats.errors++;
        await finishClaim(id,claimedAt,"error",code);
        break;
      }
    }
    if (chain>0 && stats.errors===0) {
      // Chain only a bounded request; completed means actual audit persistence.
      const {count,error} = await sb.from("image_audit_queue")
        .select("product_id",{count:"exact",head:true}).eq("status","pending").lt("attempts",3);
      if (error) throw new Error("audit_pending_read_failed");
      if ((count ?? 0)>0) {
        const {error:ke} = await sb.rpc("kick_image_audit",{p_chain:chain-1,p_batch:batch,p_starters:1});
        if (ke) throw new Error("audit_dispatch_failed");
        stats.chained=1;
      }
    }
  } catch (e) {
    const raw = e instanceof Error ? e.message : "audit_run_failed";
    code = /^audit_[a-z_]+$/.test(raw) ? raw : "audit_run_failed";
    if (stats.errors===0) stats.errors++;
  } finally {
    await finishInvocation(sb,invocation,stats.errors ? "failed" : "completed",{...stats,error_code:code});
  }
}

Deno.serve(async (req) => {
  const gate = await requireJobAuth(req, { fn: "image-audit" });
  if (gate instanceof Response) return gate;
  let batch = 1, chain = 0;
  try {
    const body = await req.json();
    if (Number.isFinite(body.batch)) batch = Math.min(Math.max(1, Math.floor(body.batch)), MAX_PRODUCTS);
    if (Number.isFinite(body.chain)) chain = Math.min(Math.max(0, Math.floor(body.chain)), 20);
  } catch { /* defaults */ }
  // @ts-ignore EdgeRuntime is provided by the Supabase edge runtime
  EdgeRuntime.waitUntil(run(batch, chain, beginInvocation(req,"image-audit",sb)));
  return new Response(JSON.stringify({ accepted: true, batch, chain }), {
    status: 202,
    headers: { "Content-Type": "application/json" },
  });
});
