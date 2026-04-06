# Notion Twitter Insights Database Setup

Create a database called **Twitter Insights** with these properties:

## Required Fields

| Property | Type | Options/Notes |
|----------|------|---------------|
| **Content Byte** | Title | Auto-filled with tweet summary |
| **Original Tweet URL** | URL | Link to tweet on X |
| **Original Tweet Summary** | Text | Full tweet text |
| **Author** | Text | "Name (@username)" |
| **Bookmarked Date** | Date | When you bookmarked |
| **Status** | Select | Draft, Ready, Published |
| **Needs review** | Checkbox | True when classification uncertain |

## Workflow Classification Fields

| Property | Type | Options |
|----------|------|---------|
| **Workflow** | Multi-select | lyra_capability, work_claude_setup, personal_claude_setup, work_productivity, content_create, research_read_later, tool_eval, market_competitor |
| **Primary workflow** | Select | Same 8 options as above |
| **Workflow confidence** | Select | High, Medium, Low |
| **Content mode** | Select | Quote OK, Commentary only, N/A |
| **Workflow rationale** | Text | One-line explanation |

## Optional Fields

| Property | Type | Notes |
|----------|------|-------|
| **Tags** | Multi-select | AI, Startup, Product, Career, Tech, etc. |
| **Style** | Select | Problem-solving, Thought Leadership, Journey-based |
| **Recruiter Ready** | Checkbox | Good for outreach |
| **Recruiter Notes** | Text | How to use in conversations |
| **Full Byte** | Text | Generated content byte |
| **Processed Date** | Date | When Lyra processed |

## Getting the Database ID

1. Open your Twitter Insights database in Notion
2. Look at the URL: `https://notion.so/workspace/[DATABASE_ID]?...`
3. Copy the 32-character ID (before the `?`)
4. Add to your environment: `TWITTER_INSIGHTS_DB_ID="..."`

## Integration Access

Make sure your Notion integration has access:
1. Open the database
2. Click **⋯** → **Connections**
3. Add your integration
