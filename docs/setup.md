# Setup and execution

Tested on macOS with Docker Desktop. Linux works the same way.

## Prerequisites

- Docker with Compose v2
- `bash`, `curl`, `jq`, `openssl`
- A Gemini API key from [AI Studio](https://aistudio.google.com) on a project with billing enabled. A run costs about $0.08; make sure the project's prepaid balance and monthly spend cap allow a few dollars.

## 1. Configure

```bash
git clone <this repo> tekion-assignment && cd tekion-assignment
scripts/init-env.sh
```

`init-env.sh` creates `.env` (mode 600) and generates `N8N_ENCRYPTION_KEY` and `WEBHOOK_API_KEY` without printing them. Open `.env` and set:

```
GEMINI_API_KEY=your-key
```

Optional: `N8N_HOST_PORT` (default 5678) and `GENERIC_TIMEZONE` (default Asia/Kolkata).

Check the key and the models before going further (prints only status, latency and token counts; writes test images to `outputs/check/`):

```bash
scripts/check-gemini.sh
```

## 2. Start n8n

```bash
docker compose up -d
docker compose ps        # wait for "healthy"
```

This runs n8n 2.47.7 (pinned) with:
- `config/` mounted read-only, `outputs/` mounted read-write, `workflows/` mounted for import
- file access restricted to `/home/node/.n8n-files`
- the Gemini key **not** passed into the container (it only lives in n8n's encrypted credential store)

## 3. Create the owner account

Open http://localhost:5678 and create the owner account (local only, any email). Imported workflows and credentials land in this account's project.

## 4. Install the workflows

```bash
scripts/setup.sh
```

It:
1. imports two credentials with fixed IDs (`Gemini API`, `Content API key (X-API-Key)`) from `.env`, through a temporary file that is deleted afterwards,
2. imports the seven workflows from `workflows/`,
3. publishes them in dependency order (gateways and error handler first, intake last),
4. restarts n8n so webhooks and the form register,
5. creates the Data Tables `content_runs` and `content_errors` through `POST /webhook/content/setup`.

Re-running it is safe. `scripts/setup.sh workflows` re-imports and re-publishes only the workflows.

## 5. Generate content

**Form**: open http://localhost:5678/form/content-form, enter a topic, press Generate. The result page shows the article, image, status, timings, cost and diversity choices.

**API** (helper script, keeps the key out of the process list):

```bash
scripts/generate.sh "How to launch a digital retailing program at a car dealership" guide
scripts/generate.sh "Dealerships should publish transparent prices" auto '{"audience": "general managers", "image_aspect": "1:1"}'
FULL=1 scripts/generate.sh "EV service revenue" trend_analysis     # whole JSON incl. the article
```

**API** (plain curl):

```bash
source .env
curl -X POST http://localhost:5678/webhook/content \
  -H "X-API-Key: $WEBHOOK_API_KEY" -H 'Content-Type: application/json' \
  -d '{"topic": "Ways dealerships can cut used-car reconditioning time", "style": "listicle"}'
```

**Batch**:

```bash
scripts/run-batch.sh samples/topics.json           # 202 + polling; prints the summary and the batch id
scripts/collect-samples.sh <batch_id>              # copies the runs into samples/ and rebuilds samples/README.md
```

**Fault injection** (shows retries, fallbacks and the error workflow):

```bash
scripts/generate.sh "Fallback demo topic" auto '{"simulate": {"text_primary_fail": true, "image_primary_fail": true}}'
scripts/generate.sh "Crash demo topic" auto '{"simulate": {"fatal": true}}'     # 500, logged in content_errors
```

See [api.md](api.md) for every field and response.

## 6. Where to look

| What | Where |
|---|---|
| Generated files | `outputs/<run_id>.md`, `.jpg`, `.json` |
| Batch summaries | `outputs/<batch_id>.json` |
| Run log (diversity memory) | n8n → Overview → Data tables → `content_runs` |
| Error log | Data table `content_errors` |
| Step-by-step execution | n8n → Executions (each gateway call is its own sub-execution) |

## 7. Changing behaviour

- **Models, timeouts, prices, styles, pools, limits, quality rules, time budget**: edit `config/content-config.json`. It is read on every run, so no restart or re-import is needed.
- **Workflows**: edit in the n8n editor, publish, then run `scripts/export.sh` to write clean JSON back to `workflows/` (it also checks that no secret leaked into the files). Sub-workflows run their *published* version in production, so publish after every change.

## 8. Troubleshooting

| Symptom | Fix |
|---|---|
| `502` with "prepayment credits are depleted" or "exceeded its monthly spending cap" | Top up or raise the cap in AI Studio for the project that owns the key |
| `403 Authorization data is wrong!` | Use the `WEBHOOK_API_KEY` from `.env` in the `X-API-Key` header |
| `404` on `/webhook/...` right after start | n8n is still registering webhooks; wait a few seconds, or re-run `scripts/setup.sh workflows` |
| Port 5678 in use | Set `N8N_HOST_PORT` in `.env`, then `docker compose up -d` and `scripts/setup.sh workflows` |
| Start from scratch | `docker compose down -v` (deletes executions, Data Tables and credentials), then steps 2–4 |

## 9. Verified fresh install

The full sequence above (clone, `init-env.sh`, `docker compose up -d`, `setup.sh`) was rehearsed from a fresh clone on a separate Compose project and port: credentials and workflows imported, publishing order resolved, Data Tables created, the form served, and the API answered 403 for a wrong key, 400 for invalid input, 404/400 for unknown or malformed batch ids, and 502 with a clear reason for a real run (the Gemini spend cap had been reached at that moment, which exercised the failure path end to end).
