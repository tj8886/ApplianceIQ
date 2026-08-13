# ApplianceIQ

![CI & Deploy](https://github.com/tj8886/ApplianceIQ/actions/workflows/ci.yml/badge.svg)

ApplianceIQ is an operating system for appliance and specialty retail. The product is organized as one platform shell with modular applications for CRM, sales operations, product intelligence, training/coaching, field operations, integrations and executive intelligence.

Backend: Supabase project **ApplianceIQ** (`fumwwhyozeouoqscolke`, `ca-central-1`).

## Canonical application registry

The source of truth for application ownership, source paths, Netlify project IDs, production URLs, lifecycle status and deployment eligibility is:

- [`config/app-registry.json`](config/app-registry.json)
- [`docs/platform/APP_REGISTRY.md`](docs/platform/APP_REGISTRY.md)

Do not add production site IDs directly to CI. Register the app once and let the deployment workflow consume the registry.

## Product architecture

### Platform

- **ApplianceIQ Platform** — shell/control plane for authentication, organizations, users, roles, entitlements, apps, integrations, notifications, settings and platform health.

### Experience

- **CRM** — customer, pipeline, activity and post-sale lifecycle.
- **Spec IQ** — product search, specifications, comparison and customer-facing product workflows.
- **IQ Academy** — training and curriculum.
- **AI IQ Coach** — performance coaching and roleplay.
- **IQ Up System** — retail traffic and salesperson opportunity assignment.
- **IQ Field** — field execution and data collection.

### Intelligence

- **Command Center** — operational action layer.
- **IQ Intelligence Group** — executive/business intelligence.
- **Field Report Analytics** — field analytics; live Netlify site exists, source ownership is still being mapped into this repository.

### Core data and acquisition

- **Product IQ** — canonical product/PIM application.
- **PIM Scraper** — internal product-data acquisition service/UI.

### Integration platform

The Supabase connector layer supports Shopify, Microsoft Dynamics 365 / Business Central, STORIS, ePASS, Oracle Xstore, RETAILvantage and Windward System Five, with shared ingestion, identity mapping, reconciliation, retry, quarantine, health, alerts, reliability and certification infrastructure.

## Repository layout

```text
apps/                       Application modules
config/app-registry.json    Canonical production application registry
scripts/                    Validation and operational tooling
supabase/migrations/        Versioned database changes
supabase/functions/         Edge Functions and connector workers
docs/platform/              Platform architecture and operational docs
tests/                      Automated tests
```

## CI and deployment

`.github/workflows/ci.yml` validates the application registry, application regressions, migration hygiene and deployable Edge Functions.

On `main`, CI builds a deployment matrix from `config/app-registry.json`. Every entry with `deploy_on_main: true` is deployed to its registered Netlify site and then smoke-tested at its registered production URL.

A missing `NETLIFY_AUTH_TOKEN` is a production deployment failure rather than a silent skip.

Run registry validation locally with:

```bash
node scripts/validate-app-registry.mjs
```

## Legacy deployments

Legacy and duplicate sites are listed under the `legacy` section of the registry instead of being silently reused. The old `applianceiq-product-pim` deployment is currently marked `retire-pending-verification`; its canonical replacement is Product IQ.

## Security and connector operations

The connector platform includes service-only credential storage, canonical ingestion, idempotency, quarantine, record and whole-job retry, reconciliation, event ordering protection, schema drift detection, health monitoring, incident alerting, SLA/reliability metrics and connector certification.

Platform connector certification is blocked when the internal platform security gate fails.

## Development rules

- Treat ApplianceIQ Platform as the shell. Other sites are modules.
- Prefer shared Supabase identity and event models over app-specific copies.
- Add new production apps to the registry before adding deployment logic.
- Do not expose service-role secrets to browser code.
- Keep schema changes in migrations and Edge Function source in GitHub.
- Use legacy status/redirects rather than allowing duplicate production products to drift indefinitely.

See [DEPLOYMENT.md](DEPLOYMENT.md), [CONTRIBUTING.md](CONTRIBUTING.md) and the [App Registry contract](docs/platform/APP_REGISTRY.md) for operational details.
