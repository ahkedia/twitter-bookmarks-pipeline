#!/bin/bash
# Write a bookmark stub to the personal KB wiki.
# Called by classify-and-route.sh when a bookmark is routed to content_create.
#
# Usage: write-bookmark-to-wiki.sh <title> <tweet_url> <tweet_text> <rationale> <primary_workflow> <secondary_workflows_csv>
# Env:
#   PERSONAL_KB_PATH  — root of personal-kb-raw (default: $HOME/AI/projects/personal-kb-raw on Mac, /root/projects/personal-kb-raw on VPS)
#   WIKI_GIT_AUTOCOMMIT — if "true", git add+commit+push after write
#
# Output (stdout): relative path to the created stub, or empty on skip.

set -e

TITLE="$1"
TWEET_URL="$2"
TWEET_TEXT="$3"
RATIONALE="$4"
PRIMARY="$5"
SECONDARY="$6"

if [[ -z "$TWEET_URL" ]]; then
  echo "write-bookmark-to-wiki: missing tweet_url" >&2
  exit 1
fi

# Resolve KB path
if [[ -z "$PERSONAL_KB_PATH" ]]; then
  if [[ -d "/root/projects/personal-kb-raw" ]]; then
    PERSONAL_KB_PATH="/root/projects/personal-kb-raw"
  elif [[ -d "$HOME/AI/projects/personal-kb-raw" ]]; then
    PERSONAL_KB_PATH="$HOME/AI/projects/personal-kb-raw"
  else
    echo "write-bookmark-to-wiki: PERSONAL_KB_PATH not set and no default exists" >&2
    exit 1
  fi
fi

BOOKMARKS_DIR="${PERSONAL_KB_PATH}/raw/bookmarks"
mkdir -p "$BOOKMARKS_DIR"

# Build slug from title (fallback to tweet id from URL)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g' | sed 's/^-\+\|-\+$//g' | cut -c1-60)
if [[ -z "$SLUG" ]]; then
  SLUG=$(echo "$TWEET_URL" | sed 's|.*/||' | cut -c1-20)
fi
DATE=$(date +%Y-%m-%d)
FILE="${BOOKMARKS_DIR}/${DATE}-${SLUG}.md"

# Idempotent: skip if a file with same tweet URL already exists
if grep -rlF "tweet_url: \"${TWEET_URL}\"" "$BOOKMARKS_DIR" 2>/dev/null | head -1 | grep -q .; then
  EXISTING=$(grep -rlF "tweet_url: \"${TWEET_URL}\"" "$BOOKMARKS_DIR" | head -1)
  echo "${EXISTING#$PERSONAL_KB_PATH/}"
  exit 0
fi

# Escape yaml values
yaml_escape() {
  printf '%s' "$1" | sed 's/"/\\"/g' | tr '\n' ' '
}

SEC_YAML=""
if [[ -n "$SECONDARY" ]]; then
  IFS=',' read -ra SEC_ARR <<< "$SECONDARY"
  for s in "${SEC_ARR[@]}"; do
    s_trim=$(echo "$s" | xargs)
    [[ -z "$s_trim" ]] && continue
    SEC_YAML="${SEC_YAML}
  - ${s_trim}"
  done
fi
[[ -z "$SEC_YAML" ]] && SEC_YAML=" []"

cat > "$FILE" <<EOF
---
source: twitter-bookmark
tweet_url: "$(yaml_escape "$TWEET_URL")"
captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
primary_workflow: ${PRIMARY}
secondary_workflows:${SEC_YAML}
status: idea
published: false
---

# $(yaml_escape "$TITLE")

**Source:** [tweet]($TWEET_URL)

## Summary
$(echo "$TWEET_TEXT" | sed 's/^/> /')

## Why it matters
${RATIONALE}

## Angles / hooks
- (fill in when drafting)

## Related
- (link to other wiki notes)
EOF

# Optional: auto-commit if flag is set
if [[ "$WIKI_GIT_AUTOCOMMIT" == "true" && -d "${PERSONAL_KB_PATH}/.git" ]]; then
  (
    cd "$PERSONAL_KB_PATH"
    git add "raw/bookmarks/$(basename "$FILE")" >/dev/null 2>&1 || true
    git commit -m "bookmark: ${DATE}-${SLUG}" >/dev/null 2>&1 || true
    git push >/dev/null 2>&1 || true
  )
fi

echo "raw/bookmarks/$(basename "$FILE")"
