# Phase 1 — Platform Stabilization

## Completed on branch `agent/platform-hardening`

- Added `config/app-registry.json` as the canonical application/deployment registry.
- Verified current Netlify IDs for Platform, CRM, Command Center, Intelligence Group, Product IQ, PIM Scraper, Spec IQ, IQ Academy, AI IQ Coach, IQ Up System and IQ Field.
- Corrected the Academy source mapping to `apps/iq-training`.
- Replaced hard-coded per-site CI deployment jobs with a registry-driven deployment matrix.
- Production deployment now fails if the Netlify deployment credential is missing instead of silently skipping.
- Each registry-driven deployment is followed by a production HTTP smoke test.
- Added registry integrity checks for duplicate app keys, duplicate Netlify site IDs, duplicate production URLs, missing source paths and malformed deployable entries.
- Replaced the stale README deployment map with the current platform/module architecture.

## Legacy / cleanup queue

### `applianceiq-product-pim`

Status: `retire-pending-verification`.

Canonical replacement: Product IQ (`applianceiq-product-iq-pim`).

The legacy Netlify project is still repo-linked and currently emits failing PR deploy-preview checks because its Netlify publish directory is misconfigured (`~/ApplianceIQ`). It is intentionally excluded from registry-driven deployment. The remaining Netlify-side cleanup is to disconnect/disable builds or retire/redirect the project after confirming no users depend on its URL.

### Field Report Analytics

The live Netlify site is verified and registered. Its canonical source directory in this repository has not yet been identified, so it remains `external-source-unmapped` and is excluded from registry-driven deployment until source ownership is resolved.

## Deployment ownership rule

GitHub Actions + `config/app-registry.json` is the desired production deployment control plane. Netlify projects that remain directly repo-linked should not independently deploy obsolete or duplicate applications.

## Phase 1 exit criteria

- Registry validation passes in GitHub Actions.
- Canonical registered apps deploy from the registry matrix on `main`.
- Production smoke tests pass for canonical apps.
- Legacy Product PIM repo-linked build is disabled/retired after dependency verification.
- Field Report Analytics source ownership is mapped or explicitly kept external with its own documented deployment process.
