# Open blockers (external) — 2026-07-19

1. **Leaked-password protection** — Supabase dashboard toggle only (Auth -> Password security). One click by account owner.
2. **NETLIFY_AUTH_TOKEN GitHub secret** — needed for CI auto-deploy. Owner creates a Netlify PAT and adds it at repo Settings -> Secrets -> Actions. Until then deploys are manual (documented) and CI validates only.
3. **applianceiq-aiacademy mirror** — separate Netlify account; needs a redeploy of apps/academy from that account to pick up robots.txt/sitemap (content otherwise identical).

4. **GitHub Actions startup_failure** — workflow is valid but runs never start ("startup_failure", no jobs). Typical cause: new GitHub account pending verification. Owner action: add/verify billing at github.com -> Settings -> Billing, then push any commit to re-trigger.

No internal blockers. No tenant-isolation failures outstanding (one found, fixed, verified).
