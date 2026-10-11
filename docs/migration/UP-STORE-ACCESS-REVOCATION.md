# Individual store access — US migration
Verified 2026-10-11 against US project jdxslqmgjsuzoisuhvlc.

UP Settings > Team offers Revoke for each active assignment. Assign Store restores access. No assignment, CRM deal, floor visit, source record or file is deleted. Existing assignments default to active. Original assignment ID and created_at remain; private grant/revoke events retain actor and date, including after restoration. Repeated revocation creates no duplicate event.

Revocation requires an organization owner/admin; only an owner can change owner/admin assignments. An active shift or unfinished interaction must be ended/reassigned first. Another active assignment becomes primary when needed. Explicit denial overrides owner/admin and all-visibility store access; platform administrators retain their existing platform-wide override.

Updated shared location/context helpers, app entitlement store lists, store-scope peer membership, UP and CRM guards, and intelligence-event restrictive policy. Stored context at a revoked location falls back to an active assignment. CRM auto-location preserves an explicit deal location and uses only active assignments when filling a missing location.

Validated the existing complete UP workflow plus authenticated revoked-store reads, denied clock-in, retained second-store access, restore/retry and audit behavior. All 11 app bundles passed routing checks and generated UP scripts passed syntax checks. Fixtures roll back.

Remaining: signed-in browser walkthrough; SpecIQ project/package readers and SECURITY DEFINER operations currently have organization-level access and need a separate linked-deal store-scope audit before claiming revocation covers every product workflow. Organization-wide records with no store remain organization-wide. Remaining onboarding and labelled historical imports are separate work.

Supabase advisor baseline: security ERROR 8/WARN 41; performance WARN 61 unchanged. New private audit-table no-policy and unused-index INFO are expected; private table has RLS and no client grants. Existing advisor remediation: https://supabase.com/docs/guides/database/database-linter

