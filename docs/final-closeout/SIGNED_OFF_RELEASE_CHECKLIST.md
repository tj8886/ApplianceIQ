# Signed-off release checklist — ApplianceIQ closeout

Verified by: Claude (Lead Release Engineer session) · Date: 2026-07-19 · Evidence keys: G=GitHub path, DB=live query/advisor, F=deployed function version, L=live URL test, M=migration

Statuses: VERIFIED_COMPLETE (VC) · INTENTIONALLY_EXCLUDED (IE) · BLOCKED_EXTERNAL (BE)

| Item | Status | Evidence / Reason |
|---|---|---|
| GitHub source of truth | VC | Full source, 16 migrations, 4 fn sources, CI, docs in tj8886/ApplianceIQ@main |
| AGENTS.md | VC | G: AGENTS.md |
| Migration log | VC | G: docs/migration-log.md; DB: 16/16 versions match schema_migrations |
| CI | BE | Workflow committed, YAML-valid; GitHub Actions runs end in startup_failure (no jobs start), consistent with new-account verification gate. Not load-bearing: release deployed manually + verified live |
| Netlify CRM deployment | VC | L: crmaiiq.netlify.app 200; deploy 6a5d6afe...; content = apps/crm |
| Netlify Academy deployment | VC | L: trainingiq-academy.netlify.app 200; deploy 6a5d6b21...; content = apps/academy |
| Academy mirror deployment | BE | applianceiq-aiacademy.netlify.app lives in a separate Netlify account; content currently identical except robots/sitemap; redeploy requires that account |
| Supabase migration alignment | VC | M: 16 applied = 16 in repo; no drift (schema built solely via migrations) |
| Authentication (signup/login/logout/session) | VC | Supabase Auth email+password; exercised live via CRM; L: auth endpoints active |
| Organizations / roles / permissions | VC | DB: organization_members + is_org_member/is_org_admin RLS across all org tables |
| CRM companies/contacts/deals/tasks/products | VC | G: apps/crm; DB: tables + org RLS; L: live app CRUD |
| Activities | VC | DB: activities table + RLS; written by recording flow |
| Notes | IE | No standalone notes feature approved/built; deal/task text fields cover current need; no dependency |
| Email dispatch + CRM association | VC(dispatch) / IE(intake) | F: email-dispatcher v1 (Resend, membership-checked, queued->sent/failed, activity+audit logged); L: compose UI on deal/contact modals; BE until RESEND_API_KEY secret set. Inbound intake webhook remains excluded (needs inbound domain) |
| File upload (specs/warranty/presentations) | IE | crm_presentations + mfr_assets schema present; general file-upload UI not approved/built; recordings are the only live upload path |
| File scanning | IE | No scanner integration approved; uploads restricted to authenticated org members, private bucket, size-capped |
| Signed URLs | VC | Recordings playback uses createSignedUrl(300s); L: verified in app |
| Storage deletion / retention | IE | No retention policy approved yet; deletion available via dashboard/service role; documented as future work |
| Sales pitch recordings | VC | Full chain: consent modal -> MediaRecorder -> crm-media -> sales_recordings -> activity -> process pipeline; L: live |
| Call recordings / roleplays | IE | recording_source supports phone_system/wearable/meeting_platform (schema-ready); capture integrations not approved/built |
| Transcription | VC | F: activity-analyzer v3 (Whisper); requires OPENAI_API_KEY secret (see env row) |
| Coaching + seven-step scoring | VC | F: activity-analyzer v3 coach mode; kpi_scores 7 steps + overall; stored in ai_coaching_reviews |
| KPI events / trends | VC | M: 20260720003822 kpi_events + auto-capture triggers + backfill; L: Dashboard view live (latest score, 30d avg, trend, 7-step averages); history append-only |
| Notifications (push) | IE | Not approved/built; no dependency |
| Turnstile | IE | Not approved/built; Supabase Auth handles abuse basics |
| Stripe / billing | IE | Not approved/built; no billing UI or entitlement dependency exists |
| AI request processing + governance | VC | F: ai-request-processor v2; ai_submit_request (membership-checked) -> model -> audit + usage meter |
| AI assistants / prompt templates / knowledge / embeddings | VC | DB: seeded tables; F: embedding-worker v1 (service-role only); match_products fixed |
| Usage metering + audit events | VC | DB: ai_usage_meter + ai_audit_events written by both AI functions |
| Model routing (light/standard/heavy) | VC | F: both AI functions tiered; env overrides documented |
| Activity analyzer | VC | F: v3 deployed; source in repo matches |
| deploy-host disposition | VC | Retired: v6 = JWT-gated 410 stub; rollback = restore v5; G: source updated |
| Sitemap / robots.txt | VC | L: crmaiiq/robots.txt disallows all (private app); academy robots.txt + sitemap.xml live |
| Security advisors | VC | Run 2026-07-19; 1 real defect (match_products) FIXED; remaining findings documented as intentional/accepted in FINAL_SECURITY_REPORT |
| Performance advisors | VC | Run 2026-07-19; duplicate index dropped, hot-path indexes added; low-impact items documented deferred |
| Leaked-password protection | BE | Dashboard-only toggle; enable at Auth -> Providers -> Password security (1 click) |
| Tenant isolation | VC | RLS org-scoped everywhere client-accessible; storage path-scoped by org UUID; match_products defect fixed; deny-by-default on service-only tables |
| Rollback readiness | VC | Netlify publish-previous-deploy; edge fn version restore; forward-only migrations; documented in FINAL_ROLLBACK_REPORT |
| Production smoke tests | VC | See FINAL_TEST_REPORT (sites 200, functions 401 unauth, robots live) |
| Production logs | VC | Edge-function logs reviewed post-deploy; no errors (FINAL_TEST_REPORT) |
| Production commit traceability | VC | Netlify deploys 6a5d6afe/6a5d6b21 built from release commit content; release merge commit recorded in FINAL_DEPLOYMENT_REPORT |
| CI auto-deploy secret (NETLIFY_AUTH_TOKEN) | BE | Requires user-created Netlify PAT added as GitHub Actions secret; until then CI validates and deploy jobs no-op with warning |
