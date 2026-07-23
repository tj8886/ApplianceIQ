# Staging environment-variable strategy

| Variable family | Scope | Classification | Expected staging source | Tracking rule |
| --- | --- | --- | --- | --- |
| `SUPABASE_URL`, `SUPABASE_PROJECT_REF` | client/configuration | non-secret identifier | approved staging secret/config provider | never hard-code a production value for staging commands |
| `SUPABASE_ANON_KEY`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`, `VITE_SUPABASE_ANON_KEY` | client | publishable but environment-specific | approved staging configuration | do not document values in Git |
| `SUPABASE_SERVICE_ROLE_KEY` | server only | secret | approved staging secret provider | never commit or expose |
| `DATABASE_URL`, `DIRECT_URL`, `POSTGRES_URL` | server/database tooling | secret | approved staging secret provider | never commit or expose |
| `NEXT_PUBLIC_SUPABASE_URL`, `VITE_SUPABASE_URL` | client build | non-secret identifier | staging build context only | deployment configuration change requires separate approval |
| `NETLIFY`, `CONTEXT`, `NODE_ENV` | deployment/runtime | environment control | deployment platform | production values remain unchanged |

`.env` and `.env.*` are Git-ignored. No local environment file was needed for this task. If later required, use an ignored `.env.staging.local` containing staging-only values; never stage or print it.

## Existing reference locations

Client-side Supabase URL/key references currently appear in `apps/academy/index.html`, `apps/command-center/index.html`, `apps/crm/index.html`, and `apps/up-system/index.html`. Server-side environment-variable references appear in deployed and `_non_deployable` Supabase function sources. These are existing platform configuration patterns; they were not changed. Staging commands must use the explicit staging project reference and must not inherit these production-oriented client references.

No tracked server secret literal was identified by the staging-documentation secret scan. Existing publishable client keys are not treated as server secrets, but remain environment-specific and must not be copied into staging documentation.
