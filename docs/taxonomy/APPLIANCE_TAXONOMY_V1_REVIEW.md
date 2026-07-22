# ApplianceIQ Canonical Product Taxonomy — V1 Review

## Executive summary

This is a proposed, database-backed canonical taxonomy. It is a design artifact only: it does not create schema, modify catalogue records, or change application behaviour. A versioned JSON projection may later serve frontends, but it must never become the source of truth.

V1 covers the current catalogue's five proven groups: Refrigeration, Cooking, Dishwashing, Laundry, and Ventilation. Beverage, specialty kitchen, outdoor kitchen, commercial equipment, and accessories are deliberately deferred because the current catalogue contains no products requiring their own V1 group.

## Source data reviewed

Read-only `SELECT` queries inspected `aiq_products`, `brand_catalog`, `mfr_vendors`, `aiq_product_specifications`, `aiq_product_relationships`, `aiq_documents`, `mfr_assets`, and `brand_training_cards`.

- 88 products, 88 unique models, 20 brands, and 9 recorded manufacturer text values.
- Current categories: cooking 34, refrigeration 23, dishwashers 17, laundry 11, ventilation 3.
- All products are available in CA and US; all are active, approved, and public-visible in the extracted catalogue.
- There are no duplicate models, blank brands, or blank categories.
- There are no product specifications, relationships, documents, or manufacturer assets yet.
- `brand_catalog.manufacturer_id` is null for all 35 brands. Consequently every proposed mapping uses verified manufacturer `UNKNOWN`; recorded manufacturer text is not treated as ownership proof.

## Architecture and tree

The tree and machine-readable node definitions are in the JSON specification. Categories identify product identity. V1 refrigeration leaves are French Door, Refrigerator-Freezer Systems, Column, Side-by-Side, Compact, and Wine Storage; cooking leaves are Ranges, Wall Ovens, Rangetops, and Cooktops; followed by Dishwashers and Dish Drawers; Washers, Dryers, Washer-Dryer Combos, and Laundry Centres; plus Range Hoods.

## Normalization decisions

- Smart, Wi-Fi, remote diagnostics, and AI claims are capabilities—not categories.
- Luxury and professional positioning are market facets governed editorially.
- Built-in, freestanding, undercounter, slide-in, and wall mount are installation facets. Built-in refrigeration was removed as a category: it is the installation context of French-door, side-by-side, column, wine-storage, compact, or refrigerator-freezer products. Compact refrigeration remains a subtype because it represents a materially distinct appliance class; undercounter is retained only as an installation facet. Column refrigeration remains a subtype because it changes discovery, comparison, dimensions, and installation planning.
- Panel-ready is a finish/panel facet.
- Outdoor rating and commercial applicability are facets until actual catalogue evidence requires materially distinct products.
- Microwave drawers, laundry centres, and washer-dryer combos remain distinct only where their product form is materially different.
- Accessories will be products connected through compatibility relationships when the catalogue contains them.

## Facets, audience, and visibility

V1 defines only controlled facets that support present catalogue classification and future retrieval: installation, fuel, form factor, market position, usage applicability, environment, connectivity, smart capability, accessibility, certification, energy, finish/panel, laundry configuration, and ventilation configuration. Arbitrary dimensions, airflow, capacity, electrical requirements, and detailed certifications remain in `aiq_product_specifications` JSONB.

Audience answers *who a record is useful for*: consumer, retail sales, builder, designer, installer, service, manufacturer, commercial, or internal. Visibility answers *who may access it*: internal, manufacturer, trade, authenticated, or public. Product, document, asset, Academy, CRM, and AI systems should apply visibility through their existing publication/authorization rules and use audience for relevance/filtering.

## Product mapping summary and manual review

The JSON contains all 88 detailed mapping proposals and five known manual-review cases. Every row preserves verified manufacturer as `UNKNOWN` because the canonical brand-to-vendor ownership relationship is not populated. The mapping artefact is ready for human review, not implementation approval.

## Governance

Platform content stewards, product/Academy editors, and verified manufacturers may propose changes. A Platform Administrator or designated taxonomy steward approves categories, facets, aliases, and releases using the existing organization administration model; no new authorization system is proposed here. Manufacturers submit suggestions only; they never write canonical nodes directly. Deprecation occurs in a new immutable version with a replacement where applicable. Historical assignments keep their original node and version.

After approval, a release produces a versioned JSON projection, then taxonomy-aware metadata and AI embeddings are refreshed. Rollback republishes the prior approved immutable release. Every proposal, evidence source, reviewer, approval, version, and publication action needs an audit record in the future implementation.

## Known limitations and migration recommendations

The catalogue has broad text categories and no canonical product-to-brand or product-to-manufacturer FK. Manufacturer ownership mapping must be completed before any manufacturer-scoped taxonomy editing is enabled. Product specifications and supporting documents are empty, so facet backfill must be evidence-led and staged. Do not remove current `aiq_products.category` values until canonical assignment coverage and consumer compatibility are verified.

## Risks

- The absent brand/manufacturer relationships make manufacturer attribution unsafe.
- Market-position assignments require editorial governance; they must not be derived only from price or brand.
- Many requested facets have no product-level specification source yet; blank is safer than inference.
- The seed must not be implemented until human review approves the five manual-review classifications and the separate brand-to-vendor ownership mapping.

## Exact next implementation task

Human-review the five flagged product mappings and approve the complete V1 specification together with the separate canonical brand-to-vendor ownership mapping. Only then design the smallest taxonomy schema migration.
