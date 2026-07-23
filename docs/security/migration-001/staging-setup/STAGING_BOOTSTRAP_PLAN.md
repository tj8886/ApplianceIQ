# Staging bootstrap plan

## Phase 1 — isolate and inspect

Verify the explicit staging target, production exclusion, and empty-project state.

## Phase 2 — obtain approved baseline strategy

Resolve the incomplete historical migration record. Approve either a reproducible baseline schema artifact with incremental migrations or another documented non-production bootstrap method. Do not replay the current history blindly.

## Phase 3 — bootstrap after separate authorization

Execute only the approved pre-Migration-001 baseline/bootstrap. Stop before `20260722194405_manufacturer_authorization_migration_001.sql`.

## Phase 4 — synthetic test baseline

Verify schema and row counts, then load only approved synthetic seed data. Capture before snapshots and resume Priority 2D-6 execution authorization.

## Phase 5 — Migration 001

Execute Migration 001 only after a separate, controlled authorization. This plan does not authorize it.
