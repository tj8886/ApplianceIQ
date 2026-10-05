// deploy-host — RETIRED 2026-07-19 (closeout).
// This function served HTML bundles from the app_bundles table for one-time Netlify
// imports during initial site creation. Deploys now run from GitHub (tj8886/ApplianceIQ)
// via CI or the Netlify CLI. No active dependency calls this endpoint.
// Rollback: restore version 5 of this function from the Supabase dashboard.
Deno.serve(() =>
  new Response(
    JSON.stringify({ error: "gone", detail: "deploy-host is retired. Deploys run from github.com/tj8886/ApplianceIQ." }),
    { status: 410, headers: { "Content-Type": "application/json" } },
  ));
