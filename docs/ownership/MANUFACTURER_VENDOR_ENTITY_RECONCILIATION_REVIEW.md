# ApplianceIQ V1 Manufacturer and Vendor Entity Reconciliation

## Executive summary

The current `mfr_vendors` table contains 19 active rows but no legal-name, entity-type, parent, country-scope, or alias fields. It mixes portfolio controllers with individual brands. All 35 catalog brands still have a null `manufacturer_id`; every vendor has zero members, zero assets, and zero catalog assignments.

The smallest compatible design is to retain `mfr_vendors` as the registry of portal-controlling organizations. Brand rows may remain for display or future delegation, but are not authoritative ownership targets. This requires 12 approved new controlling entities and leaves existing data intact.

## Current-state problems

- Existing portfolio vendors—Whirlpool, GE Appliances, Samsung, Electrolux, Danby, and LG—can control approved portfolios.
- Bosch, Frigidaire, JennAir, KitchenAid, Maytag, and Monogram are brand entities, not evidence that they may administer a corporate sibling portfolio.
- The remaining brand entities without catalog coverage are preserved, not deleted or merged.
- `mfr_members` is vendor-scoped and structurally supports a user joining more than one vendor, but contains no records.
- `manages_vendor(vendor_id)` accepts any membership and ignores `member_role`. Today, a portfolio assignment would therefore give every member content and asset management rights across the entire vendor portfolio. This is a blocking security gate, not a reason to broaden access.

## Entity-model recommendation

Keep `mfr_vendors` manufacturer/portal-controller focused. Do not replace it with a generalized corporate graph. At later implementation, add only the metadata necessary to distinguish `operating_manufacturer`, `corporate_parent`, `appliance_brand`, `licensed_brand_owner`, `licensee`, `distributor`, `importer`, and `private_label_owner`, plus legal name, parent, and country scope.

`brand_catalog.manufacturer_id` should point to the approved controller, not a brand display row or name match. If ApplianceIQ later needs brand-specific delegates within a portfolio, add a narrowly scoped delegation relationship after manufacturer RLS is secure.

## Vendor-by-vendor reconciliation

Keep as canonical controllers: Danby, Electrolux, GE Appliances, LG, Samsung, and Whirlpool. Keep as non-authoritative brand entities: Best, Bosch, Broan, Elica, FOTILE, Frigidaire, JennAir, KitchenAid, Maytag, Monogram, Panasonic, Sharp, and Venmar. There is no current data basis to delete, merge, or rename any row: all have zero members/assets/assignments. Bosch, Frigidaire, JennAir, KitchenAid, Maytag, and Monogram are authority-model merge candidates only; no destructive merge is proposed.

Required new controllers are Middleby Corporation; Beko / Arçelik; BSH Home Appliances; Sub-Zero Group; Bertazzoni; Fisher & Paykel Appliances; Meneghetti; Hestan Commercial; Best Buy (private-label owner); Liebherr; Miele; and True Manufacturing. The JSON has the exact proposed slugs, scope, portfolio, confidence, and approval gates.

## Portal authority and assignment readiness

Fifteen brands can be associated with an existing controller after human approval: Amana, Café, Dacor, Danby, Electrolux, Frigidaire, GE Appliances, GE Profile, Jenn-Air, KitchenAid, LG, Maytag, Monogram, Samsung, and Whirlpool. Eighteen require the approved creation of a missing controller. Hotpoint is blocked by regional scope; Insignia is blocked until a private-label owner policy is approved.

These labels describe ownership-entity readiness only. Every assignment remains blocked from authorization use until Priority 2 manufacturer role/membership hardening is deployed and verified in staging.

## Hotpoint regional treatment

GE Appliances' official Hotpoint support states that GE Appliances owns Hotpoint in the Americas, including the United States and Canada, while Whirlpool is a separate European owner. For the current US/CA scope, GE Appliances is the correct proposed controller. A single global Hotpoint record is acceptable only while its content and authority are limited to the Americas; any European expansion requires region-scoped ownership before a mapping is applied.

## Implementation sequence and unresolved decisions

1. Approve the 12 proposed controlling entities and the non-authoritative treatment of existing brand rows.
2. Decide whether each new entity is represented as a new `mfr_vendors` row and identify its verified legal/operating representative for US/CA portal administration.
3. Complete Priority 2 manufacturer authorization hardening, including role-aware vendor membership checks and a limited brand-delegation design if needed.
4. Prepare a staging-only, non-destructive data-repair migration using immutable IDs from the approved ownership and entity maps.
5. Validate existing administrators, public/trade content, and cross-portfolio isolation before production approval.

Explicit human decisions remain required for Hotpoint regional governance, Insignia/private-label policy, BSH/Sub-Zero/Middleby/Beko portfolio contacts, and whether brand entities should ever receive delegated access.

## Exact next task

Priority 2 manufacturer authorization and membership hardening: define and test role-aware vendor administration before creating any new controller entity or populating `brand_catalog.manufacturer_id`.
