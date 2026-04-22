# Notion Destination DB Field Mapping

Each destination DB uses a different title/source field name (historical accident). Until the DBs are migrated to a canonical schema, `classify-and-route.sh` uses this mapping.

| Workflow | DB | Title field | URL field | Extra fields |
|---|---|---|---|---|
| `lyra_capability` | Lyra Backlog | `Idea` | `Source` | `Status=Idea`, `Notes`, `From Bookmark=true` |
| `work_claude_setup` | Claude Setup Ideas | `Idea` | `Source` | `Scope=work`, `Status=Ready`, `Notes`, `From Bookmark=true` |
| `personal_claude_setup` | Claude Setup Ideas | `Idea` | `Source` | `Scope=personal`, `Status=Idea`, `Notes`, `From Bookmark=true` |
| `tool_eval` | Tool Eval Tracker | `Tool` | `Source` | `Decision=Evaluate`, `Notes`, `From Bookmark=true` |
| `content_create` | Content Topic Pool | `Topic` | `Source Reference` | `Source=Twitter`, `Domain=General`, `Score=6`, `Status=Candidate`, `Week` |
| `work_productivity` | — | — | — | stays in Twitter Insights |
| `research_read_later` | — | — | — | stays in Twitter Insights |
| `market_competitor` | — | — | — | stays in Twitter Insights |

## Canonical schema (target state)
All destination DBs should eventually use: `Title` (title), `SourceURL` (url), `FromBookmark` (checkbox), `BookmarkRationale` (rich_text). Migration is tracked separately.

## Twitter Insights source DB — schema additions required
To enable multi-label routing, audit logging, and the learner, add the following columns in Notion (manual one-time setup):

| Property | Type | Purpose |
|---|---|---|
| `Workflow` | multi_select | All matched workflows (primary + secondary). Options: `lyra_capability`, `work_claude_setup`, `personal_claude_setup`, `work_productivity`, `content_create`, `research_read_later`, `tool_eval`, `market_competitor` |
| `Primary workflow` | select | Highest-confidence match (existing column — keep) |
| `Workflow confidence` | select | `High` / `Medium` / `Low` |
| `Workflow rationale` | rich_text | One-sentence reason from classifier |
| `Correct route` | select | **Manual override** — you fill this when the classifier got it wrong. Same options as `Workflow`. Picked up by `learn-exemplars.sh`. |
| `Exemplar harvested` | checkbox | Set by learner after exemplar is saved. Prevents re-harvesting. |
| `Wiki stub path` | rich_text | Path to the personal-kb-raw stub (set when `content_create` route fires). |
