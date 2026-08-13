# Phase 2 — One ApplianceIQ

## Goal

Make ApplianceIQ behave as one operating system even though modules are deployed separately.

## Built

### Unified Workspace

`apps/platform/workspace.html`

The Workspace is a first-party Platform surface (`platform_modules.key = workspace`, version `2.0.0`) and provides:

- organization switcher,
- location/store switcher,
- entitlement-aware app launcher,
- Platform operations launcher,
- notification inbox and read-state,
- global search,
- visible current context,
- focused-record clearing,
- cross-module launch context.

### Shared Platform Context

`platform_user_context` persists one current context per authenticated user:

- `organization_id`
- `location_id`
- `entity_type`
- `entity_id`
- `entity_label`
- `source_module_key`
- arbitrary JSON `context`

RLS permits users to read/write only their own row. Context setter RPCs separately validate active organization membership and location ownership.

### Context RPCs

- `my_platform_context()`
- `set_platform_context(...)`
- `my_platform_organizations()`
- `my_platform_locations(organization_id)`

All require an authenticated user. No anonymous execution is granted.

### Shared front-end bridge

`apps/platform/aiq-context-bridge.js`

Modules can import the bridge and use:

```js
const bridge = createAIQContextBridge({ supabase, moduleKey: 'crm' });
await bridge.init();
await bridge.focus('contact', contact.id, contactName, { source: 'pipeline' });
```

The bridge emits `aiq:context-changed` in the browser whenever context changes.

### Global Search

`platform_global_search(query, limit)` searches within the user's active organization and returns typed context results for:

- CRM contacts → CRM
- products → Product IQ
- POS transactions → Command Center

Selecting a search result writes it into Platform Context before launching the target module.

### Notifications

Workspace reads `crm_notifications` for the authenticated user and uses `platform_mark_notification_read(notification_id)` to safely mark only that user's notification read.

## Cross-app contract

A module receiving a user from Workspace should:

1. restore the normal ApplianceIQ authenticated session using the existing relay mechanism,
2. import `aiq-context-bridge.js` or implement the same RPC contract,
3. call `my_platform_context()` after session initialization,
4. if `entity_type` belongs to that module, navigate to the corresponding record,
5. whenever the user changes focus inside the module, call `set_platform_context(...)` / `bridge.focus(...)`.

Examples:

- CRM opens `contact` context.
- Product IQ opens `product` context.
- Command Center opens `transaction`, `employee`, or `store` context.
- AI Coach can use `employee`, `customer`, `product`, or `transaction` context when starting coaching.
- IQ Academy can use employee/performance/product context to choose training.

## Security note

The existing inter-site authentication relay still transfers Supabase session tokens in the URL fragment. Phase 2 does **not** broaden that mechanism. Platform Context itself contains no credentials and is tenant-validated in the database.

A later auth-shell hardening pass should replace token relay with a dedicated short-lived inter-app session exchange once all modules support the common bootstrap contract.

## Remaining module rollout

The shared Platform/DB layer is complete. Each independently deployed application still needs its small context-consumer adapter so it can auto-open the focused record and publish focus changes back to Platform Context. This is intentionally a thin per-module integration, not a separate context implementation in every app.
