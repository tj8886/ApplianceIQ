# Phase 3 — Connected Intelligence

## Purpose

Phase 3 turns ApplianceIQ modules into producers and consumers of one governed intelligence layer. Modules do not integrate point-to-point. They publish normalized events and identities, then Command Center and IQ Intelligence Group consume the same contract.

## Sources of truth

- `intelligence_events` — governed event bus. Raw legacy `event_type` is preserved; `canonical_event_type` is the normalized contract.
- `intelligence_entities` — Intelligence Core entity envelope required by the historical event model.
- `platform_identity_links` — source/business-record to canonical identity graph.
- `platform_canonical_entity_types` — canonical entity catalog.
- `platform_canonical_event_types` — canonical event catalog.
- `platform_event_type_aliases` — backward-compatible mapping from historical event names to canonical event names.
- `platform_intelligence_unresolved_events` — quarantine for events that cannot safely resolve organization/context.

## Current producers

- CRM `contacts` → `customer.created`, `customer.updated`
- Product IQ `products` → `product.created`, `product.updated`
- POS `iq_pos_transactions` → `transaction.completed`, `transaction.refunded`
- IQ Up `iq_traffic_events` → `traffic.observed`
- IQ Up `iq_customer_interactions` → `interaction.started`, `interaction.completed`, `interaction.no_sale`
- IQ Academy `academy_learning_events` → `learning.progressed`, `learning.completed` when organization resolution is unambiguous; otherwise quarantine
- IQ Field `field_store_scores` → `field.score_recorded` when the Field store maps to an ApplianceIQ organization location; otherwise quarantine

## Identity graph

The initial identity graph is seeded from CRM customers, Product IQ products, canonical organization locations, and POS employee mappings. `canonical_id` represents the ApplianceIQ business identity. `intelligence_entity_id` links that identity to the historical Intelligence Core envelope used by `intelligence_events`.

Identity links retain source system, source table, source record, external ID, match confidence, match method, verification status, and first/last seen timestamps.

## Event guarantees

`platform_emit_intelligence_event` validates event type/subject compatibility, resolves or creates the required Intelligence Core entity envelope, preserves the business entity UUID in event metadata, assigns a correlation ID, and enforces organization/source/dedupe-key idempotency.

Historical event names are not rewritten. `canonical_event_type` provides the normalized v1 contract and `platform_event_type_aliases` provides compatibility.

## Consumers

Authenticated organization members can consume:

- `platform_intelligence_feed` — canonical event feed
- `platform_intelligence_summary` — organization summary
- `platform_intelligence_store_rollup` — store traffic/sales/conversion/revenue/refund/field metrics
- `platform_intelligence_employee_rollup` — salesperson interactions/sales/revenue/learning/coaching metrics
- `platform_resolve_identity` — source/external identity resolution

The shared deployment-injected `aiq-module-adapter.js` exposes these as:

- `ApplianceIQ.intelligence.feed()`
- `ApplianceIQ.intelligence.summary()`
- `ApplianceIQ.intelligence.stores()`
- `ApplianceIQ.intelligence.employees()`
- `ApplianceIQ.intelligence.resolveIdentity()`

Command Center and IQ Intelligence Group module manifests declare this same contract.

## Operations

`apps/platform/intelligence-stream.html` is the internal Phase 3 operations console. It shows organization summary, store intelligence, employee intelligence, and latest governed events using the same RPCs available to first-party apps.

## Security

Event publishing and identity mutation functions are service-role/internal only. Client-facing read RPCs verify active organization membership before returning data. Identity/unresolved infrastructure tables have RLS enabled and no direct anonymous/authenticated table access.

## Design rule

A new module should publish or consume the canonical contract. It should not create another independent cross-app event bus, customer identity table, store identity table, or performance rollup unless the canonical model is proven insufficient and deliberately versioned.