# API reference

Base URL: `http://localhost:5678` (change the port with `N8N_HOST_PORT`).
Authentication: header `X-API-Key: <WEBHOOK_API_KEY from .env>` on every endpoint except the form.

## Generate one piece: `POST /webhook/content`

Synchronous: the response arrives when the run finishes (typically 40–70 s, always under 5 minutes).

| Field | Type | Default | Rules |
|---|---|---|---|
| `topic` | string | required | 3–200 characters |
| `style` | string | `auto` | `auto`, `article`, `guide`, `opinion`, `trend_analysis`, `listicle` (`auto` lets the diversity planner choose) |
| `audience` | string | planner picks one | up to 100 characters |
| `tone` | string | the format's default tone | up to 50 characters |
| `word_target` | integer | 650 | 550–750 (the quality gate always enforces 500–800) |
| `image_aspect` | string | `16:9` | `16:9`, `1:1`, `4:5` |
| `include_image_base64` | boolean | `false` | adds `image.base64` and `image.mime_type` to the response |
| `simulate` | object | `{}` | fault injection: `text_primary_fail`, `image_primary_fail`, `fatal` (booleans) |

Optional header `X-Request-Id` is stored in the run metadata.

```bash
curl -X POST http://localhost:5678/webhook/content \
  -H "X-API-Key: $WEBHOOK_API_KEY" -H 'Content-Type: application/json' \
  -d '{"topic": "Ways dealerships can cut used-car reconditioning time", "style": "listicle"}'
```

Response `200` (abridged, from [sample 05](../samples/README.md)):

```json
{
  "status": "success",
  "run_id": "cg-20261117-130732-q9fze4",
  "topic": "Ways dealerships can cut used-car reconditioning time",
  "style": "listicle",
  "title": "5 Ways to Cut Used-Car Reconditioning Time and Boost ROI",
  "slug": "5-ways-to-cut-used-car-reconditioning-time-and-boost-roi",
  "meta_description": "Cut used-car reconditioning time with five practical tactics...",
  "word_count": 542,
  "article_markdown": "# 5 Ways to Cut Used-Car Reconditioning Time and Boost ROI\n\n...",
  "image": {
    "status": "generated",
    "path": "outputs/cg-20261117-130732-q9fze4.jpg",
    "model": "gemini-nano-banana-2.1",
    "fallback_used": false,
    "aspect_ratio": "16:9",
    "prompt": "Create an editorial photography image to accompany an article titled ...",
    "error": null
  },
  "diversity": {
    "style_source": "requested",
    "angle": "roi",
    "hook": "analogy",
    "audience": "practitioners who do the work every day",
    "visual": { "style": "editorial photography", "composition": "wide establishing shot", "palette": "soft pastels", "lighting": "moody low-key light" },
    "history_considered": 7,
    "related_runs": 0,
    "novelty_score": 1,
    "seed": 4185422467
  },
  "quality": {
    "passed": true,
    "revisions": 0,
    "checks": [{ "id": "word_count", "passed": true, "detail": "542 words (allowed 500-800)" }, "..."],
    "rounds": [{ "draft": 0, "word_count": 542, "failed": [] }]
  },
  "warnings": [],
  "models": { "text": "gemini-4-hydrogen", "image": "gemini-nano-banana-2.1", "fallback_used": false },
  "cost_usd": 0.085,
  "timings_ms": { "brief": 12524, "write": 13707, "image": 15354, "total": 41796 },
  "files": {
    "article": "outputs/cg-20261117-130732-q9fze4.md",
    "image": "outputs/cg-20261117-130732-q9fze4.jpg",
    "metadata": "outputs/cg-20261117-130732-q9fze4.json"
  },
  "error": null
}
```

`status` is `success`, `partial` (no image) or `needs_review` (a quality check still fails; see `warnings`). The `X-Run-Id` response header repeats `run_id`.

Other responses:

| Code | Body | When |
|---|---|---|
| 400 | `{"status": "rejected", "run_id", "errors": [...], "message"}` | Invalid input; every problem is listed |
| 403 | n8n's `Authorization data is wrong!` | Missing or wrong `X-API-Key` |
| 502 | Same shape as 200 with `status: "failed"` and `error` | Both text models failed (quota, outage...) |
| 500 / 504 | `{"status": "error", "error", "detail", "execution_id"}` | Unexpected workflow error or time limit; also logged in `content_errors` |

## Generate many: `POST /webhook/content/batch`

Asynchronous. Answers `202` at once, then runs the topics through `POST /webhook/content` in waves of `concurrency` (requests in a wave start 2 s apart).

```json
{
  "concurrency": 3,
  "defaults": { "image_aspect": "16:9" },
  "topics": [
    "Plain topic string",
    { "topic": "How to launch a digital retailing program at a car dealership", "style": "guide" }
  ]
}
```

Limits: 1–50 topics, concurrency 1–5 (default 3). `defaults` are merged into every topic object.

Response `202`:

```json
{
  "batch_id": "batch-20261117-130643-roclg3",
  "status": "accepted",
  "count": 7,
  "concurrency": 3,
  "status_url": "http://localhost:5678/webhook/content/batch-status?batch_id=batch-20261117-130643-roclg3",
  "summary_path": "outputs/batch-20261117-130643-roclg3.json"
}
```

`400` with `errors[]` if the batch itself is invalid. Invalid individual topics do not fail the batch; they show up as `rejected` items.

## Batch status: `GET /webhook/content/batch-status?batch_id=...`

Returns `{"status": "running", ...}` while the batch runs, then the full summary:

```json
{
  "batch_id": "batch-20261117-130643-roclg3",
  "status": "completed",
  "wall_time_ms": 157607,
  "count": 7,
  "concurrency": 3,
  "by_status": { "success": 7 },
  "runs_within_5_min": 7,
  "latency_ms": { "p50": 45114, "p95": 63852, "max": 63852 },
  "cost_usd_total": 0.5476,
  "items": [{ "index": 1, "topic": "...", "http_status": 200, "status": "success", "run_id": "...", "title": "...", "duration_ms": 37192, "cost_usd": 0.0699 }]
}
```

`404` for an unknown id, `400` for a malformed one.

## Web form: `/form/content-form`

Same fields as the API (topic, style, audience, tone, image shape). After about a minute it shows the article with its image, the run status, timings, cost, models and the diversity choices.

## Setup: `POST /webhook/content/setup`

Used by `scripts/setup.sh` to create the Data Tables. Safe to call again.
