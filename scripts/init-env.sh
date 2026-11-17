#!/usr/bin/env bash
# Creates .env from .env.example and fills generated secrets without printing them.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  cp .env.example .env
  chmod 600 .env
  echo "Created .env"
fi

fill_if_empty() {
  local key="$1" value="$2"
  if grep -qE "^${key}=$" .env; then
    sed -i.bak "s|^${key}=$|${key}=${value}|" .env && rm -f .env.bak
    echo "Generated ${key}"
  fi
}

fill_if_empty N8N_ENCRYPTION_KEY "$(openssl rand -hex 32)"
fill_if_empty WEBHOOK_API_KEY "$(openssl rand -hex 24)"

mkdir -p outputs workflows

if grep -qE '^GEMINI_API_KEY=$' .env; then
  echo "Next: add your Gemini API key to .env (GEMINI_API_KEY=...)"
fi
