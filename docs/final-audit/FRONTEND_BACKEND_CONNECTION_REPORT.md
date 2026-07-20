# Frontend and Backend Connection Report

Date: 2026-07-19
Branch: `audit/final-migration-completeness`

## Frontend routing evidence

`apps/applianceiq/src/App.tsx` wires only:

- `/auth/login`
- `/auth/signup`
- `/auth/reset`
- `/auth/callback`
- `/auth/update-password`
- `/dashboard`
- `/products`
- `/products/:id`
- `/`
- `*`

The broader page surface exists in source under `apps/applianceiq/src/pages/*`, but the top-level router does not expose every page module directly. That means many capability modules are source-present but frontend-incomplete.

## Browser-to-backend evidence

- Browser auth client: `apps/applianceiq/src/lib/auth.ts`
- Supabase client: `apps/applianceiq/src/lib/supabase.ts`
- AI enrichment client: `apps/applianceiq/src/lib/aiEnrichment.ts`
- Platform config client: `apps/applianceiq/src/lib/platformConfig.ts`
- Outreach helper: `apps/applianceiq/src/lib/outreach.ts`
- Product/forecast/territory/graph intelligence libraries exist and are consumed by page modules

## Netlify / public delivery evidence

- `apps/applianceiq/netlify.toml` publishes `dist`.
- Live `https://applianceiq.ai/` returns HTTP 200.
- Live `https://applianceiq.ai/robots.txt` returns HTTP 200.
- Live `https://applianceiq.ai/sitemap.xml` returns HTTP 200.

## Backend function evidence

- Source exists for the shared communications/files/security functions, the billing webhook, the AI enrichment runner, and the API gateway.
- Direct target endpoint probes returned `404` or `401`, so runtime behavior could not be fully proven from this workspace.

## Connection gaps

- The runtime connection from frontend routes to many of the deeper page modules is a source-level connection, not a route-level one, in the current router.
- The live backend endpoints for several functions were not proven to match source by authenticated request.
