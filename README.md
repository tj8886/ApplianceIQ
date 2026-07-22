# ApplianceIQ

![CI & Deploy](https://github.com/tj8886/ApplianceIQ/actions/workflows/ci.yml/badge.svg)
![CRM](https://img.shields.io/website?url=https%3A%2F%2Fcrmaiiq.netlify.app&label=CRM)
![Academy](https://img.shields.io/website?url=https%3A%2F%2Ftrainingiq-academy.netlify.app&label=Academy)
| Spec IQ | https://appliance-spec-iq.netlify.app | `spec-iq` | `apps/spec-iq/` |
| IQ UP System | https://applianceiq-iq-up-system.netlify.app | `iq-up-system` | `apps/up-system/` |

The Appliance Sales Operating System — CRM, AI Academy, and governed AI layer for appliance and specialty retail.

## Live deployments

| App | URL | Netlify project | Source in this repo |
|---|---|---|---|
| CRMAI IQ (CRM) | https://crmaiiq.netlify.app | `crmaiiq` | `apps/crm/` |
| ApplianceIQ Academy | https://applianceiq-aiacademy.netlify.app | (separate Netlify account, same content) | `apps/academy/` |
| Academy (team mirror) | https://trainingiq-academy.netlify.app | `trainingiq-academy` | `apps/academy/` |
| Spec IQ | https://appliance-spec-iq.netlify.app | `spec-iq` | `apps/spec-iq/` |
| IQ UP System | https://applianceiq-iq-up-system.netlify.app | `iq-up-system` | `apps/up-system/` |

Backend: Supabase project **ApplianceIQ** (`fumwwhyozeouoqscolke`, ca-central-1).

## Repo layout

```
apps/
  crm/                      Single-file CRM app (index.html) + netlify.toml
  academy/                  Academy site (single source; deployed to both academy URLs)
supabase/
  migrations/               54 files aligned with production migration history
                            (23 contain DDL; 31 are historical markers — see docs/reconciliation/)
  functions/
    ai-request-processor/   Governed AI assistant endpoint (Anthropic)
    activity-analyzer/      Recording pipeline: process | transcribe | coach | summarize
    ai-roleplay/            AI roleplay sessions
    email-dispatcher/       Outbound email via Resend
    embedding-worker/       Knowledge/product embeddings (Voyage or OpenAI)
    stripe-webhooks/        Stripe payment webhook handler
    deploy-host/            RETIRED deploy helper
    _shared/                Shared modules (http, communications, file-governance, etc.)
    _non_deployable/        7 functions with missing schema deps (see README there)
```

## Architecture notes

- **CRM** is a single-file vanilla-JS SPA talking directly to Supabase (auth + RLS) with the publishable key. All org data is tenant-scoped through `organization_members` + `is_org_member()` / `is_org_admin()` RLS helpers.
- **Sales pitch recording**: browser MediaRecorder → private `crm-media` bucket (`{org_id}/recordings/{id}.webm`) → `sales_recordings` row (consent fields required) → `activities` row → `activity-analyzer` `process` mode runs Whisper transcription + Claude coaching. Status lifecycle: `uploaded → transcribing → transcribed → analyzing → complete | failed`. `recording_source` supports future `wearable`, `phone_system`, `uploaded_file`, `meeting_platform`.
- **AI governance**: every assistant call goes through `ai_submit_request` (SQL, as the user) before any model call; requests, audit events, and token usage land in `ai_requests`, `ai_audit_events`, `ai_usage_meter`.
- **Secrets** live only in Supabase Edge Function secrets: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY` (transcription), optional `VOYAGE_API_KEY`, `AI_MODEL`, `EMBEDDING_MODEL`. Nothing sensitive ships to the frontend; the Supabase publishable key in the apps is public by design.

## Docs

- [DEPLOYMENT.md](DEPLOYMENT.md) — how each piece ships, CI setup, rollback
- [CONTRIBUTING.md](CONTRIBUTING.md) — ground rules and conventions
- [.env.example](.env.example) — reference for server-side secrets

## Deploying

- **CRM to Netlify**: from `apps/crm/`, deploy to site id `38f8f64f-c674-4e14-8639-37ebb40ac939` (`crmaiiq`). The site is currently deployed manually (no CI); linking this repo to the Netlify project enables auto-deploys from `main`.
- **Edge functions**: `supabase functions deploy <name> --project-ref fumwwhyozeouoqscolke` (or via MCP/dashboard).
- **Migrations**: 54 files match 54 production migration records. 23 contain DDL; 31 are historical markers (no executable SQL). See `docs/reconciliation/` for details. New migrations should be added with a fresh timestamp and applied via `supabase db push` or the dashboard/MCP.
