# AI Content Generation Workflow (n8n + Gemini)

Send a topic through an API, a web form or a batch request and get back a 500–800 word piece in one of five formats (article, how-to guide, opinion, trend analysis, listicle) plus a matching AI-generated image, in about a minute. Each run is planned against recent history, so a repeated topic gets a different angle, hook and visual direction (and format, when the style is `auto`) than the run before it. Everything runs as n8n workflows in Docker, with Google Gemini for text and images.

**Demo video:** [Link](https://drive.google.com/file/d/1iN_3SsqTeoDYxko40wbIneP25fT58UUZ/view?usp=sharing)

| Deliverable | Where |
|---|---|
| Workflow design, explanation, assumptions | [docs/architecture.md](docs/architecture.md) |
| Workflow export and source | [workflows/](workflows/) (n8n JSON), [config/content-config.json](config/content-config.json), [scripts/](scripts/) |
| Setup and execution instructions | [docs/setup.md](docs/setup.md), API reference in [docs/api.md](docs/api.md) |
| Sample outputs | [samples/](samples/README.md): 7 pieces on 6 topics, one per format plus a same-topic diversity pair |
| Demo video | link above |

## What it does

- **Three ways in**: authenticated JSON API (`POST /webhook/content`), an n8n web form that renders the result, and a batch API that returns `202` immediately and processes up to 50 topics with bounded concurrency.
- **Five formats**, each with its own structure, tone, rules, quality checks and preferred visual styles, all defined in one config file.
- **Diversity across runs**: a planner reads the last 50 runs and chooses format, angle, opening hook, audience, visual style, composition, palette and lighting, excluding what the previous run and the latest same-topic run used. A novelty gate regenerates the brief if its title is too close to a recent one.
- **Quality gate**: word count, structure, paragraph length, banned clichés, no links, and format-specific checks; failures turn into targeted revision instructions (up to two revisions).
- **Within 5 minutes**: one 280 s deadline is propagated to every model call. Measured: p50 45 s, p95 64 s; $0.07–0.10 per piece.
- **Resilient**: every model call retries once and falls back to a second model; image failure still delivers the article; unexpected errors are logged by an error workflow; faults can be injected on demand to demonstrate all of it.

## How it works

```mermaid
flowchart LR
  api[API] --> intake[CG · 01 Intake]
  form[Form] --> intake
  batch[Batch API] --> runner[CG · 03 Batch Runner] --> intake
  intake --> pipeline[CG · 02 Content Pipeline]
  pipeline --> text[CG · 10 Gemini Text]
  pipeline --> image[CG · 11 Gemini Image]
  pipeline --> store[("outputs/ and content_runs")]
  errors[CG · 04 Error Handler] --> errlog[(content_errors)]
```

The pipeline runs five stages, each a group on the n8n canvas: **validate & plan → brief → write & quality gate → illustrate → finalize & persist**. Model calls go through two gateway sub-workflows that own retries, fallback, timeouts, JSON parsing and cost tracking.

| Workflow | Purpose |
|---|---|
| CG · 00 Setup | Creates the Data Tables (idempotent) |
| CG · 01 Intake | API + form front doors, HTTP status mapping, HTML result page |
| CG · 02 Content Pipeline | Validation, diversity planning, brief, writing, quality gate, image, files, run log |
| CG · 03 Batch Runner | Bulk generation in waves, batch summary with latency percentiles and cost |
| CG · 04 Error Handler | Logs failed executions to `content_errors` |
| CG · 10 Gemini Text | Text gateway: primary/fallback model, retry, deadline-aware timeout, JSON schema output |
| CG · 11 Gemini Image | Image gateway: same pattern, 16:9 / 1:1 / 4:5 at 1K |

## Quick start

```bash
cp .env.example .env                # fill in N8N_ENCRYPTION_KEY, WEBHOOK_API_KEY, GEMINI_API_KEY
docker compose up -d                # n8n 2.47.7 on http://localhost:5678
# open http://localhost:5678 and create the owner account
scripts/setup.sh                    # credentials, workflows, publish, Data Tables
source .env && curl -X POST http://localhost:5678/webhook/content \
  -H "X-API-Key: $WEBHOOK_API_KEY" -H 'Content-Type: application/json' \
  -d '{"topic": "How to launch a digital retailing program at a car dealership", "style": "guide"}'
```

Or open http://localhost:5678/form/content-form. Full instructions and troubleshooting: [docs/setup.md](docs/setup.md).

## Screenshots
![1](assets/1.png)
![2](assets/2.png)
![3](assets/3.png)
![3](assets/4.png)

## Key design decisions

- **Gemini through HTTP Request nodes behind gateway sub-workflows.** The built-in nodes cannot set image aspect ratio and size, JSON schema output or request timeouts, and hide their own retries. The gateways keep that control in one place, with the API key still in n8n's encrypted credential store.
- **Deterministic logic in Code nodes, generation in the model.** Validation, diversity planning, quality checks and status decisions are plain code with explainable outputs; the model only plans, writes and draws.
- **Config over code.** Models, prices, timeouts, formats, pools, limits and quality rules live in `config/content-config.json`, read on every run.
- **The run log is also the diversity memory.** `content_runs` records every choice, so the planner, the novelty gate and an auditor all read the same data. Plans are reserved before generation so concurrent runs also diverge.
- **Graceful degradation over failure.** A missing image yields `partial`, failing checks yield `needs_review` with the reasons; only a missing article is a failure.
- **Synchronous API, asynchronous batch.** One run finishes well inside 5 minutes, so the API answers directly; bulk work is accepted with `202` and polled.

The path to large-scale operation (queue mode, Postgres, rate limiting, Gemini Batch API, object storage) is in [docs/architecture.md](docs/architecture.md#13-scaling-to-large-volumes).

## Assumptions

- Content is in English for a professional audience. The samples use automotive retail topics, but nothing in the pipeline is domain-specific.
- "500–800 words" counts the article body (headings included, title excluded). Each piece gets one image, 16:9 at 1K by default.
- The API is synchronous because runs finish well inside 5 minutes; bulk work goes through the asynchronous batch API.
- Output is stored on the local disk and in n8n Data Tables; publishing to a CMS is out of scope.
- There is no web search: the writer must not invent figures, quotes or sources and links are rejected, but facts are not otherwise verified.

The full list, with known limitations, is in [docs/architecture.md](docs/architecture.md#14-assumptions).

## Repository layout

```
config/content-config.json   models, prices, budget, formats, diversity pools, quality rules
workflows/                   exported n8n workflows (import with scripts/setup.sh)
scripts/                     setup (install into n8n), export (workflows back to clean JSON)
samples/                     generated sample outputs with a gallery README
docs/                        architecture, setup, API reference
outputs/                     generated files (git-ignored)
docker-compose.yml           pinned n8n service
```
