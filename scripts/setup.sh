#!/usr/bin/env bash
# Installs the project into the running n8n container.
# Usage: scripts/setup.sh [all|credentials|workflows]
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

n8n_cli() { docker compose exec -T n8n n8n "$@"; }

import_credentials() {
  : "${GEMINI_API_KEY:?Add GEMINI_API_KEY to .env}"
  : "${WEBHOOK_API_KEY:?Run scripts/init-env.sh first}"
  # Fixed IDs so imported workflows bind to these credentials automatically.
  jq -n '[
    {id: "CgGeminiApiKey01", name: "Gemini API", type: "googlePalmApi",
     data: {host: "https://generativelanguage.googleapis.com", apiKey: env.GEMINI_API_KEY}},
    {id: "CgWebhookApiKey1", name: "Content API key (X-API-Key)", type: "httpHeaderAuth",
     data: {name: "X-API-Key", value: env.WEBHOOK_API_KEY}}
  ]' | docker compose exec -T n8n sh -c 'umask 077; cat > /tmp/cg-credentials.json'
  local status=0
  n8n_cli import:credentials --input=/tmp/cg-credentials.json || status=$?
  docker compose exec -T n8n rm -f /tmp/cg-credentials.json
  return "$status"
}

import_workflows() {
  if ! compgen -G "workflows/*.json" >/dev/null; then
    echo "No workflow files in workflows/, skipping import"
    return 0
  fi
  n8n_cli import:workflow --separate --input=/opt/workflows
}

run_setup_workflow() {
  local id
  id=$(jq -rs 'map(select(.name | startswith("CG · 00"))) | first | .id // empty' workflows/*.json 2>/dev/null || true)
  [[ -n "$id" ]] || return 0
  n8n_cli execute --id "$id"
}

publish_workflows() {
  local f
  for f in workflows/*.json; do
    [[ -e "$f" ]] || continue
    # Only workflows with a non-manual trigger can be published.
    if jq -e 'any(.nodes[]; .type | test("webhook|formTrigger|executeWorkflowTrigger|errorTrigger"; "i"))' "$f" >/dev/null; then
      n8n_cli publish:workflow --id="$(jq -r '.id' "$f")"
    fi
  done
}

case "${1:-all}" in
  credentials) import_credentials ;;
  workflows) import_workflows; run_setup_workflow; publish_workflows ;;
  all) import_credentials; import_workflows; run_setup_workflow; publish_workflows ;;
  *) echo "Usage: $0 [all|credentials|workflows]"; exit 1 ;;
esac
