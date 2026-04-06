#!/bin/bash
# Apply Claude Setup improvements from Notion
# - Work scope: Email via Himalaya for manual forwarding
# - Personal scope: Direct apply to VPS + git commit for Mac sync
# Usage: ./apply-claude-setup.sh

set -e

NOTION_API_KEY="${NOTION_API_KEY:-}"
CLAUDE_SETUP_DB_ID="${CLAUDE_SETUP_DB_ID:-}"
SYNC_REPO_PATH="${CLAUDE_SETUP_SYNC_REPO:-/root/claude-setup-sync}"
YOUR_EMAIL="${YOUR_EMAIL:-akash@unfilteredakash.com}"

if [[ -z "$NOTION_API_KEY" || -z "$CLAUDE_SETUP_DB_ID" ]]; then
  echo "Missing required env vars: NOTION_API_KEY, CLAUDE_SETUP_DB_ID"
  exit 1
fi

echo "=== Apply Claude Setup: $(date) ==="

# Query for Ready items
echo "Fetching Ready items from Claude Setup Ideas..."
READY_ITEMS=$(curl -s -X POST "https://api.notion.com/v1/databases/${CLAUDE_SETUP_DB_ID}/query" \
  -H "Authorization: Bearer ${NOTION_API_KEY}" \
  -H "Notion-Version: 2022-06-28" \
  -H "Content-Type: application/json" \
  -d '{
    "filter": {
      "property": "Status",
      "select": {"equals": "Ready"}
    }
  }')

COUNT=$(echo "$READY_ITEMS" | jq '.results | length')
echo "Found $COUNT Ready items"

if (( COUNT == 0 )); then
  echo "Nothing to apply"
  exit 0
fi

# Process each item
echo "$READY_ITEMS" | jq -c '.results[]' | while read -r item; do
  PAGE_ID=$(echo "$item" | jq -r '.id')
  TITLE=$(echo "$item" | jq -r '.properties.Idea.title[0].text.content // "Untitled"')
  SCOPE=$(echo "$item" | jq -r '.properties.Scope.select.name // "personal"')
  SOURCE_URL=$(echo "$item" | jq -r '.properties.Source.url // ""')
  NOTES=$(echo "$item" | jq -r '.properties.Notes.rich_text[0].text.content // ""')
  TYPE=$(echo "$item" | jq -r '.properties.Type.select.name // "unknown"')
  
  echo ""
  echo "Processing: $TITLE"
  echo "  Scope: $SCOPE"
  echo "  Type: $TYPE"
  
  # Generate improvement content
  IMPROVEMENT_CONTENT="# Claude Setup Improvement

## Idea
$TITLE

## Type
$TYPE

## Source
$SOURCE_URL

## Notes
$NOTES

## How to Apply
Based on this improvement idea, consider:
1. Review the source tweet/link for full context
2. Identify the specific file(s) to modify (CLAUDE.md, rules, skills)
3. Make the change and test

---
*Auto-generated from Twitter Bookmarks Pipeline*
*Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)*"

  if [[ "$SCOPE" == "work" ]]; then
    # Work scope: Send email via Himalaya
    echo "  Sending email for work setup..."
    
    EMAIL_SUBJECT="[WORK-SETUP] $TITLE"
    EMAIL_BODY="Hi,

A new Claude setup improvement is ready for your work environment.

**Idea:** $TITLE
**Type:** $TYPE
**Source:** $SOURCE_URL

**Notes:**
$NOTES

---
Forward this to your work email, then apply the changes to your work CLAUDE.md or Cursor rules.

Lyra"

    # Send via Himalaya (using template send for non-interactive)
    himalaya template send << EOF
From: Lyra <lyra@unfilteredakash.com>
To: $YOUR_EMAIL
Subject: $EMAIL_SUBJECT

$EMAIL_BODY
EOF
    
    if [[ $? -ne 0 ]]; then
      echo "  Warning: Email send failed"
    fi
    
    echo "  Email sent to $YOUR_EMAIL"
    
    # Update Notion status to "Sent"
    curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
      -H "Authorization: Bearer ${NOTION_API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{"properties": {"Status": {"select": {"name": "Sent"}}}}' > /dev/null
    
    echo "  Marked as Sent"
    
  else
    # Personal scope: Apply to VPS + commit for Mac sync
    echo "  Applying personal setup..."
    
    # Create improvement file for Mac sync
    if [[ -d "$SYNC_REPO_PATH" ]]; then
      FILENAME="$(date +%Y-%m-%d)-$(echo "$TITLE" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-' | head -c 50).md"
      echo "$IMPROVEMENT_CONTENT" > "$SYNC_REPO_PATH/pending/$FILENAME"
      
      # Git commit and push
      cd "$SYNC_REPO_PATH"
      git add -A
      git commit -m "Add: $TITLE" 2>/dev/null || true
      git push origin main 2>/dev/null || echo "  Warning: Git push failed"
      
      echo "  Committed to sync repo: $FILENAME"
    else
      echo "  Warning: Sync repo not found at $SYNC_REPO_PATH"
    fi
    
    # Update Notion status to "Applied"
    curl -s -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
      -H "Authorization: Bearer ${NOTION_API_KEY}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{"properties": {"Status": {"select": {"name": "Applied"}}}}' > /dev/null
    
    echo "  Marked as Applied"
  fi
  
  sleep 0.5
done

echo ""
echo "=== Apply Claude Setup complete ==="
