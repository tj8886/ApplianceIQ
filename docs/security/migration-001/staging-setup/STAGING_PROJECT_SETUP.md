# ApplianceIQ Staging setup

## Purpose and identity

`ApplianceIQ Staging` is the isolated non-production project for controlled migration validation. Its reference is `okdtorbgerhukzalaxqq` and its host is `db.okdtorbgerhukzalaxqq.supabase.co`; both differ from production (`fumwwhyozeouoqscolke` and `db.fumwwhyozeouoqscolke.supabase.co`). The project is `ACTIVE_HEALTHY` in `ca-central-1`.

## Isolation and access

This task used the Supabase connector with an explicit staging project reference for a SELECT-only health/schema query. No CLI link was changed and no local environment file was created. Future commands must explicitly identify `okdtorbgerhukzalaxqq`; never rely on a default target. Credentials are project-scoped and must be retrieved/configured later through an approved secret mechanism, outside Git.

Tracked `.env` patterns are ignored. Public client configuration references exist in application HTML; no server credential value was documented here. Production Netlify variables, project configuration, schema, data, and DNS were untouched.

## Current state and blockers

The staging database is empty: zero public tables and no migration-history relation. Repository migration history contains unavailable historical markers, so bootstrap is blocked pending an approved baseline/replay strategy. Migration 001 has not run and is not authorized by this document.
