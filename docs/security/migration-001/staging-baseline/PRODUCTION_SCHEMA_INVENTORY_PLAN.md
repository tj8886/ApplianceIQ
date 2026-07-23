# Production schema inventory plan

Use explicit production metadata-only access to capture public tables, columns, types, nullability, defaults, generated/identity fields, keys, checks, indexes, sequences, enums, domains, views, materialized views, functions/procedures, triggers, RLS, policies, extensions, publication membership, scheduled-job metadata where available, ownership, and cross-schema dependencies.

Never retrieve table rows, `auth.users`, customer records, invitation tokens, Storage files, Vault values, credentials, or connection strings. Record counts and structural definitions only. Production currently exposes 212 public tables, 164 functions, 34 security-definer functions, 164 triggers, 211 RLS-enabled tables, 397 policies, 619 indexes, and 1,045 constraints; each security-definer function and policy family requires manual portability review before a candidate baseline is approved.
