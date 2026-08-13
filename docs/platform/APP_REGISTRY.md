# ApplianceIQ Application Registry

`config/app-registry.json` is the source of truth for ApplianceIQ web applications and Netlify deployment targets.

## Rules

1. Every production ApplianceIQ web app must have exactly one registry entry.
2. A Netlify site ID and production URL may belong to only one registry entry.
3. `deploy_on_main: true` means GitHub Actions owns production deployment for that app.
4. Deployable apps must have a repository `source_path` and a canonical Netlify `site_id`.
5. The Platform entry is the ApplianceIQ shell/control plane. Other sites are modules, not competing platform shells.
6. Internal tools remain registered, but use an internal category/status.
7. Legacy deployments are never silently reused. They stay in `legacy` until verified and retired/redirected.
8. Sites whose source is not mapped into this repository use `external-source-unmapped` and are excluded from automated deployment until ownership is resolved.
9. Repo-linked Netlify auto-builds are not a substitute for registry ownership. Duplicate or legacy repo-linked projects should be retired/disconnected after dependency verification.

## Current platform model

- **Platform shell:** ApplianceIQ Platform
- **Experience apps:** CRM, Spec IQ, IQ Academy, AI IQ Coach, IQ Up System, IQ Field
- **Intelligence apps:** Command Center, IQ Intelligence Group, Field Report Analytics
- **Core data:** Product IQ
- **Internal acquisition:** PIM Scraper

## Known cleanup items

### Legacy Product PIM

Netlify project `applianceiq-product-pim` is marked `retire-pending-verification`. Its canonical replacement is Product IQ (`applianceiq-product-iq-pim`). Do not add it to CI or use it as a new production target.

The legacy Netlify project remains repo-linked and currently emits a failing deploy preview because its Netlify publish directory is configured as `~/ApplianceIQ`. This is a Netlify project-configuration issue, not a Product IQ application failure.

### Field Report Analytics

The live Netlify project is registered, but a canonical source directory has not yet been mapped in `tj8886/ApplianceIQ`. It is intentionally excluded from registry-driven deployment until its source is identified or migrated into this repository.

## CI contract

`.github/workflows/ci.yml` reads the registry and builds the main-branch deployment matrix dynamically. Each registered deployable app is:

1. validated,
2. deployed to its registered Netlify site,
3. smoke-tested at its registered production URL.

Do not hardcode a new Netlify site ID directly into CI. Add or update the registry instead.

## Adding an app

Before setting `deploy_on_main: true`, confirm:

- source directory exists,
- `index.html` or the app's production entrypoint exists,
- Netlify project/site ID is verified,
- production URL is verified,
- ownership/category is clear,
- the site is not a duplicate or legacy deployment.

Then run:

```bash
node scripts/validate-app-registry.mjs
```

The same validation runs in CI.
