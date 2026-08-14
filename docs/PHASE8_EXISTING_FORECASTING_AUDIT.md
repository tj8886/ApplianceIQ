# Phase 8 — Existing Forecasting Audit & Integration

Phase 8 does not introduce a replacement forecasting subsystem. It audits and connects the forecasting assets that already exist.

## Canonical architecture

### Canonical cross-domain prediction record
`decision_predictions`

Why: it is tied to `decision_cases`, carries probability/range/financial impact/cost of inaction, supports expiration, and records actual outcomes plus forecast error.

### Specialized traffic/staffing engine
`iq_hourly_traffic_summaries` -> `iq_staffing_predictions`

The existing staffing table was populated but stale/historical-computed. Phase 8 revives it as a forward 7-day forecast using same-weekday/hour historical traffic evidence, then bridges daily staffing demand into `decision_predictions`.

### Existing manager surface
`apps/command-center/predictions.html`

This remains the Predictive Intelligence UI. Phase 8 adds the Retail Digital Twin controls there rather than creating another forecasting application.

## Dormant / non-authoritative forecast stores
- `aicrm_forecasts`: schema exists, currently empty. Keep as a domain-specific CRM store if future CRM workflows require it, but do not use as the platform forecast spine.
- `ai_budget_predictions`: schema exists, currently empty. Keep for future budget planning workflows, not real-time operating intelligence.
- `decision_predictions`: authoritative operating forecast record.

## Existing data found during audit
- `iq_hourly_traffic_summaries`: 322 rows
- `iq_staffing_predictions`: 334 legacy rows before forward refresh
- `aicrm_forecasts`: 0 rows
- `decision_predictions`: 2 rows before staffing bridge
- `ai_budget_predictions`: 0 rows
- `performance_scenarios`: 6 rows
- `ai_scenario_definitions`: 6 rows

## Phase 8 integration
- `phase8_refresh_staffing_forecasts(org, days)` generates forward staffing predictions from actual hourly traffic history.
- Each daily store forecast is represented as a `decision_case` plus `decision_predictions` record with `prediction_type=staffing_demand`.
- `phase8_simulate_store(...)` is a bounded what-if simulator using recent traffic and performance baselines. Responses are explicitly marked `scenario_type=simulation` and `not_actual=true`.
- `phase8_forecast_context(org)` provides store and forecast status to the Predictive Intelligence UI.
- `phase8_run_scheduled_forecasts()` refreshes the existing forecasting stack daily and expires stale predictions.
- `phase8-existing-forecast-refresh` runs daily at 05:17 UTC via pg_cron.

## Governance
Forecasts, simulations, and actuals remain distinct. Simulated financial outputs must never be written as actual revenue or margin. Existing model/outcome measurement through `decision_record_prediction_outcome` remains the learning path for forecast accuracy.
