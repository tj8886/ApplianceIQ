#!/usr/bin/env bash
# Restore rehearsal only: no linked project or remote connection is used.
set -euo pipefail
umask 077
export PATH="/Applications/Docker.app/Contents/Resources/bin:$HOME/.docker/bin:$PATH"
backup_root="${1:-$HOME/applianceiq-database-backups-20261004-114137}"
project="applianceiq-canada-restore-20261004"
rehearsal_dir="$HOME/$project"
db="supabase_db_$project"
command -v node >/dev/null
command -v npx >/dev/null
docker info >/dev/null
for file in roles.sql schema.sql data.sql history_schema.sql history_data.sql; do
  test -s "$backup_root/Canada/$file"
done
cd "$backup_root"
shasum -a 256 -c SHA256SUMS
if test -e "$rehearsal_dir"; then
  echo "The Canada rehearsal directory already exists. Stop here and report this message."
  exit 1
fi
mkdir "$rehearsal_dir"
cd "$rehearsal_dir"
npx --yes supabase@2.119.0 --agent no init
# Separate host ports from the existing US rehearsal. Node is already installed.
node <<'JS'
const fs = require('node:fs');
const file = 'supabase/config.toml';
const original = fs.readFileSync(file, 'utf8');
const updated = original.replace(/^(\s*(?:port|shadow_port)\s*=\s*)543(\d\d)\b/gm, '$1553$2');
if (updated === original || !/^port = 55322$/m.test(updated)) {
  throw new Error('Could not assign separate Canada database port');
}
fs.writeFileSync(file, updated);
JS
caffeinate -i npx --yes supabase@2.119.0 --agent no start \
  --exclude edge-runtime,realtime,imgproxy,studio,postgres-meta,logflare,vector,supavisor

# Stop only the new Canada's services. Preserve both database containers.
for service in storage rest inbucket auth kong; do
  docker stop "supabase_${service}_${project}"
done
for network in $(docker inspect --format '{{range $name, $details := .NetworkSettings.Networks}}{{$name}} {{end}}' "$db"); do
  docker network disconnect "$network" "$db"
done
test "$(docker inspect --format '{{json .NetworkSettings.Networks}}' "$db")" = "{}"
docker exec "$db" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 \
  -c "ALTER SYSTEM SET cron.launch_active_jobs = off;" \
  -c "SELECT pg_reload_conf();"
test "$(docker exec "$db" psql -X -U supabase_admin -d postgres -Atc 'SHOW cron.launch_active_jobs;')" = "off"
docker cp "$backup_root/Canada/roles.sql" "$db:/tmp/rehearsal-roles.sql"
docker cp "$backup_root/Canada/schema.sql" "$db:/tmp/rehearsal-schema.sql"
docker cp "$backup_root/Canada/data.sql" "$db:/tmp/rehearsal-data.sql"
echo "Restoring Canada backup into its separate, isolated local database."
if caffeinate -i docker exec "$db" psql -X -U supabase_admin -d postgres \
  --single-transaction --variable ON_ERROR_STOP=1 \
  --file /tmp/rehearsal-roles.sql --file /tmp/rehearsal-schema.sql \
  --command 'SET session_replication_role = replica;' \
  --file /tmp/rehearsal-data.sql > "$backup_root/Canada/restore-test.log" 2>&1; then
  echo "Canada restore completed successfully."
else
  echo "Canada restore failed and rolled back. First error:"
  awk '/ERROR:|FATAL:/{print; exit}' "$backup_root/Canada/restore-test.log"
  exit 1
fi
docker exec "$db" psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -c "
SELECT 'auth.users' AS table_name,count(*) AS rows FROM auth.users
UNION ALL SELECT 'public.products',count(*) FROM public.products
UNION ALL SELECT 'public.profiles',count(*) FROM public.profiles
UNION ALL SELECT 'public.speciq_packages',count(*) FROM public.speciq_packages
UNION ALL SELECT 'public.aiq_products',count(*) FROM public.aiq_products
UNION ALL SELECT 'public.pim_retailer_prices',count(*) FROM public.pim_retailer_prices
ORDER BY table_name;"
