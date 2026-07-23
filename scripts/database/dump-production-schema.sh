#!/usr/bin/env bash
# Generates an unexecuted, schema-only review candidate. It never applies SQL.
set -euo pipefail
set +x
umask 077

readonly PRODUCTION_PROJECT_REF="fumwwhyozeouoqscolke"
readonly STAGING_PROJECT_REF="okdtorbgerhukzalaxqq"
readonly PRODUCTION_DB_HOST="db.fumwwhyozeouoqscolke.supabase.co"
readonly KEYCHAIN_SERVICE="applianceiq-production-db-password"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VERIFY_TARGET_SCRIPT="${SCRIPT_DIR}/verify-dump-target.sh"
OUTPUT_FILE="${REPOSITORY_ROOT}/docs/security/migration-001/staging-baseline/generated/applianceiq_schema_baseline_candidate.sql"
TEMP_FILE=""
DB_PASSWORD=""
PGPASSWORD=""

cleanup() {
  unset DB_PASSWORD PGPASSWORD
  if [[ -n "${TEMP_FILE}" && -f "${TEMP_FILE}" ]]; then
    rm -f -- "${TEMP_FILE}"
  fi
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "Schema extraction stopped: $1" >&2
  exit 1
}

[[ -x "${VERIFY_TARGET_SCRIPT}" ]] || fail "target-verification script is missing or not executable"
command -v pg_dump >/dev/null 2>&1 || fail "pg_dump is unavailable; install Homebrew libpq and add its bin directory to PATH"
command -v security >/dev/null 2>&1 || fail "macOS Keychain command 'security' is unavailable"

"${VERIFY_TARGET_SCRIPT}" "${PRODUCTION_PROJECT_REF}" >/dev/null

DB_HOST="${APPLIANCEIQ_PRODUCTION_DB_HOST:-${PRODUCTION_DB_HOST}}"
[[ -n "${DB_HOST}" ]] || fail "database host is empty"
[[ "${DB_HOST}" != "db.${STAGING_PROJECT_REF}.supabase.co" ]] || fail "staging host is not allowed"

if [[ "${DB_HOST}" != "${PRODUCTION_DB_HOST}" && ! "${DB_HOST}" =~ ^[A-Za-z0-9.-]+\.pooler\.supabase\.com$ ]]; then
  fail "host override must be the approved direct production host or a Supavisor pooler hostname"
fi

mkdir -p "$(dirname "${OUTPUT_FILE}")"
DB_PASSWORD="$(security find-generic-password -a "${USER}" -s "${KEYCHAIN_SERVICE}" -w 2>/dev/null)" \
  || fail "Keychain entry '${KEYCHAIN_SERVICE}' is absent for the current macOS account"
[[ -n "${DB_PASSWORD}" ]] || fail "Keychain returned an empty database password"

TEMP_FILE="$(mktemp "${OUTPUT_FILE}.XXXXXX.tmp")"
PGPASSWORD="${DB_PASSWORD}" pg_dump \
  --host="${DB_HOST}" \
  --port="${DB_PORT:-5432}" \
  --username="${DB_USER:-postgres}" \
  --dbname="${DB_NAME:-postgres}" \
  --schema-only \
  --schema=public \
  --no-owner \
  --no-privileges \
  --no-password \
  --file="${TEMP_FILE}"

[[ -s "${TEMP_FILE}" ]] || fail "pg_dump produced an empty schema candidate"

# Reject top-level data and cluster-management payloads. Function bodies may contain
# DML as application logic; those bodies are reviewed separately before any approval.
if grep -Eiq '^[[:space:]]*(INSERT[[:space:]]+INTO|UPDATE[[:space:]]+|DELETE[[:space:]]+FROM|COPY[[:space:]].*[[:space:]]+FROM[[:space:]]+(STDIN|[^;]+)|MERGE[[:space:]]+INTO|TRUNCATE[[:space:]]+|CREATE[[:space:]]+DATABASE|ALTER[[:space:]]+DATABASE|DROP[[:space:]]+DATABASE|CREATE[[:space:]]+ROLE|ALTER[[:space:]]+ROLE|DROP[[:space:]]+ROLE|.*[[:space:]]PASSWORD[[:space:]]+)' "${TEMP_FILE}"; then
  fail "safety scan found prohibited top-level data, database, role, or password statement"
fi

if grep -Eiq 'sb_(secret|publishable)_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]{20,}|postgres(ql)?://[^[:space:]]+@|-----BEGIN[[:space:]].*PRIVATE[[:space:]]+KEY-----' "${TEMP_FILE}"; then
  fail "safety scan found a credential-like value"
fi

if grep -Fq -- "${DB_PASSWORD}" "${TEMP_FILE}"; then
  fail "safety scan found the Keychain password in generated output"
fi

if grep -Eiq "^[[:space:]]*(\\\\connect|CONNECT)[^;]*${STAGING_PROJECT_REF}" "${TEMP_FILE}"; then
  fail "safety scan found a staging project reference in an executable connection statement"
fi

mv -- "${TEMP_FILE}" "${OUTPUT_FILE}"
TEMP_FILE=""

file_size="$(stat -f '%z' "${OUTPUT_FILE}")"
echo "Target project: ${PRODUCTION_PROJECT_REF}"
echo "Target host: ${DB_HOST}"
echo "Output path: ${OUTPUT_FILE}"
echo "File size: ${file_size} bytes"
echo "Statement safety result: passed (schema-only candidate; not executed)"
