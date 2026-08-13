# Command Center / AI Manager / Decision Intelligence Audit

## Conclusion

Do not build another manager operating system. The existing Command Center already contains the major operating layers. The correct architecture is to consolidate and strengthen these existing surfaces.

## Authoritative responsibilities

### Command Center (`apps/command-center/index.html`)
Primary management operating UI. Owns KPI drill-down across corporate/region/store/rep and domain views for revenue, warranty, brands, stores, reps, coaching, training, floor/Up System, leaderboard, AI insights, and settings.

### AI Manager (`apps/command-center/manager.html`)
Operational orchestration surface. Owns manager cycle, active assignments, escalations, adaptive coaching priorities, Phase 6 revenue opportunities, and Phase 7 automation/approvals.

### My Work (`apps/command-center/my-work.html`)
Execution surface for named ownership, due dates, evidence, comments, completion, approvals, and escalation history.

### Decision Intelligence (`apps/command-center/decisions.html`)
Authoritative cross-domain decision/action feed. `decision_cases` / `decision_predictions` remain the governed prioritization and forecast spine.

### Predictive Intelligence (`apps/command-center/predictions.html`)
Authoritative forecast/outcome UI. Phase 8 Retail Digital Twin is attached here; simulations remain distinct from forecasts and actuals.

### Executive Intelligence (`apps/command-center/executive.html`)
Evidence-backed executive summary and question/answer surface.

### Executive Briefs (`apps/command-center/briefs.html`)
Morning, end-of-day, and weekly management narrative and delivery workflow.

## Existing backend capabilities confirmed

- `ai_manager_get_dashboard`
- `ai_manager_run_cycle`
- `ai_manager_generate_executive_brief`
- `ai_manager_get_executive_briefs`
- `ai_manager_get_my_work`
- manager assignment / comment / completion / approval / attachment RPCs
- `decision_calculate_priority`
- `decision_get_feed`
- `decision_sync_executive_insights`
- `decision_generate_operational_forecasts`
- `decision_record_prediction_outcome`
- Phase 5 adaptive coaching dashboard/recommendations
- Phase 6 revenue intelligence
- Phase 7 autonomous action orchestration
- Phase 8 forecasting integration

## Duplication found

The legacy `AI Insights` view in `apps/command-center/index.html` directly calls `ai-proxy` and stores generated recommendations in `ai_budget_predictions`. This predates the governed Phase 3-8 intelligence stack and should no longer be treated as an authoritative operating-intelligence path.

`ai_budget_predictions` may remain as a budget-planning/domain store, but new cross-domain operational recommendations should flow through the governed Intelligence / Decision / Manager stack.

The main Command Center `index.html` also contains an obsolete `#aiq_relay` refresh-token bootstrap. Phase 2 introduced one-time handoff tickets; the legacy relay should be removed after confirming the Platform deployment adapter supplies the secure handoff path to Command Center.

## Canonical operating flow

Operational evidence
-> governed Intelligence events / identities
-> Decision Intelligence prioritization + predictions
-> AI Manager orchestration
-> manager assignment / approval / autonomous action
-> execution in Coach / Academy / CRM / Up / other module
-> measured outcome
-> Intelligence learning
-> Command Center / Executive Brief visibility

## Strengthening plan

1. Keep the current Command Center as the single management product.
2. Keep AI Manager, My Work, Decisions, Predictions, Executive Intelligence, and Briefs as first-party views inside that product.
3. Route new operating recommendations through Decision Intelligence rather than direct `ai_budget_predictions` writes.
4. Have executive briefs consume Phase 5-8 evidence and action/outcome state, not a separate priority model.
5. Make the main Command Center navigation expose Manager, My Work, Decisions, Predictions, Executive Intelligence, and Briefs clearly.
6. Remove the legacy refresh-token relay once secure Platform handoff coverage is verified.
7. Do not create a new global-priority table unless the existing `decision_calculate_priority` contract proves insufficient after live POS evidence arrives.

## Product rule

Command Center is the manager-facing operating system. Intelligence engines may remain separate internally, but managers should encounter problems, priorities, actions, forecasts, and outcomes through one Command Center product rather than learning the internal architecture.