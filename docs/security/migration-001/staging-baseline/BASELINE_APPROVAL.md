# Baseline approval record

| Field | Value |
| --- | --- |
| Approving person | Terry James Robar |
| Reviewer role | Project Owner |
| Approval date | 2026-07-22 |
| Reviewed commit | `77582c7913f3f247b45477d3b98465a5dbb4e829` |
| Approval decision | `APPROVED_WITH_CONDITIONS` |
| Approved strategy | `SCHEMA_ONLY_BASELINE_FROM_PRODUCTION` |
| Approved alignment model | `BASELINE_CUTOFF_MODEL` |
| Approved generation method | schema-only `pg_dump` or Supabase-equivalent extraction |
| Approved production target | `fumwwhyozeouoqscolke` |
| Approved staging target | `okdtorbgerhukzalaxqq` |
| Evidence reference | Priority 2D-6A-3A explicit human approval |

## Approved scope

Candidate generation may use explicit read-only production targeting and must store a reviewable schema-only candidate outside `supabase/migrations`. It may include approved application-owned structural objects only. It must exclude production row data; Auth users and identities; Storage objects and files; secrets, Vault values, API keys, tokens, passwords, and credential-bearing connection strings; production integrations; environment-specific URLs; scheduled jobs; webhooks; operational monitoring data; manually recreated Supabase-managed schemas; copied production migration history; and Manufacturer Authorization Migration 001.

## Conditions of approval

1. Candidate SQL remains outside `supabase/migrations`.
2. Candidate contains no row data, secrets, or copied migration history.
3. Migration 001 remains excluded.
4. All 34 security-definer functions receive manual review.
5. All RLS policies receive manual staging-portability review.
6. Functions, policies, triggers, and dependencies involving Auth, Storage, Realtime, Vault, extensions, production-specific identifiers or URLs, and elevated privileges receive manual review.
7. Supabase-managed schemas are not manually recreated.
8. Production-specific objects are excluded or made portable through review.
9. Candidate SQL receives PostgreSQL parser validation, secret scanning, statement-inventory review, and manual review.
10. A separate human approval is required before any candidate is applied to the empty staging project.

## Authorization boundary

This approval authorizes candidate generation and review only. It does not authorize applying SQL to staging or production, executing Migration 001 or historical migrations, deploying application code, copying production data, changing Netlify or production environment variables, or enabling production integrations in staging. Production mutation is prohibited; staging application is not yet authorized.

Allowed decisions: `APPROVED`, `APPROVED_WITH_CONDITIONS`, `REJECTED`, `BLOCKED_PENDING_EVIDENCE`.
