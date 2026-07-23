#!/usr/bin/env bash
# Authorizes only a read-only, schema-only extraction target. It never runs SQL.
set -euo pipefail
set +x

readonly PRODUCTION_PROJECT_REF="fumwwhyozeouoqscolke"
readonly STAGING_PROJECT_REF="okdtorbgerhukzalaxqq"

if [[ "$#" -ne 1 || -z "${1:-}" ]]; then
  echo "Usage: $0 <project-reference>" >&2
  exit 64
fi

project_ref="$1"

if [[ "$project_ref" == "$STAGING_PROJECT_REF" ]]; then
  echo "Refusing staging project target. This tool permits production schema extraction only." >&2
  exit 65
fi

if [[ "$project_ref" != "$PRODUCTION_PROJECT_REF" ]]; then
  echo "Refusing unknown project target. This tool permits only the approved production project." >&2
  exit 65
fi

echo "Target authorized: ${PRODUCTION_PROJECT_REF} (read-only schema extraction only; SQL execution is not authorized)."
