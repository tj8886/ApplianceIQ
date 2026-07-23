# Baseline object classification policy

Include application-owned public tables, columns, keys, checks, indexes, sequences, enums, views, portable functions/triggers, RLS state, policies, and required extensions only after review. Classify each object as `INCLUDE_IN_BASELINE`, `INCLUDE_WITH_REVIEW`, `EXCLUDE_SYSTEM_MANAGED`, `EXCLUDE_ENVIRONMENT_SPECIFIC`, `EXCLUDE_DATA_ONLY`, `EXCLUDE_SECRET_BEARING`, `EXCLUDE_DEPRECATED`, or `BLOCKED_UNKNOWN_PURPOSE`.

Exclude all rows, Auth identities/sessions/tokens, Storage objects, Vault secrets, webhook/OAuth values, monitoring/audit rows, production jobs, environment URLs, and copied migration history. Supabase-managed schemas (`auth`, `storage`, `realtime`, `extensions`, `graphql`, `graphql_public`, `vault`, and `supabase_migrations`) are not recreated manually; application references to them receive separate portability review.
