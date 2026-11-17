#!/usr/bin/env bash
# Submit a batch of topics to the Batch Runner and wait until it finishes.
#
#   scripts/run-batch.sh [batch.json]      (default: samples/topics.json)
#
# The batch file looks like:
#   { "concurrency": 3, "defaults": { "image_aspect": "16:9" },
#     "topics": ["plain topic", { "topic": "...", "style": "guide" }] }
#
# Prints the batch summary and, on the last line, the batch id
# (pass it to scripts/collect-samples.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f .env ]] || { echo "Missing .env. Run scripts/init-env.sh first." >&2; exit 1; }
# shellcheck disable=SC1091
set -a; source .env; set +a
port="${N8N_HOST_PORT:-5678}"
file="${1:-samples/topics.json}"
[[ -f "$file" ]] || { echo "Batch file not found: $file" >&2; exit 1; }

# The API key is passed through a file descriptor so it never appears in the process list.
api() { curl -sS -H @<(printf 'X-API-Key: %s\n' "$WEBHOOK_API_KEY") "$@"; }

accepted=$(api -X POST "http://localhost:${port}/webhook/content/batch" \
  -H 'Content-Type: application/json' --data-binary @"$file")
batch_id=$(jq -r '.batch_id // empty' <<<"$accepted")
[[ -n "$batch_id" ]] || { echo "Batch rejected: $accepted" >&2; exit 1; }
echo "accepted $batch_id: $(jq -r '.count' <<<"$accepted") topics, concurrency $(jq -r '.concurrency' <<<"$accepted")"

started=$SECONDS
while :; do
  sleep 15
  status=$(api "http://localhost:${port}/webhook/content/batch-status?batch_id=${batch_id}")
  [[ "$(jq -r '.status // "unknown"' <<<"$status")" == "completed" ]] && break
  if (( SECONDS - started > 3600 )); then
    echo "Gave up waiting for $batch_id after 1 hour" >&2
    exit 1
  fi
  printf '  running for %ss\n' "$((SECONDS - started))"
done

jq '{batch_id, wall_time_ms, count, concurrency, by_status, runs_within_5_min, latency_ms, cost_usd_total}' <<<"$status"
echo "$batch_id"
