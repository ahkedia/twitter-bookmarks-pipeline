#!/bin/bash
# Classify unprocessed Twitter Insights entries and route to workflow databases
# Usage: ./classify-and-route.sh
# Requires: NOTION_API_KEY, ANTHROPIC_API_KEY, all DB IDs in env

set -e

NOTION_API_KEY="${NOTION_API_KEY:-}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
TWITTER_INSIGHTS_DB_ID="${TWITTER_INSIGHTS_DB_ID:-}"
LYRA_BACKLOG_DB_ID="${LYRA_BACKLOG_DB_ID:-}"
CLAUDE_SETUP_DB_ID="${CLAUDE_SETUP_DB_ID:-}"
TOOL_EVAL_DB_ID="${TOOL_EVAL_DB_ID:-}"
CONTENT_IDEAS_DB_ID="${CONTENT_IDEAS_DB_ID:-}"

if [[ -z "$NOTION_API_KEY" || -z "$ANTHROPIC_API_KEY" || -z "$TWITTER_INSIGHTS_DB_ID" ]]; then
  echo "Missing required env vars: NOTION_API_KEY, ANTHROPIC_API_KEY, TWITTER_INSIGHTS_DB_ID"
  exit 1
fi

echo "=== Classify & Route: $(date) ==="

# Step 1: Query Twitter Insights for unprocessed entries (Needs review = true, Status = Draft)
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

# Process each entry
echo "$UNPROCESSED" | jq -c '.results[]' | while read -r page; do
  PAGE_ID=$(echo "$page" | jq -r '.id')
  TWEET_TEXT=$(echo "$page" | jq -r '.properties["Original Tweet Summary"].rich_text[0].text.content // ""')
  TWEET_URL=$(echo "$page" | jq -r '.properties["Original Tweet URL"].url // ""')
  TITLE=$(echo "$page" | jq -r '.properties["Content Byte"].title[0].text.content // ""')
  EXISTING_WORKFLOW=$(echo "$page" | jq -r '.properties["Primary workflow"].select.name // ""')
  
  echo ""
  echo "Processing: $TITLE"
  echo "  URL: $TWEET_URL"
  
  # If already has primary workflow, skip classification
  if [[ -n "$EXISTING_WORKFLOW" && "$EXISTING_WORKFLOW" != "null" ]]; then
    PRIMARY_WORKFLOW="$EXISTING_WORKFLOW"
    CONFIDENCE="High"
    RATIONALE="Pre-classified"
    echo "  Already classified: $PRIMARY_WORKFLOW"
  else
    # Use Claude to classify
    echo "  Classifying with Claude..."
    
    CLASSIFY_PROMPT="Classify this tweet bookmark into exactly one primary workflow category.

Tweet: ${TWEET_TEXT}

Categories:
- lyra_capability: Improves AI assistants, automations, skills, MCP tools, Telegram bots
- work_claude_setup: Improves Claude/Cursor/repo rules/team AI tooling for work
- personal_claude_setup: Personal Claude/Cursor setup improvements
- work_productivity: Work habits, processes, productivity tips (not AI-specific)
- content_create: Worth turning into a post/thread/article
- research_read_later: Save for deep reading, no immediate action
- tool_eval: Evaluate a tool/vendor/product to adopt
- market_competitor: Market intel or competitor analysis

Respond in exactly this JSON format:
{\"primary_workflow\": \"category_name\", \"confidence\": \"High|Medium|Low\", \"rationale\": \"one sentence why\"}"

    CLASSIFICATION=$(curl -s "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: ${ANTHROPIC_API_KEY}" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$(jq -n \
        --arg prompt "$CLASSIFY_PROMPT" \
        '{
          model: "claude-sonnet-4-20250514",
          max_tokens: 200,
          messages: [{role: "user", content: $prompt}]
        }')" \
      | jq -r '.content[0].text // "{}"')
    
    PRIMARY_WORKFLOW=$(echo "$CLASSIFICATION" | jq -r '.primary_workflow // "research_read_later"')
    CONFIDENCE=$(echo "$CLASSIFICATION" | jq -r '.confidence // "Low"')
    RATIONALE=$(echo "$CLASSIFICATION" | jq -r '.rationale // "Auto-classified"')
    
    echo "  Classified as: $PRIMARY_WORKFLOW ($CONFIDENCE)"
    
    # Update Twitter Insights with classification
    curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
      -H "Authorization: Bearer ${NOTION_API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg workflow "$PRIMARY_WORKFLOW" \
        --arg confidence "$CONFIDENCE" \
        --arg rationale "$RATIONALE" \
        '{
          properties: {
            "Primary workflow": {select: {name: $workflow}},
            "Workflow confidence": {select: {name: $confidence}},
            "Workflow rationale": {rich_text: [{text: {content: $rationale}}]},
            "Workflow": {multi_select: [{name: $workflow}]}
          }
        }')" > /dev/null
  fi
  
  # Route to appropriate database based on primary workflow
  TARGET_DB=""
  TARGET_DB_NAME=""
  
  case "$PRIMARY_WORKFLOW" in
    lyra_capability)
      TARGET_DB="$LYRA_BACKLOG_DB_ID"
      TARGET_DB_NAME="Lyra Backlog"
      ;;
    work_claude_setup|personal_claude_setup)
      TARGET_DB="$CLAUDE_SETUP_DB_ID"
      TARGET_DB_NAME="Claude Setup Ideas"
      ;;
    tool_eval)
      TARGET_DB="$TOOL_EVAL_DB_ID"
      TARGET_DB_NAME="Tool Eval Tracker"
      ;;
    content_create)
      TARGET_DB="$CONTENT_IDEAS_DB_ID"
      TARGET_DB_NAME="Content Ideas"
      ;;
    *)
      # work_productivity, research_read_later, market_competitor stay in Twitter Insights
      echo "  No routing needed (stays in Twitter Insights)"
      ;;
  esac
  
  if [[ -n "$TARGET_DB" ]]; then
    echo "  Routing to: $TARGET_DB_NAME"
    
    # Check if already exists in target DB (by URL)
    EXISTING=$(curl -s -X POST "https://api.notion.com/v1/databases/${TARGET_DB}/query" \
      -H "Authorization: Bearer ${NOTION_API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "{\"filter\":{\"property\":\"Source\",\"url\":{\"equals\":\"${TWEET_URL}\"}}}" \
      | jq '.results | length')
    
    if (( EXISTING > 0 )); then
      echo "  Already exists in $TARGET_DB_NAME, skipping"
    else
      # Create entry in target DB
      case "$PRIMARY_WORKFLOW" in
        lyra_capability)
          curl -s -X POST "https://api.notion.com/v1/pages" \
            -H "Authorization: Bearer ${NOTION_API_KEY}" \
            -H "Notion-Version: 2022-06-28" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
              --arg db "$TARGET_DB" \
              --arg title "$TITLE" \
              --arg url "$TWEET_URL" \
              --arg notes "$RATIONALE" \
              '{
                parent: {database_id: $db},
                properties: {
                  "Idea": {title: [{text: {content: $title}}]},
                  "Source": {url: $url},
                  "Status": {select: {name: "Idea"}},
                  "Notes": {rich_text: [{text: {content: $notes}}]},
                  "From Bookmark": {checkbox: true}
                }
              }')" > /dev/null
          echo "  Created in Lyra Backlog"
          ;;
        work_claude_setup|personal_claude_setup)
          SCOPE="work"
          [[ "$PRIMARY_WORKFLOW" == "personal_claude_setup" ]] && SCOPE="personal"
          curl -s -X POST "https://api.notion.com/v1/pages" \
            -H "Authorization: Bearer ${NOTION_API_KEY}" \
            -H "Notion-Version: 2022-06-28" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
              --arg db "$TARGET_DB" \
              --arg title "$TITLE" \
              --arg url "$TWEET_URL" \
              --arg scope "$SCOPE" \
              --arg notes "$RATIONALE" \
              '{
                parent: {database_id: $db},
                properties: {
                  "Idea": {title: [{text: {content: $title}}]},
                  "Source": {url: $url},
                  "Scope": {select: {name: $scope}},
                  "Status": {select: {name: "Idea"}},
                  "Notes": {rich_text: [{text: {content: $notes}}]},
                  "From Bookmark": {checkbox: true}
                }
              }')" > /dev/null
          echo "  Created in Claude Setup Ideas ($SCOPE)"
          ;;
        tool_eval)
          curl -s -X POST "https://api.notion.com/v1/pages" \
            -H "Authorization: Bearer ${NOTION_API_KEY}" \
            -H "Notion-Version: 2022-06-28" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
              --arg db "$TARGET_DB" \
              --arg title "$TITLE" \
              --arg url "$TWEET_URL" \
              --arg notes "$RATIONALE" \
              '{
                parent: {database_id: $db},
                properties: {
                  "Tool": {title: [{text: {content: $title}}]},
                  "Source": {url: $url},
                  "Decision": {select: {name: "Evaluate"}},
                  "Notes": {rich_text: [{text: {content: $notes}}]},
                  "From Bookmark": {checkbox: true}
                }
              }')" > /dev/null
          echo "  Created in Tool Eval Tracker"
          ;;
        content_create)
          curl -s -X POST "https://api.notion.com/v1/pages" \
            -H "Authorization: Bearer ${NOTION_API_KEY}" \
            -H "Notion-Version: 2022-06-28" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
              --arg db "$TARGET_DB" \
              --arg title "$TITLE" \
              --arg url "$TWEET_URL" \
              --arg summary "$TWEET_TEXT" \
              '{
                parent: {database_id: $db},
                properties: {
                  "Idea": {title: [{text: {content: $title}}]},
                  "Link": {url: $url},
                  "Status": {select: {name: "Idea"}},
                  "Rough Notes": {rich_text: [{text: {content: ($summary | .[0:2000])}}]},
                  "From Bookmark": {checkbox: true}
                }
              }')" > /dev/null
          echo "  Created in Content Ideas"
          ;;
      esac
    fi
  fi
  
  # Mark as processed in Twitter Insights
  curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
    -H "Authorization: Bearer ${NOTION_API_KEY}" \
    -H "Notion-Version: 2022-06-28" \
    -H "Content-Type: application/json" \
    -d '{
      "properties": {
        "Needs review": {"checkbox": false},
        "Status": {"select": {"name": "Processed"}}
      }
    }' > /dev/null
  echo "  Marked as processed"
  
  sleep 0.5
done

echo ""
echo "=== Classification complete ==="
