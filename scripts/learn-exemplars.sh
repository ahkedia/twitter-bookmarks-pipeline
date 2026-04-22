#!/bin/bash
# Harvest manual-override corrections from Twitter Insights into classifier exemplars.
#
# Whenever you disagree with the classifier, set the "Correct route" column on that
# Twitter Insights row. This script finds rows where Correct route != Primary workflow
# and Exemplar harvested is false, appends them to classifier-exemplars.json, and
# marks them harvested.
#
# Run nightly via cron (after classify-and-route.sh).

set -e

NOTION_API_KEY="${NOTION_API_KEY:-}"
TWITTER_INSIGHTS_DB_ID="${TWITTER_INSIGHTS_DB_ID:-}"

if [[ -z "$NOTION_API_KEY" || -z "$TWITTER_INSIGHTS_DB_ID" ]]; then
  echo "Missing env: NOTION_API_KEY, TWITTER_INSIGHTS_DB_ID" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXEMPLARS_FILE="${EXEMPLARS_FILE:-$REPO_ROOT/config/classifier-exemplars.json}"
MAX_EXEMPLARS="${MAX_EXEMPLARS:-20}"

echo "=== Learn exemplars: $(date) ==="

# Fetch rows where Correct route is set AND Exemplar harvested is not true
RESP=$(curl -s -X POST "https://api.notion.com/v1/databases/${TWITTER_INSIGHTS_DB_ID}/query" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {
      "and": [
        {"property": "Correct route", "select": {"is_not_empty": true}},
        {"property": "Exemplar harvested", "checkbox": {"equals": false}}
      ]
    },
    "page_size": 20
  }')

COUNT=$(echo "$RESP" | jq '.results | length')
echo "Found $COUNT correction candidates"
(( COUNT == 0 )) && exit 0

TMP=$(mktemp)
cp "$EXEMPLARS_FILE" "$TMP"

echo "$RESP" | jq -c '.results[]' | while read -r page; do
  PAGE_ID=$(echo "$page" | jq -r '.id')
  TWEET=$(echo "$page" | jq -r '.properties["Original Tweet Summary"].rich_text[0].text.content // ""')
  CORRECT=$(echo "$page" | jq -r '.properties["Correct route"].select.name // ""')
  PRIMARY=$(echo "$page" | jq -r '.properties["Primary workflow"].select.name // ""')
  [[ -z "$TWEET" || -z "$CORRECT" ]] && continue

  RATIONALE="User-corrected: classifier said '${PRIMARY}', truth is '${CORRECT}'."

  # Append to exemplars (dedup on tweet text)
  NEW=$(jq --arg t "$TWEET" --arg p "$CORRECT" --arg r "$RATIONALE" \
    '.exemplars |= (map(select(.tweet != $t)) + [{tweet:$t, primary_workflow:$p, secondary_workflows:[], rationale:$r}])' "$TMP")
  echo "$NEW" > "$TMP"

  # Mark as harvested in Notion
  curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
    -H "Authorization: Bearer ${NOTION_API_KEY}" \
    -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" \
    -d '{"properties":{"Exemplar harvested":{"checkbox":true}}}' > /dev/null || true

  echo "  Harvested: ${TWEET:0:80}... → $CORRECT"
done

# Trim to most recent MAX_EXEMPLARS
TRIMMED=$(jq --argjson max "$MAX_EXEMPLARS" '.exemplars |= (.[-$max:])' "$TMP")
echo "$TRIMMED" > "$EXEMPLARS_FILE"

echo "Exemplars updated: $EXEMPLARS_FILE (total: $(jq '.exemplars | length' "$EXEMPLARS_FILE"))"
rm -f "$TMP"
