# IQ Connector Certification

## Lifecycle
Development → Beta → Certified → Suspended.

A connector may only reach Certified when the weighted certification score meets the configured threshold and every required check is Passed or Not Applicable. Live acceptance cannot be replaced by synthetic tests.

## IQ Connector Contract v1.0
Required transaction concepts: stable external transaction identity, occurrence timestamp, one or more line items, line quantity, and line amount. Optional canonical concepts include customer, employee, store, product, inventory, price, refund, quote, payment, service ticket, currency, discounts, cost, margin, warranty, delivery, installation, and haul-away.

Idempotency is enforced at the IQ transaction layer by organization + POS transaction identity, with line-level uniqueness by organization + transaction + external line identity.

## Automated certification
The automated runner verifies baseline and negative fixtures, golden totals, line counts, refund handling, duplicate identity scenarios, malformed payload rejection, canonical contract compatibility, connector-sensitive RLS gates, and transaction idempotency constraints. Evidence is retained per connector/run/fixture.

## Synthetic certification lab
The platform includes an isolated demo organization named `IQ Connector Certification Lab` with a synthetic store, employee, customer, appliance SKU, warranty SKU, and delivery SKU. It is used only for connector certification and never substitutes for live retailer acceptance.

## Required live acceptance
Before Certified status, a connector must pass a real vendor-backed acceptance test covering authentication, initial/incremental sync, employee/store mapping, transactions, refunds, duplicate delivery, reconciliation, quarantine/retry, recovery, tenant isolation, and downstream Command Center/Performance Brain behavior.

## Current connector families
Microsoft Dynamics 365 / Business Central, STORIS, ePASS, Shopify, Oracle Xstore, RETAILvantage, and Windward System Five.
