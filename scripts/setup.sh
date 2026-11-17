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
  # Publish in dependency order: a workflow is published only after every sub-workflow
  # it calls (and its error workflow) is published, because n8n rejects it otherwise.
  local pending=() published=() f id deps dep ready progress
  for f in workflows/*.json; do
    [[ -e "$f" ]] || continue
    # Only workflows with a non-manual trigger can be published.
    if jq -e 'any(.nodes[]; .type | test("webhook|formTrigger|executeWorkflowTrigger|errorTrigger"; "i"))' "$f" >/dev/null; then
      pending+=("$f")
    fi
  done
  while ((${#pending[@]})); do
    progress=0
    local remaining=()
    for f in "${pending[@]}"; do
      id=$(jq -r '.id' "$f")
      deps=$(jq -r '[.nodes[] | select(.type == "n8n-nodes-base.executeWorkflow") | .parameters.workflowId.value]
                    + [.settings.errorWorkflow // empty] | unique | map(select(. != "'"$id"'")) | .[]' "$f")
      ready=1
      for dep in $deps; do
        [[ " ${published[*]-} " == *" $dep "* ]] || { ready=0; break; }
      done
      if ((ready)); then
        n8n_cli publish:workflow --id="$id"
        published+=("$id")
        progress=1
      else
        remaining+=("$f")
      fi
    done
    pending=("${remaining[@]+"${remaining[@]}"}")
    ((progress)) || { echo "Cannot resolve publish order for: ${pending[*]}" >&2; return 1; }
  done
}

restart_n8n() {
  # Published workflows register their webhooks and forms when n8n starts.
  docker compose restart n8n >/dev/null
  local port="${N8N_HOST_PORT:-5678}" i
  for i in $(seq 1 60); do
    if curl -fsS "http://localhost:${port}/healthz" >/dev/null 2>&1; then
      echo "n8n is ready at http://localhost:${port}"
      return 0
    fi
    sleep 2
  done
  echo "n8n did not become healthy in time; check: docker compose logs n8n" >&2
  return 1
}

print_next_steps() {
  local port="${N8N_HOST_PORT:-5678}"
  cat <<EOF

Setup complete.
  Editor:   http://localhost:${port}   (create the owner account on first visit)
  Form:     http://localhost:${port}/form/content-form
  API:      scripts/generate.sh "your topic" [style]
  Batch:    scripts/run-batch.sh samples/topics.json
EOF
}

case "${1:-all}" in
  credentials) import_credentials ;;
  workflows) import_workflows; run_setup_workflow; publish_workflows; restart_n8n ;;
  all) import_credentials; import_workflows; run_setup_workflow; publish_workflows; restart_n8n; print_next_steps ;;
  *) echo "Usage: $0 [all|credentials|workflows]"; exit 1 ;;
esac
