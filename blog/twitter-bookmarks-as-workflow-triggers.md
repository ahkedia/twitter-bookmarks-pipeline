# I Turned My Twitter Bookmarks Into Automated Workflows. Here's Why Every Builder Should.

*Or: The Bookmark Button Is the Most Underrated AI Input Device.*

---

**Tuesday, 11:47pm.** I'm scrolling Twitter in bed. I see a thread about Claude Code workflows that could make my team's repo faster. Bookmark. A hot take about AI product management worth responding to. Bookmark. A new MCP tool I want to evaluate. Bookmark.

I fall asleep. The bookmarks sit there. Two weeks later, I've forgotten why I saved any of them.

Sound familiar?

I fixed this. Now every bookmark I save automatically routes to the right workflow — some become Lyra improvements, others become content drafts, others start vendor evaluations. I don't review a queue. I don't batch-process on Sundays. The moment I bookmark, the pipeline takes over.

This post is about how I built it, why the classification layer matters more than the fetch, and how you can use the same architecture to turn your bookmarks into automated workflows.

---

## The problem isn't saving — it's routing

Twitter bookmarks are a graveyard of good intentions. You save something because it felt important in the moment. Then it joins 500 other saved tweets in a list you'll never systematically review.

The problem isn't capture. The problem is: **what happens next?**

Most people's mental model:

```
Bookmark → Queue → (eventually) Manual review → Maybe action
```

This is a leaky bucket. Friction kills follow-through.

What I wanted:

```
Bookmark → Classify → Route → Automated action (or at least: right queue)
```

The bookmark button should be an **input device**, not a storage endpoint.

---

## What happens when I bookmark now

**10:23pm.** I bookmark a tweet about improving Claude Code's UI capabilities with a new skills repo.

**7:02am next morning.** Lyra's fetch script pulls my last 24 hours of bookmarks.

**7:03am.** The classify-and-route script calls Claude API to classify it:

> **Primary workflow:** `lyra_capability`  
> **Confidence:** High  
> **Rationale:** "Tweet describes a skills repo for Claude Code UI — directly maps to improving Lyra's gateway capabilities."

**7:04am.** The bookmark appears in my Notion "Twitter Insights" database with:
- Full tweet text
- Author and URL
- Classification: `lyra_capability`
- Status: Processed

**7:05am.** Because it's tagged `lyra_capability`, it automatically gets routed to my **Lyra Backlog** database. On Sunday, my weekly synthesis includes: "3 new capability ideas from Twitter this week."

I didn't do anything except bookmark.

---

## The eight workflow routes

Here's how every bookmark gets classified:

| Route | What it means | What happens automatically |
|-------|--------------|---------------------------|
| `lyra_capability` | Improves my AI assistant (Lyra) | → Lyra improvement backlog |
| `work_claude_setup` | Improves my employer's Claude/Cursor setup | → Team tooling queue |
| `personal_claude_setup` | Improves my personal dev environment | → Dotfiles/rules backlog |
| `work_productivity` | Work process, leadership, scaling | → Weekly reflection topics |
| `content_create` | Worth turning into my own post | → Content queue + draft byte |
| `research_read_later` | Deep read, no immediate action | → Research database |
| `tool_eval` | Evaluate a tool or vendor | → Vendor eval tracker |
| `market_competitor` | Market or competitor intel | → Intel database |

The classifier uses multiple signals:
- **Keywords:** "OpenClaw," "skill," "MCP" → likely `lyra_capability`
- **Author context:** Founder talking about growth → maybe `work_productivity` or `content_create`
- **My historical patterns:** I've bookmarked 12 Claude Code threads this month → probably `work_claude_setup` or `lyra_capability`
- **Tone:** Strong opinion, thread worth engaging → maybe `content_create`

When confident, the system routes silently. When uncertain, it sets `needs_review: true` and I check it during my morning digest.

---

## The architecture

```
┌─────────────┐     OAuth2      ┌─────────────────────┐
│  X/Twitter  │ ◄──────────────►│  fetch-twitter-     │
│  Bookmarks  │                 │  bookmarks.sh       │
└─────────────┘                 │  (cron 7am)         │
                                └──────────┬──────────┘
                                           │ JSON
                                           ▼
                                ┌─────────────────────┐
                                │  bookmarks-to-      │
                                │  notion.sh          │
                                └──────────┬──────────┘
                                           │
                                           ▼
                                ┌─────────────────────┐
                                │  Notion: Twitter    │
                                │  Insights DB        │
                                └──────────┬──────────┘
                                           │
                                           ▼
                                ┌─────────────────────┐
                                │  classify-and-      │
                                │  route.sh           │
                                │                     │
                                │  • Claude API call  │
                                │  • Classify route   │
                                │  • Route to dest DB │
                                └──────────┬──────────┘
                                           │
      ┌────────────────┬───────────────────┼───────────────────┬────────────────┐
      ▼                ▼                   ▼                   ▼                ▼
┌───────────┐   ┌───────────┐       ┌───────────┐       ┌───────────┐   ┌───────────┐
│   Lyra    │   │  Claude   │       │  Content  │       │   Tool    │   │ (stays in │
│  Backlog  │   │  Setup    │       │   Ideas   │       │   Eval    │   │ Insights) │
│           │   │   Ideas   │       │           │       │  Tracker  │   │           │
└───────────┘   └───────────┘       └───────────┘       └───────────┘   └───────────┘
lyra_capability  work_/personal_    content_create      tool_eval        others
                 claude_setup
```

**Cost:** ~$0.01-0.03/day for X API (pay-per-use), Notion free, VPS €6/month.

---

## Why I care about the classification layer

The fetch script took 30 minutes to build. OAuth debugging took 2 hours. But the classification layer — that's where the leverage is.

Without classification, you have a bookmark sync. Nice but not transformative. You still need to manually review every item.

With classification, you have **intent-aware automation**. The system knows:

- This bookmark is about improving my tools → it belongs in a specific backlog
- This one is about market dynamics → it goes to intel
- This one is a hot take I should respond to → it gets a content byte and goes to my posting queue

The classification layer is what turns passive capture into active workflow.

---

## The content byte generator

When a bookmark is classified as `content_create`, the synthesis skill generates three content bytes:

**Problem-Solving format:**
> "Here's the problem: [from tweet]. Here's how I solved it: [my angle]. Why it matters: [business impact]."

**Thought Leadership format:**
> "Hot take: [from tweet]. In practice: [my perspective]. What I'm watching: [related trend]."

**Journey-Based format:**
> "Inspired by this insight: [from tweet]. My approach: [how I'm applying it]. What I learned: [key lesson]."

These aren't final posts. They're drafts that capture the essence while I still remember why I bookmarked. I can edit and post, or let them age and delete.

The point: I never look at a bookmark two weeks later and think "why did I save this?"

---

## What I learned building this

**1. Bookmarks are high-signal, low-friction inputs.**  
You don't bookmark casually. Something caught your attention. That signal is valuable — don't waste it by dumping it into a queue you'll never process.

**2. Classification unlocks automation.**  
Without routing, every item needs manual triage. With routing, 80% of items can flow automatically to the right place.

**3. "Needs review" is the escape hatch.**  
The system doesn't need to be perfect. It needs to be confident when it's right and honest when it's not. Low-confidence items get flagged. High-confidence items flow.

**4. The bookmark button becomes an input device.**  
You're training the system with every bookmark. Over time, it learns your patterns. The classification gets better because it has more context about what you care about.

---

## Why you should build this

If you're a builder who:
- Uses Twitter/X for professional signal
- Has a backlog of bookmarks you never process
- Wants to automate more of your knowledge workflow

...this architecture is worth stealing.

The scripts are simple bash. The Notion schema is 18 fields. The classification layer can be as simple as keyword matching or as sophisticated as LLM synthesis.

Start with the fetch + sync. Add classification later. Even without the AI layer, having your bookmarks in Notion with structured fields is better than the native bookmark UI.

---

## The honest numbers

- **Setup time:** ~2 hours (mostly OAuth debugging)
- **Daily cost:** $0.01-0.05 (X API pay-per-use)
- **Bookmarks processed:** 34 in first run, ~3-5 per day typical
- **Manual review time saved:** ~30 min/week
- **Content bytes generated:** ~2-3 per week that I actually use

---

## Stop treating bookmarks as storage

The bookmark button is not an archive. It's a signal that says: "This matters. Do something with it."

Build the system that does something with it.

Every bookmark becomes a workflow trigger. Every workflow trigger becomes an automated action. The queue becomes a pipeline. The pile becomes a process.

That's what infrastructure looks like.

---

*Full code, Notion schema, and setup guide: [github.com/ahkedia/twitter-bookmarks-pipeline](https://github.com/ahkedia/twitter-bookmarks-pipeline)*

*This pipeline is part of [Lyra AI](https://github.com/ahkedia/lyra-ai), my personal AI chief of staff.*
