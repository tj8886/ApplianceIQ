# Migration Workflow

**Applies to**: Supabase project `fumwwhyozeouoqscolke` (ApplianceIQ)

## Rules

1. Every production schema change MUST have a matching committed migration file in `supabase/migrations/`.
2. Every deployed Edge Function MUST have its source in `supabase/functions/`.
3. Migration filenames MUST use the format `YYYYMMDDHHMMSS_descriptive_name.sql`.
4. Timestamps MUST match the production `supabase_migrations.schema_migrations` version exactly.
5. Never apply a migration to production without committing it to the repository first.
6. Never modify or delete an already-applied migration file.

## Creating a New Migration

1. Write the SQL in a new file: `supabase/migrations/YYYYMMDDHHMMSS_your_change.sql`
2. Use idempotent patterns where possible (`IF NOT EXISTS`, `CREATE OR REPLACE`).
3. Test locally or on a Supabase branch before applying to production.
4. Apply to production via `supabase db push` or the MCP `apply_migration` tool.
5. Verify the version number in production matches your filename.
6. Commit and push.

## Deploying Edge Functions

1. Write or update the source in `supabase/functions/<function-name>/index.ts`.
2. Shared modules go in `supabase/functions/_shared/`.
3. Deploy: `supabase functions deploy <name> --project-ref fumwwhyozeouoqscolke`
4. Commit and push.

## Baseline Stub Files

Migration files marked "PRODUCTION BASELINE STUB" are placeholders that document what was applied to production interactively. They contain no executable SQL. They exist to keep the migration version history in the repo aligned with production's `supabase_migrations.schema_migrations` table.

Do not delete or modify these stubs. If the objects they document need changes, create a new forward migration.

## Rollback

Supabase migrations are forward-only. To undo a change, write a new corrective migration. Never edit or remove an applied migration.

## CI Checks

The GitHub Actions workflow validates:
- Migration files are timestamp-ordered
- CRM, Academy, and Spec IQ inline JS syntax is valid
- Academy HTML is well-formed

Future additions should include:
- Migration file count matches production (via Supabase MCP API)
- Edge function directories match deployed function list
