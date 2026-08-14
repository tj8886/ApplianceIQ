# Phase 5 — Adaptive Coaching

Phase 5 turns the Phase 4 coaching engine into a closed learning loop.

## What it does

- Builds a per-rep adaptive profile from roleplay, skill, and measured intervention evidence.
- Runs in cold-start mode until enough evidence exists, avoiding false confidence.
- Selects coaching strategy and difficulty from profile evidence plus learned strategy performance.
- Reorders intervention steps and adjusts roleplay targets automatically.
- Records every adaptive decision for auditability.
- Learns exactly once from each measured intervention evaluation.
- Uses Bayesian smoothing for strategy success estimates.
- Refreshes the rep profile after learning.
- Exposes rep plans, manager dashboard data, recommendations, and org-wide adaptive generation through governed RPCs.

## Core tables

- `ai_adaptive_coaching_profiles`
- `ai_coaching_strategy_performance`
- `ai_adaptive_coaching_decisions`

All three tables have RLS enabled and direct anon/authenticated table access revoked. The application is expected to use the governed RPC layer rather than direct table access.

## RPCs

- `phase5_refresh_profile`
- `phase5_select_strategy`
- `phase5_apply_adaptation`
- `phase5_generate_adaptive_coaching`
- `phase5_generate_org_adaptive_coaching`
- `phase5_learn_from_evaluation`
- `phase5_rep_plan`
- `phase5_manager_dashboard`
- `phase5_manager_recommendations`

## Learning loop

1. Phase 4 detects a performance gap and creates an intervention.
2. Phase 5 refreshes the rep profile.
3. Strategy selection chooses a coaching pattern and difficulty.
4. The intervention is adapted and the decision is recorded.
5. Phase 4 measures the intervention outcome.
6. The Phase 5 evaluation trigger learns from the measured result once.
7. Strategy-performance posterior success and confidence are updated.
8. The rep profile is recomputed for the next intervention.

## Cold start

When evidence is sparse, challenge level is held near the middle, strategy remains conservative, confidence is near zero, and the decision is marked as exploration. Once real measured outcomes accumulate, Phase 5 increasingly prefers strategy cells that have at least three attempts and posterior success of at least 55%.

## Security

The Phase 5 RPCs use membership/admin checks before privileged access. Because these are `SECURITY DEFINER` RPCs in the exposed schema, they must remain narrowly granted and authorization checks must stay inside the functions. Supabase's advisor reports `SECURITY DEFINER` RPCs as warnings even when intentionally exposed; each warning still deserves review whenever authorization logic changes.

## Current production state

Production has active adaptive profiles but little or no measured evidence for most reps, so profiles correctly remain in cold-start mode until real coaching outcomes accumulate.
