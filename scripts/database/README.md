# Safe production schema extraction

This directory provides a local macOS workflow to generate a **review candidate only** for the ApplianceIQ production public schema. It never applies SQL, runs migrations, or authorizes a staging or production change.

## Prerequisites

- macOS with Homebrew and the Keychain `security` command.
- PostgreSQL client tools only (do not install or start a PostgreSQL server):

  ```bash
  brew install libpq
  ```

- Make the Homebrew `libpq` client directory available in the current shell. Do not modify shell startup files automatically:

  ```bash
  export PATH="$(brew --prefix libpq)/bin:$PATH"
  ```

- Store the production database password interactively in the current macOS account's Keychain. The prompt accepts the password without placing it in a script, file, or terminal history:

  ```bash
  security add-generic-password \
    -a "$USER" \
    -s "applianceiq-production-db-password" \
    -w
  ```

## Run

From the repository root, after the approved candidate-generation task has been authorized:

```bash
./scripts/database/dump-production-schema.sh
```

The default output is `docs/security/migration-001/staging-baseline/generated/applianceiq_schema_baseline_candidate.sql`, deliberately outside `supabase/migrations`.

## Target protections

`verify-dump-target.sh` accepts only production project reference `fumwwhyozeouoqscolke`. It rejects staging reference `okdtorbgerhukzalaxqq`, empty values, and all unknown references. This is authorization for read-only schema extraction only, never SQL execution.

The extraction script defaults to direct production host `db.fumwwhyozeouoqscolke.supabase.co`. A Supavisor session-pooler host may be supplied through `APPLIANCEIQ_PRODUCTION_DB_HOST`; it must be a `*.pooler.supabase.com` hostname. The staging host is rejected.

## Schema-only and credential handling

The script uses `pg_dump --schema-only --schema=public --no-owner --no-privileges`, so it requests public structural DDL without row data, roles, ownership, database creation, or grants. It retrieves the password only at runtime from Keychain, disables shell tracing, writes no credential to disk, and unsets credential variables in its cleanup trap.

The dump is first written to a temporary file. Before moving it into place, the script rejects top-level data/role/database/password statements and scans for credential-like values, private keys, credential-bearing PostgreSQL URLs, the Keychain password, and staging connection references. Function bodies may contain application DML and require the separate approved security review; the script does not execute them.

## Prohibited uses

Do not run this script against staging, use it to apply the candidate, place its output in `supabase/migrations`, or treat its output as implementation approval. It does not authorize Migration 001, historical migrations, application deployment, production data copying, or a production mutation.

## Troubleshooting

- If `pg_dump` is unavailable, verify the `libpq` installation and current-shell PATH command above.
- If the Keychain lookup fails, add or confirm the item with the interactive command above; never put the password in an environment file or source code.
- If a pooler is required, set only the host through `APPLIANCEIQ_PRODUCTION_DB_HOST`; do not supply a credential-bearing URL.
- If a safety scan fails, do not use the output. Review and remediate the reported category before any later candidate-validation task.

Output generation remains review-only. A separate human approval is required before any candidate can be applied to the empty staging project.
