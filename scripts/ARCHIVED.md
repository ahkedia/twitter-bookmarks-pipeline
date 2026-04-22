# Archived — bash scripts deprecated 2026-04-22

The bash pipeline (`fetch-twitter-bookmarks.sh`, `bookmarks-to-notion.sh`,
`classify-and-route.sh`, `write-bookmark-to-wiki.sh`, `learn-exemplars.sh`,
`apply-claude-setup.sh`) was superseded by a single Python script:

**`lyra-ai/scripts/twitter_bookmarks.py`** (+ `learn_exemplars.py`, `classifier-exemplars.json`)

The Python version is:
- Unified (fetch + classify + write + route + wiki in one process)
- Multi-label (primary + secondary workflows, fans out to all matched DBs)
- Voice-aware (Sonnet classifier with exemplars + regex tier-1 shortcut)
- Observable (CSV audit log at `/var/log/lyra-classification.csv`)
- Self-improving (nightly learner harvests manual "Correct route" overrides)

See `lyra-ai/scripts/twitter_bookmarks.py` for source.
See this repo's `CLAUDE.md` for the full pipeline overview.

## Why these were kept
- `fetch-twitter-bookmarks.sh` and `get-twitter-oauth-refresh-token.sh` remain in
  `lyra-ai/scripts/` as a manual bash debug path (never run by cron).

## Why everything else was removed
The bash classify/route/wiki/learner scripts never ran in production. The cron
always pointed at `twitter_bookmarks.py`. Keeping dead parallel implementations
around caused the confusion this archive marker is trying to prevent.
