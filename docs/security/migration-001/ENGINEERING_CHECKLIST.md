# Engineering checklist

- [ ] Baseline, clean tree, and staging-only boundary verified.
- [ ] Approved names, types, nullability, and defaults match all 14 membership decisions.
- [ ] Approved names, types, nullability, and defaults match all 15 invitation decisions.
- [ ] Exactly 13 invitation columns are added; `status` and `accepted_at` are not re-added.
- [ ] `vendor_id` is nullable, has no default, and has no FK.
- [ ] Only the two metadata columns and `token_version` are newly `NOT NULL`.
- [ ] Metadata defaults are empty JSON objects and token version defaults to 1.
- [ ] No default grants access, assigns a role, or creates an active membership/invitation state.
- [ ] Exactly four approved non-unique indexes are present; all eight FK groups remain deferred.
- [ ] No update, delete, destructive forward drop, existing-column tightening, FK, unique/check constraint, role/status enforcement, RLS, policy, helper, trigger, Storage, portal, or application-code change exists.
- [ ] Forward/rollback/verification paths are separated so only the forward migration auto-runs.
- [ ] SQL has not been executed; Supabase remains untouched and no deployment occurred.
