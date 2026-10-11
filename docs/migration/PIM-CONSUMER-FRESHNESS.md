# PIM consumer freshness

The owner requires ApplianceIQ.ai, Spec IQ, Academy and training bots to consume the same PIM evidence. Incoming manufacturer/scraper/Icecat facts and dated pricing evidence are captured into PIM before fill-only website publication. The minute workers and nightly catch-up remain active. Original source dates, completed fields, photographs and pricing evidence are retained; parts are excluded.

## Consumer reads

| Consumer | Product evidence | Refresh behavior |
| --- | --- | --- |
| ApplianceIQ.ai/shared catalog | PIM publication queue to native products | Every-minute bounded worker; fill blanks and append approved missing images |
| Spec IQ | Caller-visible PIM app view; linked catalog-backed package saves | Every autocomplete query; approved active appliance records, newest source first |
| Academy brand product guides | Caller-visible PIM records by canonical brand name | Every brand view; original brand-introduction lessons retained |
| Academy roleplay and utilities | ai-proxy server-side live PIM lookup | Every model request, including recent user-turn model context |
| Customer roleplay/performance scoring | Shared governed roleplay model uses caller-visible live PIM | Every model call, including evaluation and follow-up turns |
| Training personas/widget | ai-team-coach and ai-request-processor shared live lookup | Every request, including model-only questions |

Live model evidence includes description, public specs, dimensions, finish, capacity, fuel, market and source/edit dates. Caller RLS applies throughout; service credentials are used only for existing governed completion logging. Private price/cost/margin/token fields are stripped from specs. An edit timestamp is not external verification. Missing facts remain unknown, conflicting markets remain distinct, and static courses/old conversations cannot override live model evidence. Undated master pricing is not distributed as a current offer.

Academy had 10,762 stored product spotlight cards with the latest PIM sync on August 13, 2026. These source cards are retained, while product views now read live PIM. Generated brand views show at most 60 recent eligible records; bot requests retrieve at most 12 matching models. Those display/context bounds do not limit the stored catalog. Existing customer package snapshots and agreed pricing remain historical documents; new catalog-backed selections resolve current stored facts.

## Verification

Run `node --experimental-strip-types scripts/migration/test-live-pim-products.mjs`, the three AI handler regression scripts, `node --experimental-vm-modules scripts/migration/test-pim-consumers.mjs`, the US bundle builder/check and Spec IQ draft/technical regressions. Tests cover repeated reads seeing changed PIM facts, model-only matching, parts/future-date exclusion, market/source-date preservation, private-field removal and retained brand lessons. A live mapped authenticated SQL read verified access to the new selected columns in the US PIM view. No source data or files are deleted.

Repository saves precede Edge deployment. Deployment evidence is recorded separately; unit/query tests are not a claim that every signed-in UI or paid model invocation has been exercised.

## Coverage goal

The ambition is the broadest, most current appliance PIM. Track appliance counts by brand/market/category, missing descriptions/specs/assets, actual provider observation dates, held identity/source conflicts, intake/publication latency and consumer retrieval health. Global leadership cannot be claimed without coverage benchmarks. Daily source reception and automatic distribution do not mean every model is externally rechecked every day. Complete existing sourced fields remain protected; conflicting incoming evidence is retained for review rather than silently changing facts.
