# Twitter Bookmarks Pipeline — Project Memory

## What This Is
A pipeline that fetches X (Twitter) bookmarks, syncs them to Notion, and classifies them into workflow routes for automated downstream actions.

## Status: **Complete & Operational**
- Deployed on Hetzner VPS
- Cron running daily at 7 AM UTC
- 34 bookmarks synced to Notion (initial run)

## Key Files

### Scripts (on VPS at `/root/lyra-ai/scripts/`)
| File | Purpose |
|------|---------|
| `fetch-twitter-bookmarks.sh` | OAuth2 fetch, token rotation, date filter |
| `bookmarks-to-notion.sh` | JSON → Notion sync with deduplication |
| `get-twitter-oauth-refresh-token.sh` | One-time OAuth setup |
| `run-with-openclaw-env.sh` | Env loader for cron |

### Notion
- **Database:** Twitter Insights
- **Database ID:** `32d7800891008191b853d73aea132065`
- **Fields:** 18 total including workflow classification fields
- **Link:** https://www.notion.so/akashkedia/32d7800891008191b853d73aea132065

### GitHub
- **Public repo:** https://github.com/ahkedia/twitter-bookmarks-pipeline
- **Also in Lyra repo:** Scripts live in `lyra-ai/scripts/`, skill in `lyra-ai/skills/twitter-synthesis/`

## Configuration (in `~/.openclaw/.env` on VPS)

```bash
TWITTER_CLIENT_ID="..."
TWITTER_CLIENT_SECRET="..."
TWITTER_REFRESH_TOKEN="..."  # Auto-rotates on each use
TWITTER_USER_ID="1417748727599534081"
TWITTER_INSIGHTS_DB_ID="32d7800891008191b853d73aea132065"
NOTION_API_KEY="..."
```

## Cron Schedule

```bash
# Runs at 7 AM UTC daily
0 7 * * * /root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/fetch-twitter-bookmarks.sh && /root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/bookmarks-to-notion.sh
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
# Manual fetch + sync
ssh hetzner "/root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/fetch-twitter-bookmarks.sh"
ssh hetzner "/root/lyra-ai/scripts/run-with-openclaw-env.sh /root/lyra-ai/scripts/bookmarks-to-notion.sh"

# Check cron log
ssh hetzner "tail -50 /var/log/lyra-twitter-cron.log"

# Check Notion entry count
ssh hetzner 'source ~/.openclaw/.env && curl -s -X POST "https://api.notion.com/v1/databases/${TWITTER_INSIGHTS_DB_ID}/query" -H "Authorization: Bearer $NOTION_API_KEY" -H "Notion-Version: 2022-06-28" -d "{}" | jq ".results | length"'
```

## What's NOT Done Yet

1. **Lyra synthesis skill execution** — The `twitter-synthesis` skill classifies and generates content bytes, but needs to be triggered via Lyra/OpenClaw (not standalone script yet)
2. **Downstream automations** — Routes exist in Notion, but triggers to other systems (Lyra backlog, content queue, etc.) need to be wired up

## Session History

### 2026-04-06: Initial Setup
- Created X Developer app, configured OAuth2
- Fixed multiple OAuth issues (endpoint, auth method, token rotation)
- Created Notion database with 18 fields
- Deployed scripts to VPS
- Set up daily cron
- Created public GitHub repo with blog post
- Synced 34 initial bookmarks to Notion
