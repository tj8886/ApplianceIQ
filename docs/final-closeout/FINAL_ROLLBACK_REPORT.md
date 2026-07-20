# Rollback readiness — 2026-07-19

| Layer | Rollback path |
|---|---|
| Netlify sites | Dashboard -> Deploys -> select previous -> Publish deploy (previous known-good: CRM 6a5cc54c..., Academy 6a5d1a12...) |
| Edge functions | Dashboard -> Edge Functions -> function -> restore prior version (activity-analyzer v2, ai-request-processor v1, deploy-host v5, embedding-worker v1) |
| Database | Forward-only migrations; corrective migration pattern. closeout migrations are additive/guarding — reverting match_products guard is a one-line CREATE OR REPLACE (not recommended). Supabase PITR available on the project. |
| Repo | git revert on main; release merge commit recorded in FINAL_DEPLOYMENT_REPORT |
