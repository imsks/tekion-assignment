#!/usr/bin/env bash
# Export the "CG · ..." workflows from the running n8n into workflows/ as clean, diffable JSON.
#
#   scripts/export.sh
#
# Keeps workflow and node IDs (sub-workflow calls and the error workflow reference them),
# drops instance-specific fields (versions, timestamps, sharing, pinned data) and checks
# that no secret from .env ended up in the exported files.
set -euo pipefail
cd "$(dirname "$0")/.."

container_dir=/tmp/cg-export
work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

docker compose exec -T n8n sh -c \
  "rm -rf $container_dir && n8n export:workflow --all --separate --pretty --output=$container_dir/ >/dev/null"
docker compose cp "n8n:$container_dir/." "$work_dir/" >/dev/null
docker compose exec -T n8n rm -rf "$container_dir"

mkdir -p workflows
rm -f workflows/*.json

count=0
for f in "$work_dir"/*.json; do
  name=$(jq -r '.name' "$f")
  [[ "$name" == "CG · "* ]] || continue
  [[ "$(jq -r '.isArchived // false' "$f")" == "false" ]] || continue
  slug=$(printf '%s' "${name#CG · }" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
  jq '{
        id, name, description,
        active: false,
        isArchived: false,
        nodes,
        connections,
        settings,
        nodeGroups: (.nodeGroups // []),
        pinData: {},
        staticData: null,
        tags: [],
        meta: {templateCredsSetupCompleted: true}
      }' "$f" > "workflows/cg-$slug.json"
  echo "exported workflows/cg-$slug.json"
  count=$((count + 1))
done
echo "$count workflows exported"

# Secret scan: the exported JSON must never contain a value from .env.
if [[ -f .env ]]; then
  (
    set -a; . ./.env; set +a
    leaked=0
    for var in GEMINI_API_KEY WEBHOOK_API_KEY N8N_ENCRYPTION_KEY; do
      value="${!var:-}"
      [[ -n "$value" ]] || continue
      if grep -rqF -- "$value" workflows/; then
        echo "SECRET FOUND in workflows/: $var" >&2
        leaked=1
      fi
    done
    [[ "$leaked" == 0 ]] && echo "secret scan: clean"
    exit "$leaked"
  )
fi
