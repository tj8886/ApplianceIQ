# Baseline security review plan

Review all 34 security-definer functions for explicit search paths, ownership, volatility, `auth.uid()`/JWT dependencies, Storage references, hard-coded IDs, URLs, and secret-like content. Review the 211 RLS-enabled tables and 397 policies for role targets, `USING`/`WITH CHECK` dependencies, helper functions, and environment assumptions.

Review grants, object ownership, triggers, extensions, realtime publication membership, and cross-schema dependencies. Classify policies as `PORTABLE`, `PORTABLE_WITH_PRECONDITIONS`, `REQUIRES_MANUAL_SECURITY_REVIEW`, `NOT_PORTABLE`, or `UNKNOWN`. No production policy or function is presumed correct solely because it exists.
