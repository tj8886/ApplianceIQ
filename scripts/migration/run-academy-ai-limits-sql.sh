#!/usr/bin/env bash
# Applies the Academy AI limits migration to an empty Postgres and runs its
# rollback-only SQL checks. Uses $ACADEMY_AI_TEST_DATABASE_URL when set (CI
# service container); otherwise starts a throwaway local cluster.
# Never point this at Supabase: it loads stand-in schemas first.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
migration="$root/supabase/migrations/20261125170000_academy_ai_spending_limits.sql"
stubs="$root/scripts/migration/academy-ai-limits-local-stubs.sql"
checks="$root/scripts/migration/test-academy-ai-limits.sql"
run_psql(){ psql "$1" -X -q -v ON_ERROR_STOP=1 -f "$stubs" -f "$migration" -f "$checks"; }
if [ -n "${ACADEMY_AI_TEST_DATABASE_URL:-}" ]; then
  case "$ACADEMY_AI_TEST_DATABASE_URL" in *supabase.co*|*supabase.com*) echo 'Refusing to load stand-in schemas into Supabase'; exit 1;; esac
  run_psql "$ACADEMY_AI_TEST_DATABASE_URL"; exit 0
fi
bin=$(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)
[ -n "$bin" ] || bin=$(dirname "$(command -v initdb)")
dir=$(mktemp -d); port=$((20000 + RANDOM % 20000))
as_pg(){ if [ "$(id -u)" = 0 ]; then runuser -u postgres -- "$@"; else "$@"; fi; }
[ "$(id -u)" = 0 ] && chown postgres "$dir"
cleanup(){ as_pg "$bin/pg_ctl" -D "$dir/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$dir"; }
trap cleanup EXIT
as_pg "$bin/initdb" -D "$dir/data" -U postgres -A trust >/dev/null
as_pg "$bin/pg_ctl" -D "$dir/data" -o "-p $port -k $dir -c listen_addresses=''" -l "$dir/log" -w start >/dev/null
run_psql "postgresql://postgres@/postgres?host=$dir&port=$port"
