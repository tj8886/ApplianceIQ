#!/usr/bin/env bash
set -euo pipefail
umask 077

# Run on an owner-controlled machine. Credentials stay in the CLI's secure
# authentication flow; do not paste them into chat or put them in this script.
# This exports databases only. Storage file bytes need a separate backup.
command -v npx >/dev/null || { echo 'Node.js and npm are required.' >&2; exit 1; }
command -v docker >/dev/null || { echo 'A running Docker-compatible runtime is required by db dump.' >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo 'Start your Docker-compatible runtime first.' >&2; exit 1; }
backup_root="${1:-$PWD/applianceiq-database-backups-$(date +%Y%m%d-%H%M%S)}"
if [[ -e "$backup_root" ]]; then
  echo 'Choose a new output directory; existing backups will not be overwritten.' >&2
  exit 1
fi
mkdir -p "$backup_root"
backup_root="$(cd "$backup_root" && pwd)"
cli=(npx --yes supabase@2.119.0 --agent no --output-format text)
"${cli[@]}" --version
if ! "${cli[@]}" whoami >/dev/null 2>&1; then
  "${cli[@]}" login --name applianceiq-owner-export
fi

for entry in US:jdxslqmgjsuzoisuhvlc Canada:fumwwhyozeouoqscolke; do
  label="${entry%%:*}"
  project_ref="${entry#*:}"
  output_dir="$backup_root/$label"
  mkdir -p "$output_dir"
  printf 'Exporting %s database (read-only)\n' "$label"
  "${cli[@]}" db dump --project-ref "$project_ref" --role-only --file "$output_dir/roles.sql"
  "${cli[@]}" db dump --project-ref "$project_ref" --file "$output_dir/schema.sql"
  "${cli[@]}" db dump --project-ref "$project_ref" --data-only --use-copy --exclude storage.buckets_vectors,storage.vector_indexes --file "$output_dir/data.sql"
  "${cli[@]}" db dump --project-ref "$project_ref" --schema supabase_migrations --file "$output_dir/history_schema.sql"
  "${cli[@]}" db dump --project-ref "$project_ref" --schema supabase_migrations --data-only --use-copy --file "$output_dir/history_data.sql"
  for required in roles.sql schema.sql data.sql history_schema.sql history_data.sql; do
    [[ -s "$output_dir/$required" ]] || { echo "Empty export: $label/$required" >&2; exit 1; }
  done
done

cat > "$backup_root/README.txt" <<'TEXT'
Private database exports for ApplianceIQ consolidation. Contains sensitive data.
Keep private. Do not commit to GitHub or share publicly.
These exports have not been restored or verified as recoverable backups.
They do not include Storage file bytes, function source, auth configuration,
or a complete export of custom changes to managed auth/storage schemas.
Writes were not frozen: obtain final consistent deltas during cutover.
TEXT
if command -v shasum >/dev/null; then
  (cd "$backup_root" && shasum -a 256 US/*.sql Canada/*.sql > SHA256SUMS)
elif command -v sha256sum >/dev/null; then
  (cd "$backup_root" && sha256sum US/*.sql Canada/*.sql > SHA256SUMS)
fi
printf 'Database export files saved in %s\n' "$backup_root"
printf 'Do not switch production until restore and access tests pass.\n'
