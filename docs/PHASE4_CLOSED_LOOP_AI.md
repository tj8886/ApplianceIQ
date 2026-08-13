# Phase 4 — Closed-Loop AI

## Purpose

Phase 4 turns the Performance Brain, IQ Academy, Beat the Bot, live sales activity, POS outcomes, Command Center, and IQ Intelligence Group into one measurable coaching loop. Coaching is not considered complete when content is assigned. The loop closes only when post-intervention business evidence is measured and recorded.

## Closed-loop contract

1. **Observe** — Phase 3 intelligence, POS, IQ Up, Academy, coaching reviews, and performance diagnostics provide employee evidence.
2. **Diagnose** — existing `performance_metric_diagnostics` and `performance_skill_state` identify performance and skill gaps.
3. **Prescribe** — existing `ai_generate_daily_coaching_focus` creates an `ai_coaching_interventions` record and four-step intervention plan.
4. **Govern** — `phase4_generate_coaching` links the intervention to `intelligence_recommendations` and creates an `ai_intervention_evaluations` measurement contract containing baseline, target, due date, and evidence.
5. **Intervene** — the default prescription sequence is micro-training → Beat the Bot practice → live-floor challenge → 7-day recheck. `phase4_complete_step` records completion, scores, references, and evidence.
6. **Measure** — `phase4_evaluate_intervention` reads the latest comparable performance diagnostic or skill state after the intervention window and compares it to baseline/target.
7. **Learn** — the measured result is recorded in `intelligence_outcomes`, linked back to the recommendation and intervention, and emitted onto the governed `intelligence_events` stream.
8. **Manage** — Command Center / Platform surfaces consume `phase4_coaching_dashboard`, while IQ Intelligence Group can consume the canonical Phase 3 event stream to study intervention effectiveness across stores, people, skills, and scenarios.

## Core data model

### Existing assets retained

- `performance_metric_diagnostics`
- `performance_skill_state`
- `performance_competencies`
- `ai_skill_definitions`
- `ai_scenario_definitions`
- `ai_coaching_interventions`
- `ai_intervention_steps`
- `intelligence_recommendations`
- `intelligence_outcomes`
- `intelligence_learning_signals`

Phase 4 deliberately extends these rather than creating duplicate coaching and learning systems.

### New measurement contract

`ai_intervention_evaluations` stores:

- organization and intervention
- linked Intelligence recommendation
- metric key
- baseline value
- target value
- observed post-intervention value
- delta and success result
- evaluation due date and measurement timestamp
- measurement source
- linked Intelligence outcome
- evidence payload

The table is service/RPC-only. RLS is enabled and no direct authenticated or anonymous table access is granted. Foreign-key lookup indexes cover intervention recommendation/evaluation links and evaluation recommendation/outcome links.

## Phase 4 RPCs

- `phase4_generate_coaching(organization,user,date)` — generate or retrieve the daily evidence-based intervention and establish recommendation/evaluation linkage.
- `phase4_complete_step(intervention,step,completion_ref,score,metadata)` — complete an intervention step and progress the intervention state machine.
- `phase4_evaluate_intervention(intervention,force)` — measure post-intervention evidence and record an Intelligence outcome.
- `phase4_generate_org_coaching(organization,date,limit)` — organization-admin batch generation for employees with measurable performance gaps, ordered by positive gap severity so the largest shortfall is prioritized first.
- `phase4_evaluate_due_org(organization,limit)` — organization-admin evaluation of completed interventions whose measurement window is due.
- `phase4_coaching_dashboard(organization)` — organization-member management summary and latest interventions.

Internal service helpers include `phase4_attach_evaluation(intervention)`, which guarantees an existing or legacy intervention receives an evaluation linked to that exact intervention, and `phase4_evaluate_all_due(limit)`, which performs due measurement across organizations without generating new coaching.

All exposed Phase 4 RPCs validate organization membership, intervention ownership, or organization-admin authority as appropriate and are registered in the Platform Security Gate allowlist. Internal helpers are service-only.

## Automatic measurement

`pg_cron` is enabled. The job `phase4-evaluate-due-interventions` runs hourly at minute 17 and calls `phase4_evaluate_all_due(100)`.

The job only evaluates interventions that are already completed and whose evaluation date is due. It does **not** generate or assign coaching. This keeps prescription as an explicit user/admin action while removing the need for humans to remember every 7-day measurement window.

## Governed coaching events

Phase 4 publishes:

- `coaching.intervention_created`
- `coaching.step_completed`
- `coaching.intervention_completed`
- `coaching.outcome_measured`

The historical Intelligence Core entity envelope does not contain a physical `coaching` entity type. Phase 4 therefore uses the canonical employee identity as the envelope while preserving `semantic_subject = coaching` in event metadata. This maintains compatibility with the existing Intelligence Core foreign-key/type contract without weakening it.

## Shared application API

The deployment-injected `aiq-module-adapter.js` exposes:

- `ApplianceIQ.coaching.dashboard()`
- `ApplianceIQ.coaching.generate()`
- `ApplianceIQ.coaching.generateOrganization()`
- `ApplianceIQ.coaching.completeStep()`
- `ApplianceIQ.coaching.evaluate()`
- `ApplianceIQ.coaching.evaluateDue()`

The same adapter continues to expose the Phase 3 `ApplianceIQ.intelligence.*` API. Applications therefore share one context, one identity layer, one intelligence stream, and one coaching loop.

## Operations console

`apps/platform/coaching-loop.html` is the Phase 4 management console. It displays active/completed interventions, evaluations due, measured outcomes, effectiveness, and latest intervention detail. Admin actions can generate coaching from current performance gaps and evaluate due completed interventions.

## Validation

Phase 4 was tested inside rollback transactions against existing diagnostic data so no real employee received a test assignment.

Verified contracts:

- fresh diagnostic candidate → 1 intervention
- intervention → 4 prescribed steps
- intervention → 1 Intelligence recommendation
- intervention → 1 scheduled evaluation
- four completed steps → intervention completed
- forced evaluation → measured evaluation + `intelligence_outcomes` record
- governed event bridge → 1 `coaching.intervention_created`, 4 `coaching.step_completed`, 1 `coaching.intervention_completed`, 1 `coaching.outcome_measured`
- legacy evaluation attachment resolves the exact intervention rather than generating a replacement
- organization prioritization orders gaps by positive shortfall severity
- hourly due-evaluation cron is registered and active

The Platform Security Gate was refreshed after production hardening and passed with enforcement active, 0 critical findings, and 0 warning findings.

## Design rule

A coaching feature is not closed-loop merely because an AI generated advice. It must retain the evidence that triggered the intervention, record what was assigned and completed, measure comparable post-intervention evidence, and write the result back into the Intelligence layer. Otherwise it is content generation wearing a management dashboard as a hat.
