# Manufacturer Authorization P1–P2 Technical Specification

## Executive summary

This staging-only specification turns P1 and P2 into an implementation-ready contract. Current production has zero manufacturer memberships and zero invitations; its one global-role row has administrator, manufacturer, and retailer flags enabled and requires manual platform review. The existing keys/FKs prevent orphan membership rows, but do not provide lifecycle or authorization safety.

## P1: memberships and global roles

Use eight controlled membership roles and six statuses: pending, active, suspended, revoked, expired, and rejected. Only active, approved, nonexpired records will later authorize access. Keep one current membership per user/vendor, retain revoked history in place plus audit records, and add brand/country/capability scopes later as additive structures. Check constraints are recommended over enums for the staged rollout. Platform flags remain platform-only; browser upserts are removed at P2-C.

## P2: authoritative invitations

An invitation is vendor-bound, email-bound, role-bound, expiring, hashed, versioned, revocable, and single use. A trusted server transaction validates the signed-in identity, locks and consumes the invitation atomically, activates or creates membership, and writes audit events. Raw tokens are never stored. The first vendor owner needs platform approval; no first-click owner bootstrap exists.

## Compatibility, portal, and server boundary

Add fields first, preserve reads temporarily, and never retain privileged browser dual-writes. Manufacturer Portal must remove global-role upsert, self-membership insertion, and browser invitation acceptance; Trade Portal must remove global-role upsert. Use one trusted server boundary: an atomic authenticated RPC for acceptance, with an Edge Function where token delivery/rate limiting is required.

## Tests, migration package, rollback, and gates

The specification defines 23 synthetic personas and 28 scenarios, including identity mismatch, expiry, reuse, duplicate membership, concurrent acceptance, stale clients, and rollback. Eight future migration units are deliberately described without SQL. Five gates—P1-A, P1-B, P2-A, P2-B, P2-C—block staging progression until repair, authorization, token, atomicity, and portal evidence passes. Rollback preserves data/audit history and never reopens browser privileged writes.

## Exact next task

Human review of this P1–P2 specification, followed by a staging data-repair worksheet and an implementation proposal for the first additive membership-schema migration only.
