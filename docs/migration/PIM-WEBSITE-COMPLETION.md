# ApplianceIQ.ai PIM completion

User authorized appliance-only catalog completion on October 10, 2026. Existing populated website fields, prices, source/trust metadata and withdrawn records are preserved. Latest dated eligible PIM copies are used only for missing facts. JSON keys merge recursively, preserving false/zero and recognizing common dimension aliases. Native database admission and spec-write triggers remain active.

Only approved, active PIM appliance records with accepted/not-required source review, a known active brand and a plausible model are admitted. Parts/accessory categories, explicit parts flags and obvious mislabelled filter/kit descriptions are excluded. Unknown categories, pending sources, cross-brand/market/category collisions and ambiguous matches are held. New names are factual brand/model/category identifiers, not invented marketing claims. New records remain unverified; no manufacturer verification is invented.

PIM product, image, document and retailer-price changes enqueue the product. The private worker fills blank descriptions, JSON specs/dimensions, valid facets, finish, eligible images/galleries and public current specification documents. Native image rights and actual decoded-image audit checks remain required. Existing fields are never refreshed over populated values; latest date governs selection for blanks. No private dealer cost or margin is distributed.

The 60,955 prior PIM retailer-price rows already existed in the website import ledger. The worker adds missing rows and fills missing exact product links while retaining original observation dates and existing prices. No row was checked in the last 48 hours at inspection. Undated MSRP and stale prices are not current offers. Live selling-price activation remains governed by the website's existing listing/evidence workflow.

Audit before/after images and source dates are stored in private RLS tables. Anonymous and authenticated clients cannot execute the worker. Canada is unchanged. Queue processing and measured backfill results are recorded in pim-website-completion-verification.json.

## Live completion and ongoing updates

The private cron job runs every minute. Product, image, document, retailer-price, separate feature, physical-dimension and pricing-history edits enqueue their product. Feature updates carry their actual edit timestamp; historical creation dates are retained. Latest eligible dated source facts fill blanks without refreshing populated website fields. Future-dated source values are held. New model admission also requires a description that passes native appliance identity checks.

Final net audit: 16,218 descriptions filled; 51 products gained specs, 93 gained dimensions, 26 gained spec-sheet URLs, and six new active appliances were added. No new images qualified. The queue is empty with zero worker errors; all three recent minute runs succeeded. Populated scalar and JSON preservation audits both found zero changes. The repeat/queue and latest-dated-feature rollback tests pass against the final implementation.

During initial rollout, four additive measurement conflicts were repaired from retained audit values, and 26 newly inserted misclassified accessories were hidden without deletion. Stronger parts descriptions and existing-measurement guards are applied. Existing accessory rows affected by the worker were restored with guarded before/after comparisons.

Existing WARN/ERROR advisor counts remain unchanged; the two intentionally private queue/audit tables add RLS-without-policy INFO findings. Applied migration versions are server-assigned and are recorded alongside names in the verification JSON; do not reapply historical SQL or infer unapplied status solely from filename timestamps.
