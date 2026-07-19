# Contributing

## Ground rules

- `main` is production. Every push to `main` deploys the apps (once `NETLIFY_AUTH_TOKEN` is configured). Work in branches and PR into `main`.
- The apps are intentionally single-file, dependency-free HTML/JS. Keep it that way unless a build step is genuinely needed.
- Never commit secrets. The Supabase publishable key in the apps is public by design; everything else lives in Supabase Edge Function secrets or GitHub Actions secrets.
- Database changes go through `supabase/migrations/` with a fresh `YYYYMMDDHHMMSS_name.sql` timestamp. Never edit an applied migration.
- Edge function changes: update the source here AND deploy to Supabase — the repo is the source of truth, but deploys are manual.

## Conventions

- Multi-tenant safety first: every table carries `organization_id` with RLS via `is_org_member()` / `is_org_admin()`.
- Recordings: consent fields are mandatory; never process a recording without `consent_confirmed = true`.
- Brand voice in AI prompts: "verified over hyped" — evidence before claims.

## Local preview

The apps are static files — open `apps/crm/index.html` via any static server (`npx serve apps/crm`). Auth and data hit the live Supabase project, so use a test account.
