# Twitter Bookmarks → Notion Pipeline

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)

> Fetch your X bookmarks daily · Classify into workflow routes · Sync to Notion · Let AI automate the rest

---

## What This Does

Every day at 7am, this pipeline:

1. **Fetches** your X (Twitter) bookmarks from the last 24 hours
2. **Syncs** them to a Notion database (Twitter Insights) with structured fields
3. **Classifies** each bookmark using Claude AI into one of 8 workflow routes
4. **Routes** to destination Notion databases (Lyra Backlog, Claude Setup Ideas, Content Ideas, Tool Eval Tracker)

The magic isn't the fetch — it's the routing. Each bookmark gets classified:

| Workflow | Destination DB | What happens |
|----------|----------------|--------------|
| `lyra_capability` | Lyra Backlog | AI assistant improvement ideas |
| `work_claude_setup` | Claude Setup Ideas | Team Claude/Cursor setup changes |
| `personal_claude_setup` | Claude Setup Ideas | Personal dev environment tweaks |
| `content_create` | Content Ideas | Worth turning into a post |
| `tool_eval` | Tool Eval Tracker | Evaluate a tool or vendor |
| `work_productivity` | Twitter Insights | Stays for manual review |
| `research_read_later` | Twitter Insights | Stays for manual review |
| `market_competitor` | Twitter Insights | Stays for manual review |

You bookmark. Lyra routes. Automations fire.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                           X / TWITTER                            │
│                    (Your bookmarks live here)                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │ OAuth2 + Refresh Token
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    FETCH SCRIPT (Cron 7am)                       │
│         fetch-twitter-bookmarks.sh on Hetzner VPS                │
│                                                                  │
│  • Refreshes OAuth2 token (auto-rotates)                         │
│  • Fetches last 24h of bookmarks                                 │
│  • Saves to /tmp/lyra-bookmarks-YYYY-MM-DD.json                 │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NOTION SYNC SCRIPT                            │
│                  bookmarks-to-notion.sh                          │
│                                                                  │
│  • Deduplicates by tweet URL                                     │
│  • Creates page per bookmark                                     │
│  • Sets Status: Draft, Needs review: true                        │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                 NOTION: Twitter Insights DB                      │
│                                                                  │
│  18 fields including:                                            │
│  • Content Byte (title)          • Primary workflow              │
│  • Original Tweet URL            • Workflow confidence           │
│  • Author, Bookmarked Date       • Needs review                  │
│  • Tags, Status                  • Content mode                  │
│  • Workflow (multi-select)       • Workflow rationale            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              CLASSIFY & ROUTE SCRIPT                             │
│                  classify-and-route.sh                           │
│                                                                  │
│  For each unprocessed bookmark (Needs review = true):            │
│  1. Call Claude API to classify into workflow route              │
│  2. Update Twitter Insights with classification                  │
│  3. Route to destination database based on primary workflow      │
│  4. Mark as processed                                            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
       ┌───────────────────┼───────────────────┬───────────────────┐
       ▼                   ▼                   ▼                   ▼
┌────────────┐      ┌────────────┐      ┌────────────┐      ┌────────────┐
│   Lyra     │      │   Claude   │      │  Content   │      │   Tool     │
│  Backlog   │      │   Setup    │      │   Ideas    │      │   Eval     │
│            │      │   Ideas    │      │            │      │  Tracker   │
│ lyra_      │      │ work_/     │      │ content_   │      │ tool_eval  │
│ capability │      │ personal_  │      │ create     │      │            │
└────────────┘      └────────────┘      └────────────┘      └────────────┘
```

---

## Quick Start

### Prerequisites

- X Developer account (free tier works)
- Notion account + API key
- Linux VPS (Hetzner, DigitalOcean, etc.) — or run locally
- `bash`, `curl`, `jq`, `python3`

### 1. Clone and configure

```bash
git clone https://github.com/ahkedia/twitter-bookmarks-pipeline.git
cd twitter-bookmarks-pipeline
```

### 2. X API OAuth2 setup (one-time)

```bash
export TWITTER_CLIENT_ID='your_client_id'
export TWITTER_CLIENT_SECRET='your_client_secret'
./scripts/get-twitter-oauth-refresh-token.sh start
# Authorize in browser, then:
./scripts/get-twitter-oauth-refresh-token.sh exchange
# Paste callback URL when prompted
```

### 3. Create Notion database

Create a database called "Twitter Insights" with these fields:

| Field | Type |
|-------|------|
| Content Byte | Title |
| Original Tweet URL | URL |
| Author | Text |
| Bookmarked Date | Date |
| Status | Select (Draft/Ready/Published) |
| Needs review | Checkbox |
| Workflow | Multi-select |
| Primary workflow | Select |
| Workflow confidence | Select (High/Medium/Low) |
| ... | (see full schema in docs) |

### 4. Set environment variables

```bash
# ~/.openclaw/.env or export directly
TWITTER_CLIENT_ID="..."
TWITTER_CLIENT_SECRET="..."
TWITTER_REFRESH_TOKEN="..."
TWITTER_USER_ID="..."  # numeric ID from tweeterid.com
NOTION_API_KEY="secret_..."
ANTHROPIC_API_KEY="sk-ant-..."  # For classification

# Database IDs (32-char, from Notion URL)
TWITTER_INSIGHTS_DB_ID="..."    # Source: all bookmarks land here
LYRA_BACKLOG_DB_ID="..."        # Destination: lyra_capability
CLAUDE_SETUP_DB_ID="..."        # Destination: work_/personal_claude_setup
CONTENT_IDEAS_DB_ID="..."       # Destination: content_create
TOOL_EVAL_DB_ID="..."           # Destination: tool_eval
```

### 5. Test

```bash
./scripts/fetch-twitter-bookmarks.sh      # Fetch from X API
./scripts/bookmarks-to-notion.sh          # Sync to Twitter Insights
./scripts/classify-and-route.sh           # Classify and route to destination DBs
```

### 6. Add to cron

```bash
# Full pipeline daily at 7am UTC
0 7 * * * /path/to/scripts/fetch-twitter-bookmarks.sh && \
          /path/to/scripts/bookmarks-to-notion.sh && \
          /path/to/scripts/classify-and-route.sh
```

---

## Workflow Routing

The real power is classification. Each bookmark gets analyzed and routed:

| Primary Workflow | Meaning | Downstream Action |
|------------------|---------|-------------------|
| `lyra_capability` | Improves my AI assistant | Add to Lyra improvement backlog |
| `work_claude_setup` | Improves team Claude/Cursor setup | Draft rule or skill PR |
| `personal_claude_setup` | Improves personal dev setup | Add to personal dotfiles backlog |
| `work_productivity` | Work process improvement | Add to OKR tracking |
| `content_create` | Worth turning into my own post | Generate content byte + add to queue |
| `research_read_later` | Deep read for later | Add to Readwise/research DB |
| `tool_eval` | Evaluate a tool or vendor | Start eval doc |
| `market_competitor` | Market/competitor intel | Add to intel database |

The classification uses:
- Tweet text content
- Author context
- Your personal context (from SOUL.md / MEMORY.md)
- Historical patterns

---

## Cost

| Component | Cost |
|-----------|------|
| X API (Pay-Per-Use) | ~$0.01-0.03/day |
| Anthropic API (classification) | ~$0.01-0.05/day |
| Notion API | Free |
| VPS (optional) | €6/month |
| **Total** | **< $10/month** |

---

## Files

```
scripts/
├── fetch-twitter-bookmarks.sh    # Fetches bookmarks via X API
├── bookmarks-to-notion.sh        # Syncs JSON to Twitter Insights DB
├── classify-and-route.sh         # Classifies & routes to destination DBs
├── get-twitter-oauth-refresh-token.sh  # One-time OAuth setup
└── run-with-openclaw-env.sh      # Loads env vars for cron

docs/
├── TWITTER-X-API-SETUP-STEPS.md  # Step-by-step X API guide
└── NOTION-SETUP.md               # Notion database schema

blog/
└── twitter-bookmarks-as-workflow-triggers.md  # The story behind this
```

---

## Part of Lyra AI

This pipeline is a component of [Lyra AI](https://github.com/ahkedia/lyra-ai) — a personal AI chief of staff that runs 24/7, manages my household, and coordinates with my wife.

The twitter-synthesis skill in Lyra takes this pipeline further:
- Generates 3-style content bytes (Problem-Solving, Thought Leadership, Journey-Based)
- Cross-correlates with your recent work
- Suggests Claude setup improvements
- Surfaces patterns across bookmarks

---

## License

MIT — use it, fork it, make it yours.

---

*Built by [Akash Kedia](https://x.com/UnfilteredAkash) · Read the [blog post](blog/twitter-bookmarks-as-workflow-triggers.md)*
