# Peer-review checklist

- [ ] The package matches the approved Migration 001 Change Request without redesign.
- [ ] All forward SQL is additive and the three permitted safe-default `NOT NULL` columns are the only ones.
- [ ] The 14 membership additions and 13 invitation additions match names, types, defaults, and nullable behavior.
- [ ] Existing invitation `status` and `accepted_at` remain unchanged.
- [ ] `vendor_id` is nullable; its future `mfr_vendors.id` FK is deferred with approved delete/update behavior.
- [ ] The four indexes match their approved names and ordered columns; no other index or constraint is introduced.
- [ ] No authorization behavior, RLS, policies, helpers, triggers, Storage, portal, or application code changes exist.
- [ ] Verification SQL is read-only; rollback only targets Migration 001 objects and its forward-fix boundary is explicit.
- [ ] Transaction, timeout, lock, and rollback assumptions are suitable for the staging runner.
- [ ] Global-role review remains an execution blocker; no SQL has been executed and Supabase remains untouched.
