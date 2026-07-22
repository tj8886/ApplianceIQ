# Migration 001 rollback runbook

Decision owner: database change owner with security approval. Roll back immediately only before any application, server flow, or later migration writes the new fields.

1. Pause dependent releases and confirm no writer uses the new columns.
2. Preserve pre/post verification output and logs.
3. Run `rollback.sql` manually in staging only; it removes the four indexes before the added columns.
4. Re-run the pre-migration verification report and reconcile migration history according to the approved staging process.
5. Record the incident, lock cause, and remediation.

Once data exists in lifecycle, provenance, metadata, token, or vendor-binding fields—or a later migration depends on them—do not run destructive rollback. Preserve evidence and use a forward fix.
