#!/usr/bin/env bash
# Generate one piece of content through the authenticated API.
#
#   scripts/generate.sh "topic" [style] [extra-json]
#
# Examples:
#   scripts/generate.sh "How AI is changing the dealership service lane"
#   scripts/generate.sh "EV charging at dealerships" guide '{"audience":"service managers"}'
#   scripts/generate.sh "EV charging at dealerships" auto '{"simulate":{"text_primary_fail":true}}'
#
# Prints a summary of the JSON response plus the HTTP status and total time.
# Set FULL=1 to print the whole response, including the article Markdown.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "Missing .env. Run scripts/init-env.sh first." >&2; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a
[[ -n "${WEBHOOK_API_KEY:-}" ]] || { echo "WEBHOOK_API_KEY is empty in .env" >&2; exit 1; }

topic="${1:?Usage: scripts/generate.sh \"topic\" [style] [extra-json]}"
style="${2:-auto}"
extra="${3:-}"
[[ -n "$extra" ]] || extra='{}'
port="${N8N_HOST_PORT:-5678}"

body=$(jq -n --arg topic "$topic" --arg style "$style" --argjson extra "$extra" \
  '{topic: $topic, style: $style} + $extra')

response=$(mktemp)
trap 'rm -f "$response"' EXIT

# The API key is passed through a file descriptor so it never appears in the process list.
meta=$(curl -sS -o "$response" -w '%{http_code} %{time_total}' \
  -X POST "http://localhost:${port}/webhook/content" \
  -H 'Content-Type: application/json' \
  -H @<(printf 'X-API-Key: %s\n' "$WEBHOOK_API_KEY") \
  --data-binary "$body")

if [[ "${FULL:-0}" == "1" ]]; then
  jq . "$response"
else
  jq '{status, run_id, style, title, word_count,
       image: (.image | if . then {status, model, fallback_used, path} else null end),
       diversity: (.diversity | if . then {style_source, angle, hook, audience, visual, related_runs, novelty_score} else null end),
       quality: (.quality | if . then {passed, revisions} else null end),
       warnings, models, cost_usd, timings_ms, files, error, errors, detail, execution_id}
      | with_entries(select(.value != null))' "$response" 2>/dev/null || cat "$response"
fi
echo "HTTP ${meta% *} in ${meta#* }s"
