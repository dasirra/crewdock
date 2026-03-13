# Scouter Agent Design

**Date:** 2026-03-13
**Status:** Draft
**Topic:** Scouter -- intelligence radar and personal brand ghostwriter agent for OpenClaw NAS

## Goal

Create Scouter, an OpenClaw agent that runs on Discord (channel: "The Watchtower") combining two missions: (1) staying on top of everything relevant in AI, LLMs, repos, tools, and tech, and (2) converting that intelligence into engagement opportunities for Daniel's personal brand on Twitter/X.

## Constraints

- Same packaging pattern as Forge (`agents/scouter/` with `.example` files for personal config).
- Uses OpenClaw native tools only: `X-Api` skill for Twitter/X, HTTP/browser tools for RSS/web.
- No automatic publishing. Daniel publishes manually after approving drafts.
- Must be distributable: anyone can install Scouter, fill in their voice profile and sources, and run it.

## Prerequisites

- **X-Api skill**: Confirm the X-Api skill exists in the OpenClaw ecosystem and supports reading timelines, searching tweets, and fetching mentions. If unavailable, implement Twitter/X integration via direct HTTP calls to X API v2 with OAuth tokens stored in config.
- **Gateway cron**: Scouter needs a cron heartbeat registered with the gateway, same mechanism Forge uses.
- **setup.sh generalization**: Currently hard-codes Forge DB init. Must be updated to support multiple agents.

## Architecture

Scouter is a standard OpenClaw agent registered in the gateway. It lives alongside Forge in the same container, sharing the gateway runtime, Discord connection, and volume mounts.

```
openclaw-gateway container
├── Echo (Telegram) ........... personal assistant
├── Forge (Discord: The Forge)  autonomous developer
└── Scouter (Discord: The Watchtower)
    ├── Cron heartbeats ........ per-source configurable schedule
    ├── X-Api skill ............ Twitter/X feed consumption
    ├── HTTP/browser tools ..... RSS and web scraping
    └── SQLite (scouter.db) .... state tracking
```

No additional containers or services required.

## Data Sources

Scouter consumes from two channels, each source with its own configurable schedule.

### Twitter/X (via X-Api skill)

- **Curated lists**: accounts Daniel follows in AI/tech (defined as X lists in config)
- **Keyword searches**: terms like "new LLM", "open source AI", "AI agent", tool names
- **Mentions**: any mention of Daniel's account

### RSS/Web (via gateway HTTP/browser tools)

- **Tech blogs**: Anthropic, OpenAI, Google DeepMind, Hugging Face, etc.
- **Aggregators**: HackerNews (front page), Lobste.rs, Product Hunt (AI/dev tools)
- **Repos**: GitHub Trending (filtered by language/topic)
- **Newsletters/indie blogs**: configurable via RSS URLs

### Source configuration

Each source defines its own scan schedule. Scouter runs a **single cron heartbeat** (e.g., every 15 minutes, like Forge). On each heartbeat, it checks which sources are due based on their `schedule` field and the `last_scanned_at` timestamp in SQLite. Only due sources are queried. This is the same pattern as Forge (single cron, internal schedule matching), not one cron job per source.

Schedule format uses Forge-style strings: `"every-30m"`, `"every-4h"`, `"twice-daily"`, `"daily-at-10"`, or hour ranges like `"09-18"`.

```json
{
  "sources": {
    "twitter": {
      "schedule": "every-30m",
      "lists": ["ai-leaders"],
      "keywords": ["new LLM", "open source AI"],
      "mentions": true
    },
    "rss": [
      { "name": "Anthropic Blog", "url": "https://...", "schedule": "twice-daily" },
      { "name": "HackerNews Best", "url": "https://...", "schedule": "every-4h" }
    ],
    "web": [
      { "name": "GitHub Trending", "url": "https://...", "schedule": "daily-at-10" }
    ]
  }
}
```

Web sources are fetched using the gateway's browser tool (headless scraping). RSS sources are fetched via HTTP and parsed as XML feeds.

## Operation Cycle

### Cron heartbeat (per-source schedule)

Each source fires on its own schedule. When a scan finds new content:

1. **Collect**: query the source for content since last scan
2. **Filter**: discard noise (mass retweets, low-signal posts, duplicates via hash check in SQLite)
3. **Classify**: assign each piece to one of two categories:
   - **Briefing**: informative content to keep Daniel up to date
   - **Opportunity**: a post where Daniel could engage with value (reply, comment, quote tweet)
4. **Draft**: for each opportunity, generate a response/comment draft in Daniel's voice (from `USER.md`)
5. **Report**: post a structured summary to The Watchtower on Discord

### Discord report format

```
Scan 14:30

-- BRIEFING --
- Anthropic launches Claude 4.5 Opus with... [link]
- New repo: agent-toolkit by LangChain... [link]
- HN trending: "Why I switched from..." [link]

-- OPPORTUNITIES --
1. @karpathy posted: "Still surprised nobody has..."
   > Draft: "Actually, we've been building exactly this..."
   Approve | Edit | Discard

2. Trending thread on AI agents in production
   > Draft: "Running autonomous agents 24/7 on a NAS..."
   Approve | Edit | Discard
```

Reports only appear when there is new content. No empty reports. If a scan yields more than 10 briefing items, truncate to top 10 by relevance and add a "N more items" note. Opportunities are never truncated.

### Approve/Edit/Discard flow

Opportunities are presented as text in Discord. Daniel interacts via text commands:
Each report assigns sequential numbers (1, 2, 3...) to opportunities within that report. Scouter maps these to SQLite IDs internally.

- **"approve 1"**: marks opportunity #1 from the latest report as approved. Scouter replies with the final text formatted for easy copy-paste into Twitter/X.
- **"edit 1 [new text]"**: replaces the draft with Daniel's version, marks as edited, and replies with the final text.
- **"discard 1"**: marks as discarded, no further action.

There is no automatic publishing. The "approve" action simply surfaces the final text for manual copy-paste. If Discord buttons/reactions are supported by the gateway in the future, they can replace text commands without changing the underlying flow.

### Concurrency

Scouter runs a single heartbeat (not parallel sessions like Forge). If a scan is still running when the next heartbeat fires, the heartbeat skips (checked via a simple lock flag in SQLite or a "scanning" status). This prevents duplicate reports and SQLite write conflicts.

### Interactive mode (on demand)

Daniel can send commands in Discord:

- **"analyze [url/post]"**: Scouter analyzes the content and generates a response draft
- **"write about [topic]"**: generates an original post about a topic
- **"daily summary"**: consolidated briefing of everything relevant from the day
- **"add feed [url]"** / **"remove keyword [x]"**: source management (these are explicit user commands, so config mutation is authorized per the same rule as Forge: only when the user explicitly asks)
- **"status"**: current config, last scan times, stats

## Voice and Personal Brand

### USER.md

The voice profile lives in `USER.md` (same pattern as Forge). It defines:

- **Who Daniel is**: technical founder, builder, interested in applied AI and autonomous agents
- **Tone**: direct, technical but accessible, opinionated with substance. No empty hype.
- **Language**: English for Twitter/X (global audience)
- **Do**: share real building experience, substantiated opinions, acknowledge others' work, dry humor
- **Don't**: engagement bait, unfounded hot takes, aggressive promotion, excessive emojis

Distributed as `USER.example.md` with sections for each user to fill in. This differs from Forge, which ships `USER.md` directly (with empty fields). The `.example` pattern is intentionally better for distribution: it prevents `make setup` from overwriting a user's customized voice profile on reinstall.

### Calibration

Calibration is **manual, informed by data**. Scouter does not autonomously modify its own prompts or behavior. Instead:

- `scouter-db.sh stats` shows approve/edit/discard rates per source and overall.
- Daniel reviews these periodically and adjusts `SOUL.md` (prompt tuning), `USER.md` (voice refinement), or `config.json` (source priorities) based on the data.
- High discard rate on a source suggests removing it or adjusting keywords.
- Consistent edits in tone suggest updating the voice profile in `USER.md`.

## Persistence (SQLite)

`scouter.db` with three tables, managed by `scouter-db.sh` (same pattern as `forge-db.sh`).

### scouter-db.sh commands

| Command | Description |
|---------|-------------|
| `init` | Create tables if not exist |
| `scan <source> <source_name> <hash> <url> <title>` | Record a scanned item, returns ID |
| `is-scanned <hash>` | Check if content hash already processed (exit 0 = yes, 1 = no) |
| `opportunity <scanned_item_id> <original_post> <draft>` | Create opportunity (status: pending) |
| `resolve <id> <status> [edited_text]` | Mark opportunity as approved/edited/discarded |
| `pending` | List pending opportunities |
| `stats [days]` | Show approve/edit/discard rates (default: 30 days) |
| `cleanup <days>` | Delete scanned_items older than N days (default: 90) |
| `lock` | Set scan lock (prevents concurrent runs) |
| `unlock` | Release scan lock |
| `is-locked` | Check lock status (exit 0 = locked, 1 = unlocked) |

Data retention: `cleanup` should be called periodically (e.g., in the heartbeat) to prune scanned_items older than 90 days. Opportunities are kept indefinitely for calibration data.

### scanned_items
Tracks processed content to avoid duplicates.
- `id` INTEGER PRIMARY KEY
- `source` TEXT (twitter, rss, web)
- `source_name` TEXT (specific feed/list name)
- `content_hash` TEXT UNIQUE
- `url` TEXT
- `title` TEXT
- `scanned_at` DATETIME

### opportunities
Tracks engagement opportunities and their lifecycle.
- `id` INTEGER PRIMARY KEY
- `scanned_item_id` INTEGER REFERENCES scanned_items
- `original_post` TEXT
- `draft` TEXT
- `status` TEXT (pending, approved, edited, discarded)
- `edited_text` TEXT (if Daniel edited the draft)
- `created_at` DATETIME
- `resolved_at` DATETIME

There is no `daily_stats` table. Stats are computed on demand by `scouter-db.sh stats` directly from the `scanned_items` and `opportunities` tables. This avoids redundancy and keeps the schema simple.

## File Structure

```
agents/scouter/
├── IDENTITY.md              # Name, role, one-liner
├── SOUL.md                  # Full behavior spec, constraints, commands
├── USER.example.md          # Voice profile template (user fills in)
├── AGENTS.md                # Workflow summary and config reference
├── TOOLS.md                 # Available tools and usage notes (X-Api, HTTP, browser)
├── HEARTBEAT.md             # Cron registration (single heartbeat, e.g. every 15m)
├── scan-template.md         # Scan cycle instructions with {{source}}, {{schedule}} placeholders
├── config.example.json      # Source config template
├── scouter-db.sh            # SQLite helper (init, insert, query, stats)
```

### Setup and installation

`setup.sh` already copies `agents/*` to `workspace/agents/`. Scouter follows the same flow:

1. `make setup` copies `agents/scouter/` to `workspace/agents/scouter/`
2. Renames `.example` files: `USER.example.md` to `USER.md`, `config.example.json` to `config.json`
3. Runs `scouter-db.sh init` to create tables
4. Daniel edits `USER.md` (voice) and `config.json` (sources)

**Note:** `setup.sh` currently hard-codes Forge's DB initialization. It needs to be generalized to loop over all `agents/*/\*-db.sh` scripts, or Scouter's init must be added explicitly.

### Config resolution

Same as Forge: source-level overrides -> top-level defaults -> built-in fallbacks.

## Distribution

### Reusable (the agent)
- `IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `TOOLS.md`, `HEARTBEAT.md`, `scan-template.md`, `scouter-db.sh`

### Personal (user fills in)
- `USER.example.md` (voice, tone, topics, language)
- `config.example.json` (sources, keywords, lists, schedules)

Anyone can install Scouter by cloning the repo, running `make setup`, filling in their voice profile and sources, and they have their own intelligence radar and ghostwriter.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| X-Api rate limits | Missed tweets | Respect rate limits in scan schedule, cache results in SQLite |
| RSS feeds change format | Broken parsing | Graceful error handling, skip broken feeds, notify in Discord |
| Low-quality drafts | Daniel wastes time editing | Calibration loop via approve/edit/discard metrics, refine SOUL.md prompts |
| Too many notifications | Discord noise | Only report when new content exists, configurable thresholds for opportunity detection |
| Duplicate content across sources | Noise | Content hash dedup in scanned_items table |
| X-Api skill unavailable | Cannot read Twitter | Fallback: direct HTTP calls to X API v2 using gateway HTTP tools with OAuth tokens from config |
