# AGENTS.md - Scouter

## Workflow

### Cron cycle (heartbeat)

1. Read `SOUL.md` for identity and constraints.
2. Check lock via `scouter-db.sh is-locked`. If locked, skip.
3. Run `scouter-db.sh lock`.
4. Read `config.json` for source list and schedules.
5. For each source, check if due (compare schedule vs `scouter-db.sh last-scan`).
6. For each due source: collect, deduplicate, filter, classify, draft, record.
7. Post Discord report to The Watchtower (only if new content found).
8. Run `scouter-db.sh set-last-scan` for each processed source.
9. Run `scouter-db.sh cleanup` (once daily).
10. Run `scouter-db.sh unlock`.

### Interactive (messages)

Scouter responds to commands from the user:
- `approve <id>` / `edit <id> [text]` / `discard <id>` — manage opportunities
- `analyze [url]` — generate response draft for a specific post
- `write about [topic]` — generate an original post
- `daily summary` — consolidated briefing
- `status` — config overview, last scan times, stats
- `pending` — list pending opportunities
- `add feed/keyword [value]` — add source to config
- `remove feed/keyword [value]` — remove source from config

See SOUL.md for the full command reference.

## Schedule

Single cron heartbeat fires periodically. Per-source schedules in `config.json` control scan frequency.

Schedule format:
- `every-30m` — every 30 minutes
- `every-4h` — every 4 hours
- `twice-daily` — at 09:00 and 18:00
- `daily-at-10` — once at 10:00
- `HH-HH` — hour range (e.g., `09-18`)

## Process management

- Single heartbeat, no parallel sessions (unlike Forge)
- Concurrency via SQLite lock (`scouter-db.sh lock/unlock/is-locked`)
- Stale locks auto-release after 30 minutes (prevents deadlock from crashed scans)
- Content deduplication via SHA-256 hash in `scanned_items` table

## SQLite tracking database

Location: `$HOME/.openclaw/workspace/agents/scouter/scouter.db`
Helper: `$HOME/.openclaw/workspace/agents/scouter/scouter-db.sh`

Tables:
- `meta` — key-value store for lock state and last scan timestamps
- `scanned_items` — processed content (source, hash, url, title, timestamp)
- `opportunities` — engagement opportunities (original post, draft, status, timestamps)

The database prevents:
- Duplicate processing of the same content (hash-based dedup)
- Concurrent scan cycles (lock mechanism)
- Loss of state across restarts

## Config

`config.json`:
```json
{
  "timezone": "Europe/Madrid",
  "sources": {
    "twitter": {
      "schedule": "every-30m",
      "lists": ["ai-leaders"],
      "keywords": ["new LLM", "open source AI"],
      "mentions": true
    },
    "rss": [
      { "name": "Anthropic Blog", "url": "https://...", "schedule": "twice-daily" }
    ],
    "web": [
      { "name": "GitHub Trending", "url": "https://...", "schedule": "daily-at-10" }
    ]
  }
}
```

**Twitter source** (single object, scanned as one unit due to per-app rate limits):
| Field | Required | Description |
|---|---|---|
| `schedule` | Yes | How often to scan |
| `lists` | No | X list IDs to monitor |
| `keywords` | No | Search terms |
| `mentions` | No | Monitor mentions (default: `false`) |

**RSS/Web sources** (array of objects, each with own schedule):
| Field | Required | Description |
|---|---|---|
| `name` | Yes | Display name for reports |
| `url` | Yes | Feed URL or page URL |
| `schedule` | Yes | How often to scan |

## Scan template

`scan-template.md` defines the step-by-step instructions for each scan cycle:
- Collect from due sources (xurl for Twitter, HTTP for RSS, browser for web)
- Deduplicate via content hash
- Filter and classify (LLM evaluation)
- Draft responses for opportunities (following USER.md voice profile)
- Post structured report to Discord

## Reporting

Reports posted to Discord only when new content is found.
- Briefing: max 10 items, "N more" note if truncated
- Opportunities: never truncated, shown with globally unique SQLite IDs
- Format: see SOUL.md for exact template

## Safety
- Scouter modifies `config.json` only when the user explicitly asks.
- Scouter never publishes to Twitter/X or any platform. Drafts are for manual copy-paste.
- If config.json is missing or empty, exit silently on cron.
