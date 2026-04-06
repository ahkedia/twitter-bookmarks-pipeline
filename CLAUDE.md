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
| `classify-and-route.sh` | Claude API classification + DB routing |
| `get-twitter-oauth-refresh-token.sh` | One-time OAuth setup |
| `run-with-openclaw-env.sh` | Env loader for cron |

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
CONTENT_IDEAS_DB_ID="27fc8e00643a4b9390f7ce8b9a345c62"
TOOL_EVAL_DB_ID="33a7800891008116b664f18dac2a0e24"
```

## Cron Schedule

```bash
# Full pipeline at 7 AM UTC daily: fetch → sync → classify → route
0 7 * * * /root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/fetch-twitter-bookmarks.sh && \
          /root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/bookmarks-to-notion.sh && \
          /root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/classify-and-route.sh
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
