# Phase 6 — Revenue Intelligence

Phase 6 turns the existing Command Center into a manager action engine.

## Contract

Observe -> Diagnose -> Quantify -> Rank -> Act -> Measure

### Inputs
- POS transactions, gross margin and attachment facts
- CRM pipeline and opportunity health
- Up System traffic and conversion evidence
- performance diagnostics
- Phase 5 adaptive coaching state

### Opportunity model
`phase6_revenue_opportunities` is the governed queue. Each case stores the subject, diagnosis, recommended action, target gap, financial estimate when defensible, confidence, priority, evidence, financial model and downstream module.

Financial values are intentionally conservative. Direct target gaps such as margin dollars and probability-weighted CRM pipeline are quantified. Gaps without sufficient transactional evidence remain severity-ranked until enough POS/CRM evidence exists. As live connector transactions arrive, conversion, attachment, average-ticket, product-mix and traffic opportunity formulas can be enabled from observed retailer economics rather than guessed constants.

### Manager actions
`phase6_accept_action()` converts a revenue opportunity into an auditable `ai_manager_assignments` record. Command Center remains the front door; AI Coach, Academy and CRM are execution modules.

### Command Center
The existing manager page receives `phase6-revenue-intelligence.js` during the Command Center Netlify build. It shows open actions, quantified revenue/margin opportunity, priority-ranked recommendations, confidence, model rationale, and direct action routing.

### Security
The Phase 6 table has RLS enabled and no direct browser grants. The three browser-facing RPCs are organization-admin constrained and are registered in the platform reviewed RPC allowlist.
