# Platform canonical infrastructure

## Source control and backend

| Resource | Canonical value | Ownership / deployment |
|---|---|---|
| GitHub repository | `https://github.com/tj8886/ApplianceIQ` | Source of truth |
| Production branch | `main` | GitHub Actions validates and deploys configured applications |
| Supabase project | ApplianceIQ (`fumwwhyozeouoqscolke`, ca-central-1) | Supabase database, Auth, Storage, and Edge Functions |

## Netlify applications

| Application | Canonical site | Site ID | Source | Workflow |
|---|---|---|---|---|
| Academy | `https://applianceiq-aiacademy.netlify.app` | `4179d04b-ca18-4551-9b18-fe434b83ebc6` | `apps/academy/` | `deploy-academy` in `.github/workflows/ci.yml` |
| CRM | `https://crmaiiq.netlify.app` | `38f8f64f-c674-4e14-8639-37ebb40ac939` | `apps/crm/` | `deploy-crm` in `.github/workflows/ci.yml` |
| Spec IQ | `https://appliance-spec-iq.netlify.app` | `7dd39e7d-8c68-4109-a803-f4d6e0aab6ff` | `apps/spec-iq/` | `deploy-speciq` in `.github/workflows/ci.yml` |

The Academy is a static site. Its repository configuration is `apps/academy/netlify.toml`, with `apps/academy/` as the deployment directory and `.` as the publish directory. It has no repository Netlify Functions directory, no build command, and no broad SPA catch-all redirect.

## Deprecated and prohibited infrastructure

`trainingiq-academy.netlify.app` (site ID `840dd2f5-21c6-410c-9491-e4887fa9be38`) is rogue/abandoned infrastructure. It must never be restored, linked, deployed to, or reused. Historical closeout documents may mention it solely as historical evidence and must label it as superseded.

## Deployment ownership

- GitHub Actions is the canonical deployment path when `NETLIFY_AUTH_TOKEN` is configured for the repository.
- Manual deployment is a fallback and must target only the site IDs in this document.
- Supabase migrations and Edge Functions are deployed through their separate documented workflows; they are not Netlify resources.

## Current known limitations

- The Academy frontend references `/.netlify/functions/ai-trainer` and `/.netlify/functions/tts`, but this repository has no corresponding Netlify Function source and the canonical Academy deployment has no Netlify Functions. These routes remain unavailable until separately approved work resolves them.
- The canonical Academy site's Netlify dashboard build-configuration and deploy-hook details require dashboard verification if they are needed; do not infer or recreate them from historical rogue-site settings.
