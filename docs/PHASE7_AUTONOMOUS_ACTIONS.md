# Phase 7 — Autonomous Action Orchestration

Phase 7 extends the existing Command Center. It does not create another manager product.

## Loop
Detect -> Quantify -> Policy Check -> Approve/Auto Execute -> Dispatch -> Audit -> Measure -> Learn

## Policy modes
- `disabled`: IQ will not execute the action.
- `approval_required`: a manager must approve before execution.
- `auto_execute`: IQ may execute only inside the configured caps and confidence threshold.

Customer-facing outreach is hard-blocked from `auto_execute` in Phase 7.

## Governed tables
- `phase7_automation_policies`: per-retailer action permissions and financial/confidence caps.
- `phase7_action_runs`: idempotent execution records linked to Phase 6 opportunities.
- `phase7_action_audit`: immutable-style decision/execution/outcome audit events.

All three tables use RLS and have no direct browser grants. Browser access is through organization-admin RPCs.

## Dispatcher
Safe execution handlers currently cover:
1. adaptive AI coaching for employee performance gaps;
2. auditable AI Manager assignments for Academy, CRM and generic manager work;
3. Phase 6 opportunity acceptance without duplicate manager assignments.

## Scheduling
`phase7-autonomous-orchestration` runs every 15 minutes through `pg_cron` using `cron.schedule`. It evaluates active Phase 6 opportunities, applies each organization's policy, executes allowed actions, and measures due outcomes.

## Outcome measurement
Executed actions carry a baseline metric, target and due date. When due, Phase 7 compares the latest diagnostic evidence with baseline and classifies the result as `improved`, `no_change`, `regressed`, or `insufficient_evidence`. Results are also written to `intelligence_outcomes` for the governed learning layer.

## Reversal
Manager-assignment actions can be reversed by cancelling the downstream open assignment. Other downstream actions are marked reversed with an audit record and require manual review if the external action is not safely reversible.

## Command Center
The existing manager surface receives `phase7-automation.js` at deploy time and exposes:
- pending approvals;
- execution/failed counts;
- automation policy controls;
- approve/reject and run-cycle actions;
- policy modes per action type/module.
