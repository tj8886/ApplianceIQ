# AGENTS.md — rules for AI agents working on ApplianceIQ

## Identity
- GitHub `tj8886/ApplianceIQ` is the source of truth. Supabase project: `fumwwhyozeouoqscolke` (ApplianceIQ, ca-central-1). Canonical Netlify sites: `crmaiiq` (38f8f64f-c674-4e14-8639-37ebb40ac939) and `applianceiq-aiacademy` (4179d04b-ca18-4551-9b18-fe434b83ebc6). `trainingiq-academy` (840dd2f5-21c6-410c-9491-e4887fa9be38) is abandoned infrastructure: never deploy to, restore, or reuse it.

## Hard rules
1. Never commit secrets. The Supabase publishable key in the apps is public by design; everything else lives in Supabase edge secrets or GitHub Actions secrets.
2. Database changes go through `supabase/migrations/` with a fresh timestamp AND get applied to prod. Never edit an applied migration; write a corrective one.
3. Edge function changes must land in both places: this repo and the deployed function. Update the repo first.
4. Every table carries `organization_id` with RLS via `is_org_member()` / `is_org_admin()`. Any SECURITY DEFINER function that accepts an org id MUST verify caller membership (see the match_products fix in `20260719232101`).
5. Recordings are never processed without `consent_confirmed = true`.
6. AI model routing is tiered (light/standard/heavy). Don't hardcode model names in new code; use the tier env vars.
7. Deploys: prefer CI (push to main). Manual fallback commands are in DEPLOYMENT.md.
8. After DDL changes, run the Supabase security + performance advisors and fix or document findings.

## Brand voice for AI features
Verified over hyped. Evidence before claims. Never invent specs, prices, or stock. ACRA objection handling. Advisory-only; human approval where flagged.
