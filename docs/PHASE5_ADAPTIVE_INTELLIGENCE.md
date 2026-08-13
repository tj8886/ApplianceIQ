# Phase 5 — Adaptive Intelligence

Phase 5 extends the Phase 4 closed-loop coaching system. It does not replace the Performance Brain or create a parallel trainer.

## Goal

Use observed performance, Beat the Bot results, skill evidence and measured coaching outcomes to personalize the next intervention for each salesperson.

## Adaptive profile

`ai_adaptive_coaching_profiles` stores the current per-rep operating profile:

- challenge level from 1–5
- coaching intensity: light, standard or intensive
- recent roleplay and skill scores
- learning velocity from recent measured intervention deltas
- recent coaching success rate
- evidence count and confidence
- preferred intervention sequence and strategy

Cold start is explicit. Profiles with little evidence use conservative defaults and low confidence rather than fabricating precision.

## Strategy learning

`ai_coaching_strategy_performance` learns effectiveness by organization, metric, skill, strategy and difficulty. Each measured intervention updates attempts, successes, failures, average performance delta and a Beta-prior posterior success estimate.

A strategy is not exploited from outcome history until it has at least three measured attempts and a posterior success estimate of at least 0.55. Before that, Phase 5 remains in exploration/cold-start mode and uses the rep profile.

## Decision audit trail

`ai_adaptive_coaching_decisions` records every adaptive decision including:

- intervention and evaluation IDs
- strategy and difficulty
- sequence
- Beat the Bot target score
- rationale and confidence
- whether the choice was exploration
- eventual measured outcome and delta
- when that outcome was learned

This makes personalization inspectable rather than an untraceable prompt-side behavior.

## Adaptive strategies

Initial strategies are deliberately small and governed:

- `foundation`: lesson → roleplay → floor challenge → review
- `field_first`: roleplay → floor challenge → lesson → review for stronger reps
- `practice_heavy`: foundation sequence with an explicit repeat-roleplay recommendation
- `reinforce`: standard sequence at higher coaching intensity when recent intervention effectiveness is weak

Difficulty maps to Beat the Bot targets of 65, 72, 78, 84 and 90 for levels 1–5.

## Closed-loop learning

A database trigger observes the existing Phase 4 evaluation record. When an adaptive intervention becomes `measured`, Phase 5 learns the outcome exactly once, updates the strategy-performance cell, records the decision outcome and refreshes the rep profile. `learned_at` makes this idempotent.

The Phase 4 evaluator remains the source of truth for measurement. Phase 5 consumes its result rather than duplicating outcome logic.

## Manager intelligence

`phase5_manager_dashboard` returns adaptive profiles, learned strategy cells and recent decisions.

`phase5_manager_recommendations` ranks manager attention using coaching intensity, low measured effectiveness, negative learning velocity and overdue active interventions.

`apps/platform/adaptive-intelligence.html` provides the management console.

## Shared client API

`apps/platform/aiq-adaptive-client.js` adds `ApplianceIQ.adaptive` with:

- `refreshProfile`
- `selectStrategy`
- `generate`
- `generateOrganization`
- `repPlan`
- `managerDashboard`
- `managerRecommendations`

## Security

Adaptive tables are RLS-enabled and are not directly granted to `anon` or `authenticated`. Client access is through allowlisted, membership-aware RPCs. Cross-user reads and generation require organization-admin access. The internal learning function and trigger are service-only.

## Validation

Rollback validation creates a real-shaped adaptive intervention, applies a strategy, marks its evaluation measured and verifies that exactly one strategy-learning update occurs. The test transaction is rolled back so no fake employee assignment or outcome remains in production.
