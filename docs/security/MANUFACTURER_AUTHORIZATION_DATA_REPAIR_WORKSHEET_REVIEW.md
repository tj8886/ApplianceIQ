# Manufacturer Authorization Data Repair Worksheet V1

## Executive summary

Migration 001 is an additive staging schema preparation only. It does not repair authorization, change data, or alter behavior. The current verified data makes this low-risk: zero memberships, zero invitations, 19 vendors, no orphan/duplicate memberships, and one enabled global-role record requiring manual platform review.

## Repair analysis

`mfr_members`, `mfr_invites`, and `mfr_vendors` are `NO_ACTION`. The global-role row is `MANUAL_REVIEW`: preserve it as the platform administration record unless an authorized reviewer says otherwise. No automatic conversion, quarantine, or ownership assignment is justified from the current data.

## Migration 001 scope and deferred work

Migration 001 adds nullable lifecycle/provenance columns, invitation-security columns, metadata defaults, and non-disruptive indexes only. It does not update data, tighten constraints, enforce roles/status, change RLS/helpers/Storage, create vendor entities, or activate brand ownership. Controlled constraints, trusted invitation flow, browser-write cutoff, and enforcement are deferred to later P1/P2 units.

## Compatibility and validation

Legacy reads remain compatible. The additive fields are ignored by old clients; privileged browser writes are not removed until P2-C, but are never expanded by this migration. Repeat the worksheet immediately before staging, verify schema/defaults/indexes after, and smoke-test legacy reads. No authorization claim may rely on Migration 001 alone.

## Risks and readiness

Readiness is **READY WITH CONDITIONS**: repeat the data snapshot, manually confirm the existing platform admin, review locking/index plans, and approve rollback. The migration is additive and expected to have low schema/data/performance risk, but it is not security remediation until later authoritative flows and RLS enforcement are deployed.

## Exact next task

Human-review this worksheet, then prepare the staging-only Migration 001 change request with exact database conventions, lock plan, rollback runbook, and verification checklist—still without authoring executable SQL until explicitly approved.
