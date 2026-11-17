# AI Content Generation Workflow (n8n + Gemini)

Send a topic, get back a 500–800 word piece in one of five styles (article, how-to guide, opinion, trend analysis, listicle) plus a matching AI-generated image. Everything runs as n8n workflows on a local Docker instance, using Google Gemini for text and images.

> Work in progress: architecture, setup details and sample outputs are added as the build progresses.

## Quick start

1. `scripts/init-env.sh`, then add your Gemini API key to `.env`
2. `docker compose up -d`
3. Open http://localhost:5678 and create the owner account
