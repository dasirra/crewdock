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

Each source defines its own scan schedule:

```json
{
  "sources": {
    "twitter": {
      "schedule": "*/30 * * * *",
      "lists": ["ai-leaders"],
      "keywords": ["new LLM", "open source AI"],
      "mentions": true
    },
    "rss": [
      { "name": "Anthropic Blog", "url": "https://...", "schedule": "0 9,18 * * *" },
      { "name": "HackerNews Best", "url": "https://...", "schedule": "0 */4 * * *" }
    ],
    "web": [
      { "name": "GitHub Trending", "url": "https://...", "schedule": "0 10 * * *", "scrape": true }
    ]
  }
}
```

Schedule format follows whatever the gateway supports (cron expressions or gateway-native format like Forge's `"HH-HH"` patterns).

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

Reports only appear when there is new content. No empty reports.

### Interactive mode (on demand)

Daniel can send commands in Discord:

- **"analyze [url/post]"**: Scouter analyzes the content and generates a response draft
- **"write about [topic]"**: generates an original post about a topic
- **"daily summary"**: consolidated briefing of everything relevant from the day
- **"add feed [url]"** / **"remove keyword [x]"**: source management
- **"status"**: current config, last scan times, stats

## Voice and Personal Brand

### USER.md

The voice profile lives in `USER.md` (same pattern as Forge). It defines:

- **Who Daniel is**: technical founder, builder, interested in applied AI and autonomous agents
- **Tone**: direct, technical but accessible, opinionated with substance. No empty hype.
- **Language**: English for Twitter/X (global audience)
- **Do**: share real building experience, substantiated opinions, acknowledge others' work, dry humor
- **Don't**: engagement bait, unfounded hot takes, aggressive promotion, excessive emojis

Distributed as `USER.example.md` with sections for each user to fill in.

### Calibration

Over time, Scouter learns from edits. The approve/edit/discard data in SQLite provides a feedback signal:
- High discard rate on a source = lower priority or remove
- Consistent edits in tone = adjust drafting style
- Approved patterns = reinforce

## Persistence (SQLite)

`scouter.db` with three tables, managed by `scouter-db.sh` (same pattern as `forge-db.sh`):

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

### daily_stats
Aggregate metrics for calibration.
- `date` DATE PRIMARY KEY
- `total_scanned` INTEGER
- `opportunities_detected` INTEGER
- `approved` INTEGER
- `edited` INTEGER
- `discarded` INTEGER

## File Structure

```
agents/scouter/
├── IDENTITY.md              # Name, role, one-liner
├── SOUL.md                  # Full behavior spec, constraints, commands
├── USER.example.md          # Voice profile template (user fills in)
├── AGENTS.md                # Workflow summary and config reference
├── HEARTBEAT.md             # Cron trigger definitions
├── autopilot-template.md    # Scan cycle template
├── config.example.json      # Source config template
├── scouter-db.sh            # SQLite helper (init, insert, query, stats)
```

### Setup and installation

`setup.sh` already copies `agents/*` to `workspace/agents/`. Scouter follows the same flow:

1. `make setup` copies `agents/scouter/` to `workspace/agents/scouter/`
2. Renames `USER.example.md` to `USER.md`, `config.example.json` to `config.json`
3. Runs `scouter-db.sh init` to create tables
4. Daniel edits `USER.md` (voice) and `config.json` (sources)

### Config resolution

Same as Forge: source-level overrides -> top-level defaults -> built-in fallbacks.

## Distribution

### Reusable (the agent)
- `IDENTITY.md`, `SOUL.md`, `AGENTS.md`, `HEARTBEAT.md`, `autopilot-template.md`, `scouter-db.sh`

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
