#!/bin/bash
# Classify unprocessed Twitter Insights entries and route to workflow databases.
# Multi-label: a bookmark can route to multiple destination DBs (primary + secondary workflows).
# Also writes a stub to the personal-kb wiki for content_create routes and appends to an audit log.
#
# Usage: ./classify-and-route.sh
# Requires: NOTION_API_KEY, ANTHROPIC_API_KEY, TWITTER_INSIGHTS_DB_ID, destination DB IDs
# Optional: PERSONAL_KB_PATH, CLASSIFICATION_LOG_PATH, WIKI_GIT_AUTOCOMMIT

set -e

NOTION_API_KEY="${NOTION_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
TWITTER_INSIGHTS_DB_ID="${TWITTER_INSIGHTS_DB_ID:-}"
LYRA_BACKLOG_DB_ID="${LYRA_BACKLOG_DB_ID:-}"
CLAUDE_SETUP_DB_ID="${CLAUDE_SETUP_DB_ID:-}"
TOOL_EVAL_DB_ID="${TOOL_EVAL_DB_ID:-}"
CONTENT_TOPIC_POOL_DB_ID="${CONTENT_TOPIC_POOL_DB_ID:-${CONTENT_IDEAS_DB_ID:-}}"

if [[ -z "$NOTION_API_KEY" || -z "$ANTHROPIC_API_KEY" || -z "$TWITTER_INSIGHTS_DB_ID" ]]; then
  echo "Missing required env vars: NOTION_API_KEY, ANTHROPIC_API_KEY, TWITTER_INSIGHTS_DB_ID" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXEMPLARS_FILE="${EXEMPLARS_FILE:-$REPO_ROOT/config/classifier-exemplars.json}"
CLASSIFICATION_LOG_PATH="${CLASSIFICATION_LOG_PATH:-$REPO_ROOT/logs/classification-log.csv}"
WIKI_WRITER="$SCRIPT_DIR/write-bookmark-to-wiki.sh"

mkdir -p "$(dirname "$CLASSIFICATION_LOG_PATH")"
if [[ ! -f "$CLASSIFICATION_LOG_PATH" ]]; then
  echo "timestamp,page_id,tweet_url,title,primary_workflow,secondary_workflows,confidence,rationale,wiki_stub,routed_to" > "$CLASSIFICATION_LOG_PATH"
fi

echo "=== Classify & Route: $(date) ==="

# ---------- Build classifier prompt with exemplars ----------
EXEMPLARS_BLOCK=""
if [[ -f "$EXEMPLARS_FILE" ]]; then
  EXEMPLARS_BLOCK=$(jq -r '.exemplars[] | "Tweet: \(.tweet)\nOutput: {\"primary_workflow\": \"\(.primary_workflow)\", \"secondary_workflows\": \(.secondary_workflows | tojson), \"confidence\": \"High\", \"rationale\": \"\(.rationale)\"}\n"' "$EXEMPLARS_FILE" 2>/dev/null || echo "")
fi

read -r -d '' SYSTEM_PROMPT <<'SYS' || true
You classify tweet bookmarks for Akash Kedia into workflow routes so they can be auto-filed in Notion and the personal wiki.

Akash's voice and focus:
- Technical founder, product-minded engineer, based in Germany
- Builds Lyra (personal AI assistant on Hetzner), runs Claude Code/Cursor setups
- Writes contrarian, teachable, builder-first content — hooks, concrete examples, honest takes
- Currently: job hunting, building MVPs, evaluating AI tooling, publishing on AI/agents/dev workflows

Routing rules — MULTI-LABEL. A bookmark can belong to multiple workflows. Always return a primary (highest-confidence) and a secondary_workflows array (can be empty).

Categories:
- lyra_capability: Improves Lyra, OpenClaw, Telegram bot, home automation. Concrete capability idea.
- work_claude_setup: Improves Claude Code / Cursor / MCP setup usable at work. Any MCP server, repo rule, agent config.
- personal_claude_setup: Personal dev-env Claude tweaks (prompts, aliases, launchd, routines).
- work_productivity: Non-AI work habits, processes, leadership.
- content_create: Worth a post / thread / article. Be GENEROUS here — if the tweet is a hook, a contrarian take, a teaching moment, a behind-the-scenes build story, a candid career/market take, a 'how I do X' angle, or directly adjacent to Lyra/agents/dev workflows → include it. Default-lean toward content_create when in doubt and the topic matches Akash's voice.
- research_read_later: Pure long-form reading with no actionable angle and no content hook.
- tool_eval: A specific tool/vendor/product worth evaluating for adoption.
- market_competitor: Market intel, competitor moves, industry signal.

Heuristics for content_create (add as primary OR secondary whenever any apply):
- Has a hook, a contrarian take, or a surprising claim
- Is about Lyra-adjacent topics (agents, memory, MCP, personal AI, prompt engineering)
- Is a 'how I built X' or 'here's the architecture' story
- Candid market/job/career angle that Akash can comment on
- Teaches a concept that a builder audience would save

Output: STRICT JSON only, no prose.
{"primary_workflow": "<category>", "secondary_workflows": ["<category>", ...], "confidence": "High|Medium|Low", "rationale": "<one sentence>"}
SYS

# ---------- Step 1: fetch unprocessed ----------
echo "Fetching unprocessed bookmarks..."
UNPROCESSED=$(curl -s -X POST "https://api.notion.com/v1/databases/${TWITTER_INSIGHTS_DB_ID}/query" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {
      "and": [
        {"property": "Needs review", "checkbox": {"equals": true}},
        {"property": "Status", "select": {"equals": "Draft"}}
      ]
    },
    "page_size": 20
  }')

COUNT=$(echo "$UNPROCESSED" | jq '.results | length')
echo "Found $COUNT unprocessed bookmarks"
if (( COUNT == 0 )); then
  echo "Nothing to process"
  exit 0
fi

# ---------- Helpers ----------
csv_escape() { printf '"%s"' "$(echo "$1" | sed 's/"/""/g' | tr '\n' ' ')"; }

notion_query_dedup_content() {
  local db="$1" url="$2"
  curl -s -X POST "https://api.notion.com/v1/databases/${db}/query" \
    -H "Authorization: Bearer ${NOTION_API_KEY}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d "{\"filter\":{\"property\":\"Source Reference\",\"url\":{\"equals\":\"${url}\"}}}" \
    | jq '.results | length'
}
notion_query_dedup_source() {
  local db="$1" url="$2"
  curl -s -X POST "https://api.notion.com/v1/databases/${db}/query" \
    -H "Authorization: Bearer ${NOTION_API_KEY}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d "{\"filter\":{\"property\":\"Source\",\"url\":{\"equals\":\"${url}\"}}}" \
    | jq '.results | length'
}

# Route one workflow to one destination DB. Returns routed-DB name (or empty).
route_to_db() {
  local workflow="$1" title="$2" url="$3" rationale="$4"
  local target_db="" target_name=""
  case "$workflow" in
    lyra_capability)            target_db="$LYRA_BACKLOG_DB_ID";          target_name="Lyra Backlog" ;;
    work_claude_setup|personal_claude_setup) target_db="$CLAUDE_SETUP_DB_ID"; target_name="Claude Setup Ideas" ;;
    tool_eval)                  target_db="$TOOL_EVAL_DB_ID";             target_name="Tool Eval Tracker" ;;
    content_create)             target_db="$CONTENT_TOPIC_POOL_DB_ID";    target_name="Content Topic Pool" ;;
    *) return 0 ;;
  esac
  [[ -z "$target_db" ]] && return 0

  local existing
  if [[ "$workflow" == "content_create" ]]; then
    existing=$(notion_query_dedup_content "$target_db" "$url")
  else
    existing=$(notion_query_dedup_source "$target_db" "$url")
  fi
  if (( existing > 0 )); then
    echo "  [$workflow] already exists in $target_name, skipping"
    return 0
  fi

  case "$workflow" in
    lyra_capability)
      curl -s -X POST "https://api.notion.com/v1/pages" \
        -H "Authorization: Bearer ${NOTION_API_KEY}" \
        -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
        -d "$(jq -n --arg db "$target_db" --arg title "$title" --arg url "$url" --arg notes "$rationale" \
          '{parent:{database_id:$db},properties:{"Idea":{title:[{text:{content:$title}}]},"Source":{url:$url},"Status":{select:{name:"Idea"}},"Notes":{rich_text:[{text:{content:$notes}}]},"From Bookmark":{checkbox:true}}}')" \
        > /dev/null
      ;;
    work_claude_setup|personal_claude_setup)
      local scope="work" status="Ready"
      [[ "$workflow" == "personal_claude_setup" ]] && scope="personal" && status="Idea"
      curl -s -X POST "https://api.notion.com/v1/pages" \
        -H "Authorization: Bearer ${NOTION_API_KEY}" \
        -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
        -d "$(jq -n --arg db "$target_db" --arg title "$title" --arg url "$url" --arg scope "$scope" --arg status "$status" --arg notes "$rationale" \
          '{parent:{database_id:$db},properties:{"Idea":{title:[{text:{content:$title}}]},"Source":{url:$url},"Scope":{select:{name:$scope}},"Status":{select:{name:$status}},"Notes":{rich_text:[{text:{content:$notes}}]},"From Bookmark":{checkbox:true}}}')" \
        > /dev/null
      ;;
    tool_eval)
      curl -s -X POST "https://api.notion.com/v1/pages" \
        -H "Authorization: Bearer ${NOTION_API_KEY}" \
        -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
        -d "$(jq -n --arg db "$target_db" --arg title "$title" --arg url "$url" --arg notes "$rationale" \
          '{parent:{database_id:$db},properties:{"Tool":{title:[{text:{content:$title}}]},"Source":{url:$url},"Decision":{select:{name:"Evaluate"}},"Notes":{rich_text:[{text:{content:$notes}}]},"From Bookmark":{checkbox:true}}}')" \
        > /dev/null
      ;;
    content_create)
      local week=$(date +%Y-%m-%d)
      curl -s -X POST "https://api.notion.com/v1/pages" \
        -H "Authorization: Bearer ${NOTION_API_KEY}" \
        -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
        -d "$(jq -n --arg db "$target_db" --arg title "$title" --arg url "$url" --arg week "$week" \
          '{parent:{database_id:$db},properties:{"Topic":{title:[{text:{content:$title}}]},"Source":{select:{name:"Twitter"}},"Domain":{select:{name:"General"}},"Score":{number:6},"Status":{select:{name:"Candidate"}},"Week":{date:{start:$week}},"Source Reference":{url:$url}}}')" \
        > /dev/null
      ;;
  esac
  echo "  [$workflow] routed to $target_name"
  printf '%s' "$target_name"
}

# ---------- Process each bookmark ----------
echo "$UNPROCESSED" | jq -c '.results[]' | while read -r page; do
  PAGE_ID=$(echo "$page" | jq -r '.id')
  TWEET_TEXT=$(echo "$page" | jq -r '.properties["Original Tweet Summary"].rich_text[0].text.content // ""')
  TWEET_URL=$(echo "$page" | jq -r '.properties["Original Tweet URL"].url // ""')
  TITLE=$(echo "$page" | jq -r '.properties["Content Byte"].title[0].text.content // ""')
  EXISTING_WORKFLOW=$(echo "$page" | jq -r '.properties["Primary workflow"].select.name // ""')

  echo ""
  echo "Processing: $TITLE"
  echo "  URL: $TWEET_URL"

  if [[ -n "$EXISTING_WORKFLOW" && "$EXISTING_WORKFLOW" != "null" ]]; then
    PRIMARY_WORKFLOW="$EXISTING_WORKFLOW"
    SECONDARY_JSON="[]"
    CONFIDENCE="High"
    RATIONALE="Pre-classified"
    echo "  Already classified: $PRIMARY_WORKFLOW"
  else
    echo "  Classifying with Claude..."
    USER_PROMPT=$(printf 'Exemplars (for calibration):\n%s\n\nTweet to classify:\n%s\n\nReturn JSON only.' "$EXEMPLARS_BLOCK" "$TWEET_TEXT")

    CLASSIFICATION=$(curl -s "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      --retry 3 --retry-delay 2 \
      -d "$(jq -n --arg sys "$SYSTEM_PROMPT" --arg prompt "$USER_PROMPT" \
        '{model:"claude-sonnet-4-20250514", max_tokens:400, system:$sys, messages:[{role:"user", content:$prompt}]}')" \
      | jq -r '.content[0].text // "{}"')

    PRIMARY_WORKFLOW=$(echo "$CLASSIFICATION" | jq -r '.primary_workflow // "research_read_later"')
    SECONDARY_JSON=$(echo "$CLASSIFICATION" | jq -c '.secondary_workflows // []')
    CONFIDENCE=$(echo "$CLASSIFICATION" | jq -r '.confidence // "Low"')
    RATIONALE=$(echo "$CLASSIFICATION" | jq -r '.rationale // "Auto-classified"')

    echo "  Primary: $PRIMARY_WORKFLOW ($CONFIDENCE)"
    echo "  Secondary: $SECONDARY_JSON"

    # Build Workflow multi_select from primary + secondary
    WORKFLOW_MULTI=$(echo "$SECONDARY_JSON" | jq -c --arg p "$PRIMARY_WORKFLOW" '[$p] + . | unique | map({name: .})')

    # Update Twitter Insights with classification
    curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
      -H "Authorization: Bearer ${NOTION_API_KEY}" \
      -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
      --retry 2 --retry-delay 2 \
      -d "$(jq -n --arg workflow "$PRIMARY_WORKFLOW" --arg confidence "$CONFIDENCE" --arg rationale "$RATIONALE" --argjson multi "$WORKFLOW_MULTI" \
        '{properties:{"Primary workflow":{select:{name:$workflow}},"Workflow confidence":{select:{name:$confidence}},"Workflow rationale":{rich_text:[{text:{content:$rationale}}]},"Workflow":{multi_select:$multi}}}')" \
      > /dev/null || echo "  WARN: failed to update Twitter Insights row"
  fi

  # ---------- Multi-label routing: fan out to every matched DB ----------
  ROUTED_TO=""
  ALL_WORKFLOWS=$(echo "$SECONDARY_JSON" | jq -r --arg p "$PRIMARY_WORKFLOW" '[$p] + . | unique | .[]')
  while IFS= read -r wf; do
    [[ -z "$wf" ]] && continue
    routed=$(route_to_db "$wf" "${TITLE:-${TWEET_TEXT:0:200}}" "$TWEET_URL" "$RATIONALE" || true)
    [[ -n "$routed" ]] && ROUTED_TO="${ROUTED_TO}${routed};"
  done <<< "$ALL_WORKFLOWS"

  # ---------- Wiki stub for content_create ----------
  WIKI_STUB=""
  if echo "$ALL_WORKFLOWS" | grep -qx "content_create"; then
    SEC_CSV=$(echo "$SECONDARY_JSON" | jq -r 'join(",")')
    if [[ -x "$WIKI_WRITER" ]]; then
      WIKI_STUB=$("$WIKI_WRITER" "${TITLE:-bookmark}" "$TWEET_URL" "$TWEET_TEXT" "$RATIONALE" "$PRIMARY_WORKFLOW" "$SEC_CSV" 2>/dev/null || echo "")
      if [[ -n "$WIKI_STUB" ]]; then
        echo "  Wiki stub: $WIKI_STUB"
        # Record stub path on the Twitter Insights row
        curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
          -H "Authorization: Bearer ${NOTION_API_KEY}" \
          -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
          -d "$(jq -n --arg path "$WIKI_STUB" '{properties:{"Wiki stub path":{rich_text:[{text:{content:$path}}]}}}')" \
          > /dev/null || true
      fi
    else
      echo "  WARN: wiki writer not executable at $WIKI_WRITER"
    fi
  fi

  # ---------- Audit log ----------
  {
    printf '%s,' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s,' "$PAGE_ID"
    csv_escape "$TWEET_URL"; printf ','
    csv_escape "$TITLE"; printf ','
    printf '%s,' "$PRIMARY_WORKFLOW"
    csv_escape "$(echo "$SECONDARY_JSON" | jq -r 'join(";")')"; printf ','
    printf '%s,' "$CONFIDENCE"
    csv_escape "$RATIONALE"; printf ','
    csv_escape "$WIKI_STUB"; printf ','
    csv_escape "$ROUTED_TO"
    printf '\n'
  } >> "$CLASSIFICATION_LOG_PATH"

  # ---------- Mark processed ----------
  curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
    -H "Authorization: Bearer ${NOTION_API_KEY}" \
    -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
    -d '{"properties":{"Needs review":{"checkbox":false},"Status":{"select":{"name":"Processed"}}}}' \
    > /dev/null || true
  echo "  Marked as processed"

  sleep 0.5
done

echo ""
echo "=== Classification complete ==="
echo "Audit log: $CLASSIFICATION_LOG_PATH"
