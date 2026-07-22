# Staging execution runbook

1. Obtain human change approval.
2. Confirm the global-role manual review is resolved and recorded.
3. Confirm the target environment identity is staging, never production.
4. Confirm the repository is clean and at the approved commit.
5. Confirm no active manufacturer onboarding or pending invitation process is running.
6. Capture a schema snapshot.
7. Capture row-count and integrity snapshots.
8. Capture constraint and index snapshots.
9. Capture RLS and policy snapshots.
10. Capture migration history.
11. Run `pre_migration_verification.sql`.
12. Stop if the precheck is false or any blocker is present.
13. Apply only the timestamped forward migration through the approved staging migration runner.
14. Run `post_migration_verification.sql`.
15. Compare post-state with every captured snapshot.
16. Confirm rows remain 0/0/1/19, policies/RLS remain unchanged, and exactly four indexes exist.
17. Observe database and API logs for 30 minutes.
18. Record all results and observed errors.
19. Decide to approve the next phase, rollback, or forward-fix.
20. Retain evidence with the staging change record.

This document is a runbook, not execution authorization.
