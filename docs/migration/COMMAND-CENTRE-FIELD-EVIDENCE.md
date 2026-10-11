# Field IQ in the US Command Centre

Field visits, findings, actions and completed checklist scores now feed the existing Command Centre evidence refresh. Source changes enqueue the old/new affected organizations; the existing private bounded worker and five-minute native cron remain the only refresh mechanism. Source records and historical snapshots are retained.

The executive screen displays received visit totals, inspection dates, unresolved critical findings, open/overdue actions and the latest completed checklist score per client/store. Field IQ's `endWalk` records scores as percentages (passed applicable checklist items / applicable items × 100), so values are used directly on a 0–100 scale. No 0–10 heuristic rescaling or missing-value score is introduced. Historical score dates are visible; this is not a current-month average or a claim of a fresh inspection.

Resolution is the observed resolved/closed status ratio among known non-rejected actions. A resolved status does not establish verified evidence. Unknown-status actions are counted separately. Composite health and confidence remain unassessed.

Organization ownership comes from the field client. Findings additionally require matching visit, client and store; actions require matching finding, visit, client and store; scores require a matching completed visit. Inconsistent cross-client source links are excluded from publication, not deleted or repaired implicitly. The executive endpoints retain their existing active native identity and organization administrator authorization.

Current risks and the top ten recorded open actions are read from the latest snapshot's field evidence. Priority is a deterministic severity/priority ordering, with due date as a tie breaker. This does not create duplicate insight rows, contact owners, change action statuses or create tasks on their behalf. Source titles/descriptions are escaped by the existing executive card renderer.

Validation: the field rollback test verifies source relationships, cross-organization denial, latest-per-store selection (a recorded score of 5 stays 5), visits/due dates, actual executive endpoints, field correction enqueue, resolution propagation with history retained, source client transfer enqueue and private helper permissions. Existing current-month/POS/Academy/failed-worker and Command Centre/management regressions are retained. Frontend rendering verifies visit counts, unscaled scores, inspection dates and the distinction between recorded resolution and verification. Authenticated browser verification remains outstanding.

Run results and production source dates are recorded in `command-centre-field-verification.json`. This supersedes the previous live-evidence document's field-execution gap; coaching and assignment-based training completion remain outside this change.
