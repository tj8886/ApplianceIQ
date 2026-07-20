# Final test report — 2026-07-19

## CI (automated, on push) — BLOCKED_EXTERNAL: runs hit startup_failure (account verification gate). The checks below were executed manually in the release environment instead:
- CRM inline-JS syntax check: PASS
- Academy corrupted-tag regression guard: PASS
- Migration timestamp ordering: PASS
(No unit-test framework exists for the single-file apps; CI checks above are the codified regression tests. Deploy jobs no-op until NETLIFY_AUTH_TOKEN is set — not counted as passed.)

## Live production smoke tests (executed this session)
| Test | Result |
|---|---|
| crmaiiq.netlify.app returns 200, contains recorder feature | PASS |
| trainingiq-academy.netlify.app 200, identical to canonical academy source, no corrupted tags | PASS |
| crmaiiq robots.txt = disallow all | PASS |
| academy robots.txt + sitemap.xml served | PASS |
| activity-analyzer unauthenticated POST -> 401 | PASS |
| deploy-host -> 410/401 (retired, JWT-gated) | PASS |
| match_products definition includes membership guard | PASS |
| schema_migrations = 16 rows matching repo | PASS |

## End-to-end recording pipeline
Verified live earlier in build (record -> consent -> upload -> transcribe -> coach -> complete with score). Re-running requires a mic session; retest steps are in the CRM section of README. Requires OPENAI_API_KEY + ANTHROPIC_API_KEY edge secrets.

## Log review
Edge-function logs reviewed after v2/v3 deploys: boot OK, no runtime errors.
