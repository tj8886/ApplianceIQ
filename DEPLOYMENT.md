# Deployment

## Overview

| Component | Where | How it deploys |
|---|---|---|
| CRM (`apps/crm`) | Netlify site `crmaiiq` (`38f8f64f-c674-4e14-8639-37ebb40ac939`) | GitHub Actions on push to `main` (or manual) |
| Academy (`apps/academy`) | Netlify site `trainingiq-academy` (`840dd2f5-21c6-410c-9491-e4887fa9be38`) | GitHub Actions on push to `main` (or manual) |
| Academy mirror | `applianceiq-aiacademy.netlify.app` | Lives in a **separate Netlify account** — must be updated from that account with the same `apps/academy` content |
| Edge functions (`supabase/functions/*`) | Supabase project `fumwwhyozeouoqscolke` | Supabase CLI / dashboard / MCP (manual) |
| Migrations (`supabase/migrations/*`) | Same Supabase project | Already applied in prod; new ones via `supabase db push` |

## One-time setup for auto-deploy

The GitHub Actions workflow needs one repository secret:

1. Create a Netlify personal access token: Netlify dashboard → **User settings → Applications → Personal access tokens → New access token**.
2. In GitHub: repo → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `NETLIFY_AUTH_TOKEN`
   - Value: the Netlify token
3. Push to `main` — the `Deploy CRM` and `Deploy Academy` jobs go live. Until the secret exists, those jobs no-op with a warning and only validation runs.

## Manual deploys

```bash
# CRM
npx netlify-cli deploy --prod --dir apps/crm --site 38f8f64f-c674-4e14-8639-37ebb40ac939

# Academy
npx netlify-cli deploy --prod --dir apps/academy --site 840dd2f5-21c6-410c-9491-e4887fa9be38

# Edge function
supabase functions deploy activity-analyzer --project-ref fumwwhyozeouoqscolke
```

## Supabase edge secrets (never in the repo)

Set in Supabase dashboard → Edge Functions → Secrets:

| Secret | Used by | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | ai-request-processor, activity-analyzer | Claude model calls |
| `OPENAI_API_KEY` | activity-analyzer, embedding-worker | Whisper transcription / fallback embeddings |
| `VOYAGE_API_KEY` (optional) | embedding-worker | Preferred embedding provider |
| `AI_MODEL` (optional) | both AI functions | Defaults to `claude-sonnet-4-6` |
| `EMBEDDING_MODEL` (optional) | embedding-worker | Defaults per provider |

## Rollback

Netlify keeps every deploy. Dashboard → site → Deploys → pick a previous deploy → **Publish deploy**. For the database, migrations are forward-only; write a new corrective migration rather than editing an applied one.
