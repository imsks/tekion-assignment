#!/usr/bin/env bash
# Checks the Gemini key and the models in config/content-config.json.
# Prints status, latency and token usage only; responses land in outputs/check/.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
: "${GEMINI_API_KEY:?Add GEMINI_API_KEY to .env}"

BASE="https://generativelanguage.googleapis.com/v1beta"
CONFIG=config/content-config.json
OUT=outputs/check
mkdir -p "$OUT"

TEXT_MODELS="${TEXT_MODELS:-$(jq -r '.models.text.primary + " " + .models.text.fallback' "$CONFIG")}"
IMAGE_MODELS="${IMAGE_MODELS:-$(jq -r '.models.image.primary + " " + .models.image.fallback' "$CONFIG")}"

# Writes the response body to $3 and prints "<http_code> <seconds>".
generate() {
  curl -sS -o "$3" -w '%{http_code} %{time_total}' --max-time 180 \
    -X POST "$BASE/models/$1:generateContent" \
    -H "x-goog-api-key: $GEMINI_API_KEY" -H 'Content-Type: application/json' -d "$2" || true
}

report() {
  local label=$1 result=$2 body=$3
  local code=${result%% *} secs=${result##* }
  if [[ "$code" == 200 ]]; then
    printf '  %-44s OK   %7ss  %s\n' "$label" "$secs" \
      "$(jq -c '.usageMetadata | {in: .promptTokenCount, out: .candidatesTokenCount, thoughts: .thoughtsTokenCount}' "$body")"
  else
    printf '  %-44s FAIL %7ss  HTTP %s %s\n' "$label" "$secs" "$code" \
      "$(jq -r '.error.message // empty' "$body" 2>/dev/null | head -c 240)"
  fi
}

echo "== Model availability"
curl -sS --max-time 30 "$BASE/models?pageSize=1000" -H "x-goog-api-key: $GEMINI_API_KEY" > "$OUT/models.json"
if jq -e '.error' "$OUT/models.json" >/dev/null; then
  echo "Key check failed: $(jq -r '.error.message' "$OUT/models.json")"
  exit 1
fi
for m in $TEXT_MODELS $IMAGE_MODELS; do
  if jq -e --arg n "models/$m" 'any(.models[]; .name == $n)' "$OUT/models.json" >/dev/null; then
    echo "  listed   $m"
  else
    echo "  MISSING  $m"
  fi
done

echo "== Text"
brief_body=$(jq -n '{
  contents: [{role: "user", parts: [{text: "Propose a title and a one-sentence angle for an article about AI in automotive retail."}]}],
  generationConfig: {
    responseMimeType: "application/json",
    responseJsonSchema: {type: "object", properties: {title: {type: "string"}, angle: {type: "string"}}, required: ["title", "angle"]}
  }
}')
article_prompt='Write a 650-word markdown article titled "How AI is reshaping the car-buying journey" with an H1 title and four H2 sections. Return only the article.'
for m in $TEXT_MODELS; do
  r=$(generate "$m" "$brief_body" "$OUT/$m.brief.json"); report "$m json-schema" "$r" "$OUT/$m.brief.json"
  for level in default low; do
    if [[ $level == default ]]; then
      body=$(jq -n --arg p "$article_prompt" '{contents: [{role: "user", parts: [{text: $p}]}]}')
    else
      body=$(jq -n --arg p "$article_prompt" --arg l "$level" '{contents: [{role: "user", parts: [{text: $p}]}], generationConfig: {thinkingConfig: {thinkingLevel: $l}}}')
    fi
    f="$OUT/$m.article-$level.json"
    r=$(generate "$m" "$body" "$f"); report "$m article (thinking $level)" "$r" "$f"
    if [[ ${r%% *} == 200 ]]; then
      echo "      words: $(jq -r '[.candidates[0].content.parts[]? | select(.thought != true) | .text // empty] | join("")' "$f" | wc -w | tr -d ' ')"
    fi
  done
done

echo "== Image (16:9)"
image_prompt='Editorial header image: a modern car dealership showroom at dusk with an electric SUV under soft studio lighting, wide shot. No text, no logos.'
for m in $IMAGE_MODELS; do
  for size in "$(jq -r '.models.image.image_size' "$CONFIG")" none; do
    if [[ $size == none ]]; then
      body=$(jq -n --arg p "$image_prompt" '{contents: [{parts: [{text: $p}]}], generationConfig: {responseModalities: ["IMAGE"], imageConfig: {aspectRatio: "16:9"}}}')
    else
      body=$(jq -n --arg p "$image_prompt" --arg s "$size" '{contents: [{parts: [{text: $p}]}], generationConfig: {responseModalities: ["IMAGE"], imageConfig: {aspectRatio: "16:9", imageSize: $s}}}')
    fi
    f="$OUT/$m.image-$size.json"
    r=$(generate "$m" "$body" "$f"); report "$m image (size $size)" "$r" "$f"
    if [[ ${r%% *} == 200 ]]; then
      mime=$(jq -r '[.candidates[0].content.parts[]? | select(.inlineData) | .inlineData.mimeType][0] // "none"' "$f")
      img="$OUT/$m-$size.${mime#image/}"
      jq -r '[.candidates[0].content.parts[]? | select(.inlineData) | .inlineData.data][0] // empty' "$f" | base64 -d > "$img"
      echo "      $mime $(sips -g pixelWidth -g pixelHeight "$img" 2>/dev/null | awk '/pixel/{printf "%s ", $2}')-> $img"
      break
    fi
  done
done
