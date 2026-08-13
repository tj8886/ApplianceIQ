# ApplianceIQ Deployment

## Source of truth

Production web deployment ownership is defined in [`config/app-registry.json`](config/app-registry.json).

Do not copy Netlify site IDs into new scripts or documentation. The registry owns:

- app key and display name,
- source path,
- Netlify site/project identity,
- production URL,
- lifecycle status,
- whether GitHub Actions deploys the app on `main`.

Validate it with:

```bash
node scripts/validate-app-registry.mjs
```

## GitHub Actions

`.github/workflows/ci.yml` performs platform validation on pull requests and pushes to `main`.

Validation includes:

- canonical app-registry integrity,
- CRM and Spec IQ inline JavaScript syntax checks,
- Academy HTML regression checks,
- migration ordering/version/filename checks,
- deployable Edge Function completeness checks.

On `main`, CI builds a deployment matrix from the registry. Each entry with `deploy_on_main: true` is deployed to the registered Netlify site and then smoke-tested against its registered production URL.

`NETLIFY_AUTH_TOKEN` is required for production deployment. A missing credential fails the production deploy job; it is not silently skipped.

## Current deployment model

The ApplianceIQ Platform site is the shell/control plane. CRM, Command Center, IQ Intelligence Group, Product IQ, PIM Scraper, Spec IQ, IQ Academy, AI IQ Coach, IQ Up System and IQ Field are registered modules with verified Netlify targets.

Field Report Analytics is registered as `external-source-unmapped` until its canonical source ownership is resolved, so GitHub Actions does not deploy it.

The old `applianceiq-product-pim` Netlify project is legacy and is not a valid production target. Product IQ (`applianceiq-product-iq-pim`) is its canonical replacement.

## Netlify repo-linked builds

Some Netlify projects are still independently linked to this GitHub repository and may create deploy previews in addition to the registry-driven GitHub Actions flow.

Legacy or duplicate repo-linked projects should be disconnected/retired after dependency verification. In particular, the legacy Product PIM currently fails deploy previews because its Netlify publish directory is configured as `~/ApplianceIQ`, which does not exist in the Netlify build environment.

The desired end state is:

**GitHub + app registry → validation → canonical Netlify target → smoke test**

rather than multiple Netlify projects independently deciding how the same commit should be built.

## Supabase

Backend project: `fumwwhyozeouoqscolke` (`ca-central-1`).

Database changes must be represented by versioned files under `supabase/migrations/`. Edge Function source must live under `supabase/functions/`.

Connector/platform production changes should be mirrored into source control before being considered complete.

## Rollback

For a web-app regression, use the Netlify project deploy history to restore the previous successful production deploy, then revert/fix the corresponding Git commit so the registry-driven pipeline and production state converge again.

For database changes, prefer forward corrective migrations. Do not manually edit migration history to make an incident disappear.
