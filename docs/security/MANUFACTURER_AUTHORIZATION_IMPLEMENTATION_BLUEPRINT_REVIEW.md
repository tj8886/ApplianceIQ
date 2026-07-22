# Manufacturer Authorization Implementation Blueprint V1

## Outcome

This is a staging-first, nine-phase plan to remediate all seven approved manufacturer authorization findings before controller creation, ownership activation, or manufacturer onboarding. It contains no SQL or implementation instructions executable against production.

## Roadmap and dependency graph

`P1 membership/roles → P2 invitations → P3 helpers → P4 RLS → P5 Storage → P6 portal compatibility → P7 controllers → P8 ownership activation → P9 onboarding/monitoring`.

P8 cannot begin until P3–P7 are validated. P9 cannot begin until P8 is approved. Every phase has a rollback trigger, reversible steps, verification, recovery target, and data-safety rule in the JSON.

## Membership, roles, and compatibility

The future model adds controlled role, status, approval, invitation, expiry, brand/country/capability scope, and delegated-principal scope without deleting history. Legacy memberships are never auto-activated. The eight roles are vendor owner, vendor admin, brand admin, content editor, product editor, asset editor, training editor, and viewer. No implicit inheritance or platform-admin grant exists.

`manages_vendor()` is replaced through parallel decision telemetry, then policy-caller cutover. The compatibility window is read-oriented; it never preserves a permissive browser write path. Browser mutation of global roles, memberships, and invite acceptance is retired in P6.

## RLS and Storage

P4 replaces self-role, self-join, role-blind, invitation, and organization-only manufacturer-write policies in a staged preview. P5 makes `vendor-assets` private, binds paths to `vendor_id/asset_id/filename`, requires scoped authorization and signed URLs, and adds scan/quarantine, retryable deletion, and lifecycle monitoring. Public URLs receive an inventory and adapter window before any visibility change.

## Test and rollback plan

The matrix defines 34 scenarios spanning positive authorization, denials, escalation, cross-vendor/brand/region access, invitation abuse, Storage, audit, and portal regression. A rollback never deletes memberships or assets; it disables new grants, restores the prior approved release, and preserves evidence. RLS is never disabled as a rollback shortcut.

## Deployment gates

G1 approves controller creation only after membership, helper, RLS, Storage, and portal staging tests pass. G2 approves ownership activation only after brand/controller/region evidence, including Hotpoint and Insignia decisions. G3 approves onboarding only after pilot invitation, audit, support, and rollback-drill evidence passes.

## Exact next task

Create a human-reviewed, staging-only technical change specification for P1 and P2: controlled membership status/roles and authoritative invitation acceptance. It must include the detailed data-repair analysis and test fixtures required before any migration is drafted.
