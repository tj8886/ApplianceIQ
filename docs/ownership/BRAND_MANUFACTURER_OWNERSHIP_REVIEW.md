# ApplianceIQ V1 Brand-to-Manufacturer Ownership Review

## Executive summary

This design-only review establishes a proposed canonical owner for every one of the 35 `brand_catalog` records. It does not update `brand_catalog.manufacturer_id`, create vendors, or alter Supabase. All 35 current assignments are `NULL`; 16 can be proposed against an existing portfolio-level vendor after approval. Nineteen require a missing controlling-vendor record, and Hotpoint additionally requires regional licence-scope review.

The central rule is simple: `brand_catalog.manufacturer_id` must identify the controlling manufacturer/vendor entity, never a string match, distributor, retailer, or an inferred OEM. A vendor with the same display name is not automatically the correct owner for a sibling portfolio brand.

## Source data and methodology

Read-only queries inspected `brand_catalog`, `mfr_vendors`, `aiq_products`, and `aiq_documents`. The catalogue contains 35 unique active brands, 20 with products and 15 without; no catalog brand has a populated `manufacturer_id`. There are 19 unique vendor names and no literal duplicates. No related product documents were found.

The JSON specification preserves the database IDs, current parent-company text, product/document counts, and first-party evidence links. Public evidence was used to corroborate portfolio relationships; where an appropriate controlling vendor does not yet exist, the proposed ID deliberately remains `null`.

## Ownership decisions and special cases

| Portfolio / brand set | Canonical controlling manufacturer | Decision |
| --- | --- | --- |
| Amana, Jenn-Air, KitchenAid, Maytag, Whirlpool | Whirlpool Corporation | Use existing Whirlpool vendor after approval. Jenn-Air's catalog spelling must not drive runtime matching. |
| Café, GE Appliances, GE Profile, Monogram | GE Appliances (Haier company) | Use existing GE Appliances vendor after approval. |
| Hotpoint | GE Appliances in the North American catalogue | Treat as a regional/licensed-brand case; confirm scope before mapping. |
| Dacor, Samsung | Samsung Electronics | Use existing Samsung vendor after approval. Dacor has been Samsung-owned since 2016. |
| Electrolux, Frigidaire | Electrolux Group | Use existing Electrolux vendor after approval. |
| Bosch, Gaggenau, Thermador | BSH Home Appliances / Bosch Group | Do **not** map sibling brands to the existing Bosch-named vendor. Create or verify one BSH portfolio vendor first. |
| Sub-Zero, Wolf, Cove | Sub-Zero Group, Inc. | Do **not** create three independent owner mappings. Create or verify the group vendor first. |
| Beko, Blomberg | Beko / Arçelik | Create or verify an Arçelik/Beko controlling vendor first. |
| AGA, La Cornue, Viking | Middleby portfolio | Verify the current North American controlling entity and create/approve it before mapping. |
| Fisher & Paykel | Fisher & Paykel Appliances / Haier Smart Home | Create or verify the correct operating entity before mapping. |
| Insignia | Best Buy | Private label: never infer an OEM manufacturer as the owner. |

The remaining direct brands (Bertazzoni, Danby, Fulgor Milano, Hestan, LG, Liebherr, Miele, True Residential) either have an exact active vendor recommendation (Danby and LG) or require a new/verified controlling-vendor record. No distributor relationship has been substituted for ownership.

## Data-quality findings

- `manufacturer_id` is null for all 35 brands, despite the column being the intended canonical foreign key.
- Existing `mfr_vendors` combine portfolio entities (for example Whirlpool, GE Appliances, Samsung, Electrolux) with individual brand entities (for example Bosch, JennAir, KitchenAid, Maytag, Monogram). This is not a duplicate-name problem, but it is a governance and permission-scope problem.
- `brand_catalog.parent_company` is useful evidence but is not yet a normalized, enforceable ownership relationship.
- Brand names and vendor names differ in meaningful ways (`Jenn-Air` versus `JennAir`) and cannot safely be joined by text.
- No catalog-linked documents were found in this audit; product ownership therefore cannot be corroborated by document lineage.

## Recommended implementation approach

1. Human-approve this ownership specification and the 16 existing-vendor recommendations.
2. Resolve the 19 missing controlling-vendor entities, including the intended permission scope for BSH, Sub-Zero Group, Beko/Arçelik, Middleby, and Haier/Fisher & Paykel.
3. Create a non-destructive data-repair migration only after entity approval; populate `brand_catalog.manufacturer_id` from immutable IDs in this specification.
4. Verify every mapping in staging with existing portal users before manufacturer RLS uses the relationship.
5. Retain `parent_company` as descriptive provenance until its migration/reconciliation plan is approved; do not authorize from it.

## Risks and approval requirements

The primary risk is treating a local brand vendor as though it controls a whole parent portfolio. That could grant a Bosch, JennAir, KitchenAid, or Maytag portal administrator access beyond their legitimate scope. The opposite risk is creating new group vendors without confirming which legal entity should contract, publish content, or manage members in Canada and the United States.

Human approval is required for all recommendations, with explicit legal/entity confirmation required for the 19 records lacking a controlling vendor and for Hotpoint's regional licence scope (20 manual-review records in total). No ownership relation should be applied automatically from this document.

## Exact next implementation task

Conduct a human-approved vendor-entity reconciliation: decide whether each missing controlling manufacturer should be represented by a new `mfr_vendors` row or an approved existing portfolio entity, then prepare a non-destructive staging migration to populate only the approved `brand_catalog.manufacturer_id` values.
