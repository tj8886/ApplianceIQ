# Command Centre live evidence

The US Command Centre previously queried June 2026 regardless of the date. Its executive screen ignored `overall_health_score`, substituted 50 for missing scores, and could show today's timestamp without a source snapshot. The replacement defaults to the Toronto reporting month, supports historical months and displays the actual snapshot generation date separately from received source dates.

## Publication and refresh

CRM, UP visits/interactions, POS receipts, organization-owned PIM products and Academy quiz/progress changes enqueue affected organizations. The private native worker runs every five minutes, processes at most ten organizations per dispatch (hard maximum twenty), locks queue rows and serializes each organization's rebuild. It also renews activated organizations' snapshots daily. Failures retain the queued receipt, record only the SQLSTATE and defer retry for ten minutes. A successful dispatch is not evidence of successful processing: inspect `processed`, `failed`, queue errors and source dates.

The executive summary uses distinct source visits for month-to-date conversion and observed quiz percentages for Academy knowledge. Pipeline counts are explicitly current/all-recorded-outcome scopes. CRM currency is absent, so CAD pipeline totals are withheld. Composite health/confidence remain unassessed until their required evidence is validated. Missing score data displays — instead of a fabricated 50 or a failing grade.

Monthly UP and explicit-CAD POS metrics are produced only from recorded current-month rows. Budget targets, other producers' rows and historical snapshots are retained. Managed rows whose source evidence no longer supports publication are retained with subtype `command_centre_withheld`; application reads and the guarded IQ score helper exclude these rows. Corrected evidence can restore publication without duplicating rows or losing targets. POS amounts/margins require complete explicit currency/amount evidence; no conversion rate is inferred.

The former browser AI writer is replaced by navigation to the existing Predictions workflow. Opening Predictions does not claim an AI/provider job completed. Previously stored predictions and source records are retained.

## Validation

`test-command-centre-live-refresh.sql` uses an isolated organization and rolls back all fixtures. It verifies month boundaries, duplicate-interaction counting, Academy quiz scores, missing health/currency, target/producer preservation, currency correction and restoration, authenticated application wrappers, unmapped-user denial, source enqueue, a failed bounded job and successful retry, private helper permissions and native cron configuration. The deliberate failure constraint exists only inside the rolled-back test transaction.

`test-us-command-centre.mjs` verifies module syntax, historical month control, removed raw browser prediction writes/model routing, missing-score rendering and actual source-date/confidence display. The eleven-app bundle routing regression verifies the US endpoint and ticket-only shared auth handoff.

## Remaining verification

Received source dates may still be old even after successful recalculation. This work does not manufacture fresh CRM/UP/POS receipts, certify manufacturer/Icecat/DataForSEO provider completion, or certify all PIM publications. The executive PIM source indicator covers organization-owned catalog rows; shared-catalog ingestion/publication requires its existing dedicated freshness audit. Field execution/coaching and complete assignment-based Academy completion are explicitly missing from the composite score. The authenticated browser walkthrough remains a separate verification step.

Production run evidence and advisor findings are recorded in `command-centre-live-verification.json` after application and publication.
