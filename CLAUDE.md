# Twitter Bookmarks Pipeline — Project Memory

## What This Is
A pipeline that fetches X (Twitter) bookmarks, syncs them to Notion, classifies into workflow routes via Claude API, and routes to destination databases.

## Status: **Complete & Operational (Track 1 Done)**
- Deployed on Hetzner VPS
- Cron running daily at 7 AM UTC
- Full pipeline: fetch → sync → classify → route
- 20 bookmarks classified and routed (first run)

## Key Files

### Scripts (on VPS at `/root/lyra-ai/scripts/`)
| File | Purpose |
|------|---------|
| `fetch-twitter-bookmarks.sh` | OAuth2 fetch, token rotation, date filter |
| `bookmarks-to-notion.sh` | JSON → Notion sync with deduplication |
| `classify-and-route.sh` | Claude API classification (multi-label) + fan-out to all matched DBs + wiki stub + audit log |
| `write-bookmark-to-wiki.sh` | Writes a markdown stub to `personal-kb-raw/raw/bookmarks/` for `content_create` routes |
| `learn-exemplars.sh` | Harvests manual overrides (Correct route column) into classifier exemplars |
| `apply-claude-setup.sh` | Auto-apply Claude setup improvements |
| `get-twitter-oauth-refresh-token.sh` | One-time OAuth setup |
| `run-with-openclaw-env.sh` | Env loader for cron |

### Config
- `config/classifier-exemplars.json` — labeled exemplars injected into the classifier prompt. Grows via `learn-exemplars.sh`.
- `config/field-mapping.md` — canonical field names per destination DB + required schema additions in Twitter Insights.

### Logs
- `logs/classification-log.csv` — every classification decision (timestamp, page_id, url, title, primary, secondary, confidence, rationale, wiki stub, routed DBs). Review weekly.

## Multi-label Routing (2026-04-22)
The classifier now returns `primary_workflow` + `secondary_workflows[]`. A single bookmark fans out to every matched destination DB (e.g. `content_create` + `tool_eval` creates rows in both Content Topic Pool AND Tool Eval Tracker). Dedup is per-DB by source URL.

## Wiki Integration (2026-04-22)
When a bookmark routes to `content_create`, a markdown stub is written to `$PERSONAL_KB_PATH/raw/bookmarks/YYYY-MM-DD-<slug>.md` with frontmatter (tweet_url, primary_workflow, secondary_workflows, status=idea). This is the bridge to downstream workflows (content-engine, lenny extractor) that already read from the wiki.

Env vars:
- `PERSONAL_KB_PATH` — defaults to `/root/projects/personal-kb-raw` on VPS, `~/AI/projects/personal-kb-raw` on Mac
- `WIKI_GIT_AUTOCOMMIT=true` — optional, auto-commit+push after write

## Required Twitter Insights schema additions
See `config/field-mapping.md`. Add these columns in Notion (one-time manual setup):
- `Workflow` (multi_select) — all matched workflows
- `Correct route` (select) — **manual override** when classifier is wrong
- `Exemplar harvested` (checkbox) — set by learner
- `Wiki stub path` (rich_text) — populated on content_create routes

### Claude Setup Automation

**Work scope items:**
- Direct email sending is disabled
- Work scope creates draft emails only (never send directly)
- Optional draft folder override: `EMAIL_DRAFTS_FOLDER` (default `Drafts`)
- You manually review/forward/apply from drafts

**Personal scope items:**
- Committed to git sync repo (`/root/claude-setup-sync`)
- Mac auto-pulls every 15 min via launchd
- macOS notification when new items arrive
- Files land in `~/.claude/setup-sync/pending/`

### Notion Databases

**Source:**
| Database | ID | Purpose |
|----------|-----|---------|
| Twitter Insights | `32d7800891008191b853d73aea132065` | All bookmarks land here first |

**Destinations (auto-routed):**
| Database | ID | Routes |
|----------|-----|--------|
| Lyra Backlog | `33a780089100812282c7c5ead53149` | `lyra_capability` |
| Claude Setup Ideas | `33a7800891008197bad5d1a53afe8efa` | `work_/personal_claude_setup` |
| Content Ideas | `27fc8e00643a4b9390f7ce8b9a345c62` | `content_create` |
| Tool Eval Tracker | `33a7800891008116b664f18dac2a0e24` | `tool_eval` |

### GitHub
- **Public repo:** https://github.com/ahkedia/twitter-bookmarks-pipeline
- **Also in Lyra repo:** Scripts live in `lyra-ai/scripts/`, skill in `lyra-ai/skills/twitter-synthesis/`

## Configuration (in `~/.openclaw/.env` on VPS)

```bash
TWITTER_CLIENT_ID="..."
TWITTER_CLIENT_SECRET="..."
TWITTER_REFRESH_TOKEN="..."  # Auto-rotates on each use
TWITTER_USER_ID="1417748727599534081"
NOTION_API_KEY="..."
ANTHROPIC_API_KEY="..."  # For classification

# Database IDs
TWITTER_INSIGHTS_DB_ID="32d7800891008191b853d73aea132065"
LYRA_BACKLOG_DB_ID="33a780089100812282c7c5ead53149"
CLAUDE_SETUP_DB_ID="33a7800891008197bad5d1a53afe8efa"
# Content Topic Pool (canonical). Legacy: CONTENT_IDEAS_DB_ID still works as fallback.
CONTENT_TOPIC_POOL_DB_ID="33f780089100812aacaec0a61d8caf3a"
TOOL_EVAL_DB_ID="33a7800891008116b664f18dac2a0e24"
```

## Cron Schedule

```bash
# Full pipeline at 7 AM UTC daily: fetch → sync → classify → route → apply
0 7 * * * .../fetch-twitter-bookmarks.sh && \
          .../bookmarks-to-notion.sh && \
          .../classify-and-route.sh && \
          .../apply-claude-setup.sh

# Learn from manual overrides nightly at 3 AM UTC
0 3 * * * .../run-with-openclaw-env.sh .../learn-exemplars.sh
```

## Mac Launchd Job

```bash
# Runs every 15 minutes, auto-pulls git sync repo
# Sends macOS notification when new items arrive
~/Library/LaunchAgents/com.akash.claude-setup-sync.plist
```

## Cost
- X API: Pay-per-use, ~$0.01-0.05/day
- Topped up $5 on 2026-04-06

## Key Decisions Made

1. **Date filter:** Dynamic "yesterday" to minimize API costs
2. **Token rotation:** Script auto-saves new refresh token when X rotates it
3. **OAuth endpoint:** `api.twitter.com` (not `oauth2.twitter.com` which doesn't exist)
4. **Auth method:** HTTP Basic Auth for client credentials (not body params)
5. **Notion fields:** 18 fields including 6 workflow classification fields

## Workflow Routes (for Lyra synthesis)

| Route | Meaning |
|-------|---------|
| `lyra_capability` | Improves Lyra/gateway/skills |
| `work_claude_setup` | Team Claude/Cursor setup |
| `personal_claude_setup` | Personal dev environment |
| `work_productivity` | Process/leadership improvements |
| `content_create` | Worth turning into a post |
| `research_read_later` | Deep read for later |
| `tool_eval` | Evaluate a tool/vendor |
| `market_competitor` | Market/competitor intel |

## Quick Commands

```bash
# Manual full pipeline
ssh hetzner "/root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/fetch-twitter-bookmarks.sh"
ssh hetzner "/root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/bookmarks-to-notion.sh"
ssh hetzner "/root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/classify-and-route.sh"

# Check cron log
ssh hetzner "tail -50 /var/log/lyra-twitter-cron.log"

# Check unprocessed count
ssh hetzner 'source ~/.openclaw/.env && curl -s -X POST "https://api.notion.com/v1/databases/${TWITTER_INSIGHTS_DB_ID}/query" -H "Authorization: Bearer $NOTION_API_KEY" -H "Notion-Version: 2022-06-28" -H "Content-Type: application/json" -d "{\"filter\":{\"property\":\"Needs review\",\"checkbox\":{\"equals\":true}}}" | jq ".results | length"'

# Check Lyra Backlog count
ssh hetzner 'source ~/.openclaw/.env && curl -s -X POST "https://api.notion.com/v1/databases/${LYRA_BACKLOG_DB_ID}/query" -H "Authorization: Bearer $NOTION_API_KEY" -H "Notion-Version: 2022-06-28" -d "{}" | jq ".results | length"'
```

## What's NOT Done Yet (Track 2)

1. **Content generation pipeline** — Content Ideas DB entries should trigger an end-to-end content generation workflow (drafts, review, publish)
2. **Lyra synthesis enhancement** — The `twitter-synthesis` skill can generate richer content bytes, but current routing is lightweight classification only

## Session History

### 2026-04-06: Initial Setup
- Created X Developer app, configured OAuth2
- Fixed multiple OAuth issues (endpoint, auth method, token rotation)
- Created Notion database with 18 fields
- Deployed scripts to VPS
- Set up daily cron
- Created public GitHub repo with blog post
- Synced 34 initial bookmarks to Notion

### 2026-04-06: Track 1 Complete (Automated Routing)
- Created 3 new Notion databases: Lyra Backlog, Claude Setup Ideas, Tool Eval Tracker
- Built `classify-and-route.sh` that:
  - Fetches unprocessed bookmarks (Needs review=true, Status=Draft)
  - Calls Claude API to classify into 8 workflow routes
  - Routes to 4 destination databases based on primary workflow
  - Marks items as processed
- First run classified 20 bookmarks:
  - 4 → Lyra Backlog (lyra_capability)
  - 6 → Claude Setup Ideas (work/personal_claude_setup)
  - 4 → Content Ideas (content_create)
  - 0 → Tool Eval Tracker (tool_eval)
  - 6 → stayed in Twitter Insights (research_read_later, market_competitor)
- Updated cron to run full pipeline
- Updated GitHub repo and blog

### 2026-04-06: Claude Setup Automation
- Built `apply-claude-setup.sh` for downstream actions on Ready items
- **Work scope:** Email via Himalaya → forward to work email → apply manually
- **Personal scope:** 
  - VPS commits to private git repo (`claude-setup-sync`)
  - Mac auto-pulls via launchd every 15 min
  - macOS notification on new items
  - Files appear in `~/.claude/setup-sync/pending/`
- Fixed Himalaya config (disabled save-copy to avoid IMAP folder error)
- Improved classification: MCP tools now route to work_claude_setup
- Added Status options: Ready, Sent, Applied, Rejected

### 2026-04-08: Email Safety Hard Guard
- Added hard policy: no direct email sending
- `apply-claude-setup.sh` now creates drafts only for work-scope items
- Work items are marked terminal after draft creation to avoid duplicate drafts
