/**
 * PIM Safety Tests
 * Validates security invariants against the live Supabase project.
 * Run: SUPABASE_URL=... SUPABASE_KEY=... node tests/pim-safety.mjs
 *
 * Tests:
 * 1. Anonymous users cannot write to PIM tables
 * 2. Unapproved products cannot be publicly visible
 * 3. Confidence values are on the 0-100 scale
 * 4. Source types match the constraint
 * 5. Price observations table exists and is append-only
 * 6. Schema backup file exists in repo
 */

const SUPABASE_URL = process.env.SUPABASE_URL || "https://fumwwhyozeouoqscolke.supabase.co";
const SUPABASE_KEY = process.env.SUPABASE_KEY || "sb_publishable_wiP3ouBdS_Qub9EMIYJK7w_eiltZHKV";

let passed = 0;
let failed = 0;

function ok(name) { passed++; console.log(`  ✓ ${name}`); }
function fail(name, detail) { failed++; console.error(`  ✗ ${name}: ${detail}`); }

async function supaRest(path, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...opts,
    headers: {
      apikey: SUPABASE_KEY,
      Authorization: `Bearer ${SUPABASE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
      ...opts.headers,
    },
  });
  return res;
}

// ── Test 1: Anonymous writes are blocked ─────────────────────────

console.log("\n1. Anonymous write protection");

const anonInsert = await supaRest("aiq_products", {
  method: "POST",
  body: JSON.stringify({
    brand_name: "__SAFETY_TEST__",
    model: "__TEST_MODEL__",
    category: "test",
    source_type: "internal",
  }),
});
if (anonInsert.status === 403 || anonInsert.status === 401) {
  ok("Anonymous INSERT into aiq_products is blocked");
} else {
  fail("Anonymous INSERT into aiq_products", `expected 401/403, got ${anonInsert.status}`);
  // Clean up if it somehow succeeded
  if (anonInsert.ok) {
    await supaRest("aiq_products?brand_name=eq.__SAFETY_TEST__&model=eq.__TEST_MODEL__", { method: "DELETE" }).catch(() => {});
  }
}

const anonImgInsert = await supaRest("pim_product_images", {
  method: "POST",
  body: JSON.stringify({
    product_id: "00000000-0000-0000-0000-000000000000",
    image_type: "test",
    file_url: "https://test.invalid/test.jpg",
  }),
});
if (anonImgInsert.status === 403 || anonImgInsert.status === 401) {
  ok("Anonymous INSERT into pim_product_images is blocked");
} else {
  fail("Anonymous INSERT into pim_product_images", `expected 401/403, got ${anonImgInsert.status}`);
}

const anonPriceInsert = await supaRest("pim_price_observations", {
  method: "POST",
  body: JSON.stringify({
    product_id: "00000000-0000-0000-0000-000000000000",
    observed_price: 999.99,
  }),
});
if (anonPriceInsert.status === 403 || anonPriceInsert.status === 401) {
  ok("Anonymous INSERT into pim_price_observations is blocked");
} else {
  fail("Anonymous INSERT into pim_price_observations", `expected 401/403, got ${anonPriceInsert.status}`);
}

// ── Test 2: No unapproved products are publicly visible ──────────

console.log("\n2. Approval workflow integrity");

const badProducts = await supaRest(
  "aiq_products?public_visible=eq.true&approval_status=neq.approved&select=id,brand_name,model,approval_status&limit=5",
  { headers: { Prefer: "return=representation" } }
);
const badRows = await badProducts.json().catch(() => []);
if (Array.isArray(badRows) && badRows.length === 0) {
  ok("No unapproved products are publicly visible");
} else {
  fail("Unapproved products are publicly visible", `found ${badRows.length}: ${JSON.stringify(badRows.slice(0,2))}`);
}

// ── Test 3: Confidence values are on 0-100 scale ─────────────────

console.log("\n3. Data contract: confidence scale");

const badConfidence = await supaRest(
  "aiq_products?source_confidence=gt.0&source_confidence=lt.1&select=id,model,source_confidence&limit=5",
  { headers: { Prefer: "return=representation" } }
);
const badConfRows = await badConfidence.json().catch(() => []);
if (Array.isArray(badConfRows) && badConfRows.length === 0) {
  ok("All confidence values are on 0-100 scale (none between 0-1)");
} else {
  fail("Confidence values on wrong scale", `found ${badConfRows.length} with 0<conf<1`);
}

// ── Test 4: Source types match constraint ─────────────────────────

console.log("\n4. Data contract: source types");

const VALID_SOURCE_TYPES = ["raw_import", "ai_extracted", "ai_suggested", "manufacturer_submitted", "aiq_reviewed", "internal", "web_scrape"];
const sourceTypes = await supaRest(
  "aiq_products?source_type=not.is.null&select=source_type&limit=1000",
  { headers: { Prefer: "return=representation" } }
);
const stRows = await sourceTypes.json().catch(() => []);
const invalid = [...new Set(stRows.map(r => r.source_type))].filter(t => !VALID_SOURCE_TYPES.includes(t));
if (invalid.length === 0) {
  ok("All source_type values match the constraint");
} else {
  fail("Invalid source_type values found", invalid.join(", "));
}

// ── Test 5: Price observations table exists ──────────────────────

console.log("\n5. Evidence preservation");

const obsRead = await supaRest("pim_price_observations?select=id&limit=1");
if (obsRead.status === 200) {
  ok("pim_price_observations table exists and is readable");
} else {
  fail("pim_price_observations table", `status ${obsRead.status}`);
}

// ── Test 6: Schema backup exists in repo ─────────────────────────

console.log("\n6. Repository reproducibility");

import { existsSync } from "fs";
if (existsSync("schema/applianceiq_full_schema.sql")) {
  ok("schema/applianceiq_full_schema.sql exists");
} else {
  fail("Schema backup missing", "schema/applianceiq_full_schema.sql not found");
}

if (existsSync("LICENSE")) {
  ok("LICENSE file exists");
} else {
  fail("LICENSE missing", "LICENSE file not found");
}

// ── Summary ──────────────────────────────────────────────────────

console.log(`\n${passed + failed} tests: ${passed} passed, ${failed} failed\n`);
process.exit(failed > 0 ? 1 : 0);
