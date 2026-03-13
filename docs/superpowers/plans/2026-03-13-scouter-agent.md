# Scouter Agent Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the Scouter agent (intelligence radar + personal brand ghostwriter) as an OpenClaw agent in `agents/scouter/`, following the same packaging pattern as Forge.

**Architecture:** Scouter is a set of markdown files, a config template, and a bash SQLite helper. It runs inside the existing gateway container. No new services or containers. The agent reads Twitter/X via xurl CLI and RSS/web via gateway HTTP/browser tools, then posts reports to Discord.

**Tech Stack:** Bash (scouter-db.sh), SQLite, Markdown (agent definition files), JSON (config), xurl CLI (Twitter/X API v2)

**Spec:** `docs/superpowers/specs/2026-03-13-scouter-agent-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `agents/scouter/IDENTITY.md` | Create | Agent name, role, one-liner |
| `agents/scouter/SOUL.md` | Create | Full behavior spec: cron cycle, interactive commands, constraints |
| `agents/scouter/USER.example.md` | Create | Voice profile template for distribution |
| `agents/scouter/AGENTS.md` | Create | Workflow summary and config reference |
| `agents/scouter/TOOLS.md` | Create | Tool reference (xurl, HTTP, browser, scouter-db.sh, Discord) |
| `agents/scouter/HEARTBEAT.md` | Create | Cron registration (single heartbeat) |
| `agents/scouter/scan-template.md` | Create | Scan cycle template with placeholders |
| `agents/scouter/config.example.json` | Create | Source config template |
| `agents/scouter/scouter-db.sh` | Create | SQLite helper for state tracking |
| `setup.sh` | Modify | Generalize DB init to support multiple agents |
| `Dockerfile` | Modify | Add xurl CLI installation |

---

## Chunk 1: Foundation (SQLite + Config)

### Task 1: Create scouter-db.sh

The SQLite helper is the foundation. Everything else depends on it.

**Files:**
- Create: `agents/scouter/scouter-db.sh`

- [ ] **Step 1: Write scouter-db.sh with all commands**

```bash
#!/usr/bin/env bash
# scouter-db.sh — SQLite helper for Scouter state tracking
# Location: agents/scouter/scouter-db.sh (tracked, copied to workspace on setup)

set -euo pipefail

DB="${SCOUTER_DB:-$HOME/.openclaw/workspace/agents/scouter/scouter.db}"

usage() {
  cat <<'EOF'
Usage: scouter-db.sh <command> [args]

Commands:
  init                                              Create tables if not exist
  scan <source> <source_name> <hash> <url> <title>  Record scanned item, returns ID
  is-scanned <hash>                                 Check if hash processed (exit 0=yes, 1=no)
  opportunity <scanned_item_id> <original> <draft>  Create opportunity (status: pending)
  resolve <id> <status> [edited_text]               Mark approved/edited/discarded
  pending                                           List pending opportunities
  stats [days]                                      Approve/edit/discard rates (default: 30)
  cleanup [days]                                    Delete scanned_items older than N days (default: 90)
  lock                                              Set scan lock
  unlock                                            Release scan lock
  is-locked                                         Check lock (exit 0=locked, 1=unlocked)
  last-scan <source_name>                           Get last scan timestamp for a source
  set-last-scan <source_name>                       Set last scan timestamp to now
EOF
  exit 1
}

db() { sqlite3 "$DB" "$@"; }

esc() { printf '%s' "${1//\'/\'\'}"; }

assert_int() {
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }
}

cmd_init() {
  mkdir -p "$(dirname "$DB")"
  db <<'SQL'
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS scanned_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    source_name TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    url TEXT,
    title TEXT,
    scanned_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_scanned_hash ON scanned_items(content_hash);
CREATE INDEX IF NOT EXISTS idx_scanned_source ON scanned_items(source, source_name);
CREATE INDEX IF NOT EXISTS idx_scanned_at ON scanned_items(scanned_at);

CREATE TABLE IF NOT EXISTS opportunities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scanned_item_id INTEGER REFERENCES scanned_items(id),
    original_post TEXT NOT NULL,
    draft TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending',
    edited_text TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_opp_status ON opportunities(status);
SQL
  echo "DB initialized: $DB"
}

cmd_scan() {
  local source; source=$(esc "$1")
  local source_name; source_name=$(esc "$2")
  local hash; hash=$(esc "$3")
  local url; url=$(esc "$4")
  local title; title=$(esc "$5")
  db "INSERT INTO scanned_items (source, source_name, content_hash, url, title) VALUES ('$source', '$source_name', '$hash', '$url', '$title');"
  db "SELECT last_insert_rowid();"
}

cmd_is_scanned() {
  local hash; hash=$(esc "$1")
  local count
  count=$(db "SELECT COUNT(*) FROM scanned_items WHERE content_hash='$hash';")
  [[ "$count" -gt 0 ]]
}

cmd_opportunity() {
  local item_id="$1"; assert_int "$item_id"
  local original; original=$(esc "$2")
  local draft; draft=$(esc "$3")
  db "INSERT INTO opportunities (scanned_item_id, original_post, draft) VALUES ($item_id, '$original', '$draft');"
  db "SELECT last_insert_rowid();"
}

cmd_resolve() {
  local id="$1"; assert_int "$id"
  local status; status=$(esc "$2")
  if [[ $# -ge 3 ]]; then
    local edited; edited=$(esc "$3")
    db "UPDATE opportunities SET status='$status', edited_text='$edited', resolved_at=datetime('now') WHERE id=$id;"
  else
    db "UPDATE opportunities SET status='$status', resolved_at=datetime('now') WHERE id=$id;"
  fi
}

cmd_pending() {
  db -column -header "SELECT o.id, o.original_post, o.draft, o.created_at, s.source, s.url
      FROM opportunities o
      JOIN scanned_items s ON o.scanned_item_id = s.id
      WHERE o.status='pending'
      ORDER BY o.created_at ASC;"
}

cmd_stats() {
  local days="${1:-30}"
  assert_int "$days"
  echo "=== Scan stats (last $days days) ==="
  db -column -header "SELECT source, source_name, COUNT(*) as items
      FROM scanned_items
      WHERE scanned_at >= datetime('now', '-$days days')
      GROUP BY source, source_name
      ORDER BY items DESC;"
  echo ""
  echo "=== Opportunity stats (last $days days) ==="
  db -column -header "SELECT status, COUNT(*) as count
      FROM opportunities
      WHERE created_at >= datetime('now', '-$days days')
      GROUP BY status;"
}

cmd_cleanup() {
  local days="${1:-90}"
  assert_int "$days"
  local deleted
  deleted=$(db "DELETE FROM scanned_items WHERE scanned_at < datetime('now', '-$days days'); SELECT changes();")
  echo "Cleaned up $deleted scanned items older than $days days."
}

STALE_LOCK_MINUTES=30

cmd_lock() {
  db "INSERT OR REPLACE INTO meta (key, value, updated_at) VALUES ('scan_lock', datetime('now'), datetime('now'));"
}

cmd_unlock() {
  db "DELETE FROM meta WHERE key='scan_lock';"
}

cmd_is_locked() {
  local lock_time
  lock_time=$(db "SELECT value FROM meta WHERE key='scan_lock';")
  if [[ -z "$lock_time" ]]; then
    return 1
  fi
  # Check for stale lock
  local stale
  stale=$(db "SELECT CASE WHEN datetime('$lock_time', '+$STALE_LOCK_MINUTES minutes') < datetime('now') THEN 1 ELSE 0 END;")
  if [[ "$stale" == "1" ]]; then
    db "DELETE FROM meta WHERE key='scan_lock';"
    echo "Stale lock released (was set at $lock_time)." >&2
    return 1
  fi
  return 0
}

cmd_last_scan() {
  local source_name; source_name=$(esc "$1")
  db "SELECT value FROM meta WHERE key='last_scanned_$source_name';"
}

cmd_set_last_scan() {
  local source_name; source_name=$(esc "$1")
  db "INSERT OR REPLACE INTO meta (key, value, updated_at) VALUES ('last_scanned_$source_name', datetime('now'), datetime('now'));"
}

[[ $# -lt 1 ]] && usage

COMMAND="$1"; shift

case "$COMMAND" in
  init)          cmd_init ;;
  scan)          [[ $# -ge 5 ]] && cmd_scan "$1" "$2" "$3" "$4" "$5" || usage ;;
  is-scanned)    if [[ $# -ge 1 ]]; then cmd_is_scanned "$1"; else usage; fi ;;
  opportunity)   [[ $# -ge 3 ]] && cmd_opportunity "$1" "$2" "$3" || usage ;;
  resolve)       [[ $# -ge 2 ]] && cmd_resolve "$@" || usage ;;
  pending)       cmd_pending ;;
  stats)         cmd_stats "${1:-30}" ;;
  cleanup)       cmd_cleanup "${1:-90}" ;;
  lock)          cmd_lock ;;
  unlock)        cmd_unlock ;;
  is-locked)     cmd_is_locked ;;
  last-scan)     [[ $# -ge 1 ]] && cmd_last_scan "$1" || usage ;;
  set-last-scan) [[ $# -ge 1 ]] && cmd_set_last_scan "$1" || usage ;;
  *)             echo "Unknown command: $COMMAND"; usage ;;
esac
```

- [ ] **Step 2: Make it executable and test init**

Run:
```bash
chmod +x agents/scouter/scouter-db.sh
SCOUTER_DB=/tmp/test-scouter.db agents/scouter/scouter-db.sh init
```
Expected: `DB initialized: /tmp/test-scouter.db`

- [ ] **Step 3: Test core commands**

Run:
```bash
export SCOUTER_DB=/tmp/test-scouter.db
# Test scan + dedup
agents/scouter/scouter-db.sh scan twitter ai-leaders abc123 "https://x.com/post/1" "Test post"
agents/scouter/scouter-db.sh is-scanned abc123 && echo "FOUND" || echo "NOT FOUND"
agents/scouter/scouter-db.sh is-scanned xyz999 && echo "FOUND" || echo "NOT FOUND"
# Test opportunity lifecycle
agents/scouter/scouter-db.sh opportunity 1 "Original post text" "Draft reply text"
agents/scouter/scouter-db.sh pending
agents/scouter/scouter-db.sh resolve 1 approved
# Test lock
agents/scouter/scouter-db.sh lock
agents/scouter/scouter-db.sh is-locked && echo "LOCKED" || echo "UNLOCKED"
agents/scouter/scouter-db.sh unlock
agents/scouter/scouter-db.sh is-locked && echo "LOCKED" || echo "UNLOCKED"
# Test last-scan
agents/scouter/scouter-db.sh set-last-scan twitter
agents/scouter/scouter-db.sh last-scan twitter
# Test stats
agents/scouter/scouter-db.sh stats
# Cleanup
rm /tmp/test-scouter.db
```

Expected:
- First `is-scanned`: "FOUND"
- Second `is-scanned`: "NOT FOUND"
- `pending`: shows 1 row with the opportunity
- After resolve: pending shows 0 rows
- Lock/unlock cycle works
- `last-scan` returns a timestamp
- Stats shows counts

- [ ] **Step 4: Commit**

```bash
git add agents/scouter/scouter-db.sh
git commit -m "feat: add scouter-db.sh SQLite helper for Scouter agent"
```

---

### Task 2: Create config.example.json

**Files:**
- Create: `agents/scouter/config.example.json`

- [ ] **Step 1: Write the config template**

```json
{
  "timezone": "Europe/Madrid",
  "sources": {
    "twitter": {
      "schedule": "every-30m",
      "lists": ["ai-leaders"],
      "keywords": ["new LLM", "open source AI", "AI agent"],
      "mentions": true
    },
    "rss": [
      { "name": "Anthropic Blog", "url": "https://www.anthropic.com/rss.xml", "schedule": "twice-daily" },
      { "name": "HackerNews Best", "url": "https://hnrss.org/best", "schedule": "every-4h" }
    ],
    "web": [
      { "name": "GitHub Trending", "url": "https://github.com/trending", "schedule": "daily-at-10" }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/config.example.json
git commit -m "feat: add Scouter config template"
```

---

## Chunk 2: Agent Identity Files

### Task 3: Create IDENTITY.md

**Files:**
- Create: `agents/scouter/IDENTITY.md`

- [ ] **Step 1: Write IDENTITY.md**

Follow Forge's format exactly (same structure, 5 lines).

```markdown
# IDENTITY.md

- **Name:** Scouter
- **Role:** Intelligence radar and personal brand ghostwriter
- **Focus:** AI/tech monitoring and Twitter/X engagement drafting
```

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/IDENTITY.md
git commit -m "feat: add Scouter IDENTITY.md"
```

---

### Task 4: Create SOUL.md

The core behavioral spec. This is the largest file. Follow Forge's SOUL.md structure closely.

**Files:**
- Create: `agents/scouter/SOUL.md`

- [ ] **Step 1: Write SOUL.md**

````markdown
# SOUL.md - Scouter

You are Scouter, an intelligence radar and personal brand ghostwriter. You run on a cron heartbeat and respond to interactive messages.

## Two modes of operation

### 1. Cron cycle (automatic)
A single cron heartbeat fires periodically. On each cycle:
1. Run `scouter-db.sh is-locked`. If locked, skip this cycle.
2. Run `scouter-db.sh lock`.
3. Read `config.json`.
4. For each source, check if it is due: compare the source's `schedule` against `scouter-db.sh last-scan <source_name>`.
5. For each due source, run the scan cycle (see below).
6. Run `scouter-db.sh unlock`.

If no sources are due, unlock and exit silently.

### 2. Interactive (messages from the user)
Handle these operations:

**Engagement:**
- "approve <id>" — mark opportunity as approved. Reply with the final draft text, formatted for easy copy-paste into Twitter/X.
- "edit <id> [new text]" — replace the draft with the user's text, mark as edited. Reply with the final text.
- "discard <id>" — mark as discarded. No further action.

**Content creation:**
- "analyze [url or post text]" — analyze the content and generate a response draft
- "write about [topic]" — generate an original post about a topic

**Information:**
- "daily summary" — consolidated briefing of everything scanned today
- "status" — current config, last scan times per source, pending opportunities count, approve/discard rates
- "pending" — list all pending opportunities

**Config management:**
- "add feed [url]" — add an RSS source to config.json
- "add keyword [term]" — add a Twitter keyword to config.json
- "remove feed [name]" — remove an RSS source
- "remove keyword [term]" — remove a Twitter keyword

For any `add`/`remove` command: modify config.json. Changes take effect on the next heartbeat.

## Schedule format

Per-source schedules determine when each source is scanned:
- `every-30m` — every 30 minutes
- `every-4h` — every 4 hours
- `twice-daily` — at 09:00 and 18:00 in the configured timezone
- `daily-at-10` — once daily at 10:00
- `HH-HH` — active during this hour range (e.g., `09-18`)

To check if a source is due: read its `schedule`, get `scouter-db.sh last-scan <source_name>`. If enough time has elapsed (or no previous scan exists), the source is due.

All times are interpreted in the `timezone` from config.json.

## Scan cycle

For each due source:

1. **Collect** content:
   - **Twitter** (`twitter`): use xurl CLI.
     - Lists: `xurl api get /2/lists/:id/tweets` for each list ID
     - Keywords: `xurl api get /2/tweets/search/recent?query=<keyword>` for each keyword
     - Mentions: `xurl api get /2/users/:id/mentions` if `mentions: true`
     - If xurl returns a rate limit error, skip Twitter for this cycle and note in the report.
   - **RSS** (`rss`): use the gateway HTTP tool to fetch the feed URL. Parse XML for `<item>` or `<entry>` elements.
   - **Web** (`web`): use the gateway browser tool to load the page and extract relevant items.

2. **Deduplicate**: for each collected item, compute SHA-256 hash of the URL. Run `scouter-db.sh is-scanned <hash>`. Skip items already processed. For new items: `scouter-db.sh scan <source> <source_name> <hash> <url> <title>`.

3. **Filter**: evaluate each new item for relevance. Discard:
   - Off-topic content (not related to AI, LLMs, tools, tech, or the user's topics from USER.md)
   - Spam, memes, promotional content
   - Retweets or reposts with no added commentary
   - Low-substance content (one-word reactions, emoji-only posts)

4. **Classify** each surviving item:
   - **Briefing**: informative and relevant, but not a natural engagement opportunity for the user
   - **Opportunity**: a post where the user could add value by replying, commenting, or quote-tweeting

5. **Draft**: for each opportunity:
   - Read `USER.md` for voice profile, tone, and guidelines
   - Generate a response draft that sounds like the user
   - For Twitter/X replies: keep under 280 characters
   - Follow the Do/Don't rules from USER.md strictly
   - Insert via `scouter-db.sh opportunity <scanned_item_id> <original_post> <draft>`

6. **Report**: post a structured summary to Discord (The Watchtower channel):

```
Scan 14:30

-- BRIEFING --
- Anthropic launches Claude 4.5 Opus with... [link]
- New repo: agent-toolkit by LangChain... [link]
- HN trending: "Why I switched from..." [link]

-- OPPORTUNITIES --
#42. @karpathy posted: "Still surprised nobody has..."
   > Draft: "Actually, we've been building exactly this..."
   approve 42 | edit 42 | discard 42

#43. Trending thread on AI agents in production
   > Draft: "Running autonomous agents 24/7 on a NAS..."
   approve 43 | edit 43 | discard 43
```

   - Only post if there is new content. No empty reports.
   - Truncate briefing to top 10 items by relevance. If more exist, add "and N more items" at the end.
   - Opportunities are never truncated.
   - Opportunity IDs are globally unique SQLite IDs (not sequential per report).

7. **Housekeeping**:
   - `scouter-db.sh set-last-scan <source_name>` for each source processed.
   - `scouter-db.sh cleanup` once daily (skip if already run today).

## Voice
- Direct. Technical. No filler.
- Short summary first, details on request.
- Never say "Great question!" or "Happy to help."

## Constraints
- Only read from sources listed in `config.json`.
- Never publish to Twitter/X or any platform automatically. Always present drafts for user approval.
- You MAY modify `config.json` when the user explicitly asks (add/remove feed/keyword).
- You MUST NOT modify `config.json` autonomously.
- Config changes take effect on the next heartbeat; in-progress scans are not affected.
- If `config.json` is empty or missing: exit silently on cron. On interactive message, tell the user.

## Paths
- Workspace: `/home/node/.openclaw/workspace/agents/scouter/`
- Database: `/home/node/.openclaw/workspace/agents/scouter/scouter.db`
- DB helper: `/home/node/.openclaw/workspace/agents/scouter/scouter-db.sh`
````

- [ ] **Step 2: Verify SOUL.md covers all spec requirements**

Cross-reference with the spec. Check: schedule format, scan cycle, interactive commands, concurrency (lock), approve/edit/discard, voice, constraints, paths.

- [ ] **Step 3: Commit**

```bash
git add agents/scouter/SOUL.md
git commit -m "feat: add Scouter SOUL.md behavioral spec"
```

---

### Task 5: Create USER.example.md

**Files:**
- Create: `agents/scouter/USER.example.md`

- [ ] **Step 1: Write USER.example.md**

Based on Forge's `USER.md` structure but with voice-specific sections:

```markdown
# USER.md - About Your Human

_Your voice profile. Scouter uses this to draft posts and replies that sound like you._

## Identity

- **Name:**
- **What to call them:**
- **Timezone:**
- **Twitter/X handle:**

## Voice Profile

- **Who you are:** _(e.g., "technical founder, building AI agents")_
- **Tone:** _(e.g., "direct, technical but accessible, opinionated with substance")_
- **Language:** _(e.g., "English for Twitter/X")_

## Guidelines

### Do
_(What characterizes your good posts? e.g., "share real building experience, substantiated opinions, acknowledge others' work, dry humor")_

### Don't
_(What to avoid? e.g., "engagement bait, unfounded hot takes, aggressive promotion, excessive emojis")_

## Topics of Expertise

_(What subjects can you speak on with authority? e.g., "autonomous agents, self-hosted AI, developer tooling")_

## Context

_(What are you working on? What's your angle? Build this over time.)_

---

The more detail you provide, the better the drafts. Review and update periodically based on approve/edit/discard patterns.
```

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/USER.example.md
git commit -m "feat: add Scouter USER.example.md voice profile template"
```

---

### Task 6: Create AGENTS.md

**Files:**
- Create: `agents/scouter/AGENTS.md`

- [ ] **Step 1: Write AGENTS.md**

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/AGENTS.md
git commit -m "feat: add Scouter AGENTS.md workflow reference"
```

---

### Task 7: Create TOOLS.md

**Files:**
- Create: `agents/scouter/TOOLS.md`

- [ ] **Step 1: Write TOOLS.md**

````markdown
# TOOLS.md - Scouter

Environment-specific tool notes for Scouter.

## xurl CLI (Twitter/X API v2)

[xurl](https://github.com/xdevplatform/xurl) is installed in the Docker image at `/usr/local/bin/xurl`.

### Key endpoints

**List tweets:**
```bash
xurl api get /2/lists/:list_id/tweets \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

**Search recent tweets:**
```bash
xurl api get /2/tweets/search/recent \
  --query "query=<keyword>" \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

**User mentions:**
```bash
xurl api get /2/users/:user_id/mentions \
  --query "tweet.fields=created_at,author_id,text" \
  --query "max_results=20"
```

### Rate limits
Rate limits are per-app, not per-endpoint. If xurl returns HTTP 429, skip Twitter for this cycle and note it in the Discord report. Do not retry.

### Auth
xurl manages its own auth via `xurl auth`. Tokens are stored in `~/.xurl/`. Auth must be configured during initial setup (not automated).

## HTTP tools

Use the gateway's HTTP tool to fetch RSS feeds.

### RSS parsing
Fetch the URL, then parse the XML response:
- Atom feeds: look for `<entry>` elements with `<title>`, `<link>`, `<published>`
- RSS 2.0 feeds: look for `<item>` elements with `<title>`, `<link>`, `<pubDate>`

## Browser tool

Use the gateway's browser tool for pages that require JavaScript rendering (e.g., GitHub Trending).

Extract relevant items from the rendered DOM. Each page may need different selectors.

## scouter-db.sh

SQLite helper at `$HOME/.openclaw/workspace/agents/scouter/scouter-db.sh`.
Run with no args to see all available commands.

## Discord

Post reports and read user commands via the gateway's Discord integration.
Scouter's channel: **The Watchtower**.
````

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/TOOLS.md
git commit -m "feat: add Scouter TOOLS.md tool reference"
```

---

### Task 8: Create HEARTBEAT.md

**Files:**
- Create: `agents/scouter/HEARTBEAT.md`

- [ ] **Step 1: Write HEARTBEAT.md**

Unlike Forge's empty HEARTBEAT.md, Scouter's heartbeat is active:

```markdown
# HEARTBEAT.md

Run the scan cycle as defined in SOUL.md.

1. Read `config.json`.
2. Check lock via `scouter-db.sh is-locked`. If locked, skip this cycle.
3. Determine which sources are due (compare schedule vs last scan timestamp).
4. If any sources are due, run the scan cycle (see SOUL.md).
5. If no sources are due, skip silently.
```

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/HEARTBEAT.md
git commit -m "feat: add Scouter HEARTBEAT.md cron registration"
```

---

### Task 9: Create scan-template.md

**Files:**
- Create: `agents/scouter/scan-template.md`

- [ ] **Step 1: Write scan-template.md**

Analogous to Forge's `autopilot-template.md`. This is the step-by-step template the agent follows on each scan cycle:

```markdown
# Scan Cycle

## Due sources this cycle
{{due_sources}}

## Instructions

For each due source:

### 1. Collect
- **Twitter**: use xurl CLI to fetch new posts from lists, keyword searches, and mentions since last scan.
- **RSS**: use HTTP tool to fetch the feed URL, parse XML for new entries since last scan.
- **Web**: use browser tool to scrape the page, extract relevant items.

### 2. Deduplicate
For each collected item, compute SHA-256 hash of the URL.
Run `scouter-db.sh is-scanned <hash>`. Skip if already processed.
For new items: `scouter-db.sh scan <source> <source_name> <hash> <url> <title>`.

### 3. Filter and classify
Read `USER.md` for the user's topics of expertise and interests.
Evaluate each new item:
- **Discard**: off-topic, spam, memes, retweets with no commentary, promotional content.
- **Briefing**: relevant and informative, but not a natural engagement opportunity.
- **Opportunity**: a post where the user could add value by replying or commenting.

### 4. Draft
For each opportunity, generate a response draft:
- Read `USER.md` for voice, tone, and guidelines.
- Match the style and length appropriate for the platform (Twitter/X: concise, under 280 chars for replies).
- Follow the Do/Don't rules from the voice profile strictly.

### 5. Record
Insert each opportunity via `scouter-db.sh opportunity <scanned_item_id> <original_post> <draft>`.

### 6. Report
Post a structured report to Discord (The Watchtower):
- Briefing section: top items by relevance (max 10, "N more" note if truncated).
- Opportunities section: each with its SQLite ID, original post, and draft.
- Only post if there is new content.

### 7. Housekeeping
- `scouter-db.sh set-last-scan <source_name>` for each source processed.
- `scouter-db.sh cleanup` (run once daily, not every cycle).

## Pending opportunities
There are currently {{pending_opportunities}} unresolved opportunities from previous scans.
```

- [ ] **Step 2: Commit**

```bash
git add agents/scouter/scan-template.md
git commit -m "feat: add Scouter scan-template.md cycle template"
```

---

## Chunk 3: Infrastructure Changes

### Task 10: Generalize setup.sh DB initialization

**Files:**
- Modify: `setup.sh:67-73`

- [ ] **Step 1: Replace hard-coded Forge DB init with generic loop**

Current code (lines 67-73):
```bash
# --- Initialize Forge SQLite database ---
FORGE_DB_SH="workspace/agents/forge/forge-db.sh"
if [ -f "$FORGE_DB_SH" ]; then
    chmod +x "$FORGE_DB_SH"
    "$FORGE_DB_SH" init
    echo "[ok] Forge tracking database initialized."
fi
```

Replace with:
```bash
# --- Initialize agent databases ---
for db_script in workspace/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    chmod +x "$db_script"
    "$db_script" init
    echo "[ok] $agent_name tracking database initialized."
done
```

- [ ] **Step 2: Test that setup.sh still works for Forge**

Run:
```bash
# Simulate a clean setup (using temp workspace)
mkdir -p /tmp/test-setup/workspace/agents/forge
cp agents/forge/forge-db.sh /tmp/test-setup/workspace/agents/forge/
mkdir -p /tmp/test-setup/workspace/agents/scouter
cp agents/scouter/scouter-db.sh /tmp/test-setup/workspace/agents/scouter/
# Test the glob pattern
for db_script in /tmp/test-setup/workspace/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    echo "Would init: $agent_name ($db_script)"
done
rm -rf /tmp/test-setup
```

Expected: Both `forge` and `scouter` are found.

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: generalize setup.sh DB init for multiple agents"
```

---

### Task 11: Add xurl CLI to Dockerfile

**Files:**
- Modify: `Dockerfile`

- [ ] **Step 1: Check xurl installation method**

Visit https://github.com/xdevplatform/xurl for installation instructions. xurl is a Go binary. Installation is typically:
```bash
go install github.com/xdevplatform/xurl@latest
```
Or download a prebuilt binary from releases.

- [ ] **Step 2: Add xurl installation to Dockerfile**

Add after the GitHub CLI installation block (after line 29), before `USER node`:

```dockerfile
# xurl CLI (X/Twitter API v2)
RUN XURL_VERSION=$(curl -sf https://api.github.com/repos/xdevplatform/xurl/releases/latest | jq -r '.tag_name') \
    && curl -fsSL "https://github.com/xdevplatform/xurl/releases/download/${XURL_VERSION}/xurl_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin xurl \
    && chmod +x /usr/local/bin/xurl
```

Note: Adjust the binary name/path based on the actual release asset naming. If xurl does not publish prebuilt binaries, install Go and build from source instead.

- [ ] **Step 3: Verify Dockerfile builds**

Run:
```bash
docker build --build-arg OPENCLAW_VERSION=$(cat .openclaw-version) -t openclaw-nas-test -f Dockerfile .
docker run --rm openclaw-nas-test xurl --version
docker rmi openclaw-nas-test
```

Expected: xurl version is printed.

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add xurl CLI to Dockerfile for Twitter/X API access"
```

---

## Chunk 4: Verification

### Task 12: End-to-end verification

- [ ] **Step 1: Verify complete file structure**

Run:
```bash
ls -la agents/scouter/
```

Expected files:
- `IDENTITY.md`
- `SOUL.md`
- `USER.example.md`
- `AGENTS.md`
- `TOOLS.md`
- `HEARTBEAT.md`
- `scan-template.md`
- `config.example.json`
- `scouter-db.sh`

- [ ] **Step 2: Verify setup.sh handles both agents**

Run:
```bash
# Simulate fresh setup
rm -rf /tmp/test-workspace
mkdir -p /tmp/test-workspace/agents
cp -r agents/forge /tmp/test-workspace/agents/
cp -r agents/scouter /tmp/test-workspace/agents/
# Test agent install loop (the same logic setup.sh uses)
for agent_dir in /tmp/test-workspace/agents/*/; do
    agent_name=$(basename "$agent_dir")
    # Rename example files
    for example in "$agent_dir"*.example.*; do
        [ -f "$example" ] || continue
        real="${example/.example/}"
        cp "$example" "$real"
        echo "Renamed: $(basename "$example") -> $(basename "$real")"
    done
done
# Verify USER.example.md -> USER.md rename
ls /tmp/test-workspace/agents/scouter/USER.md && echo "USER.md created" || echo "FAIL: USER.md not created"
ls /tmp/test-workspace/agents/scouter/config.json && echo "config.json created" || echo "FAIL: config.json not created"
rm -rf /tmp/test-workspace
```

Expected: Both `USER.md` and `config.json` are created from their `.example` counterparts.

- [ ] **Step 3: Verify scouter-db.sh full lifecycle**

Run:
```bash
export SCOUTER_DB=/tmp/test-lifecycle.db
agents/scouter/scouter-db.sh init
# Scan
agents/scouter/scouter-db.sh scan twitter ai-leaders $(echo -n "https://x.com/1" | shasum -a 256 | cut -d' ' -f1) "https://x.com/1" "AI post"
# Create opportunity
agents/scouter/scouter-db.sh opportunity 1 "Original tweet" "Draft reply"
# Check pending
agents/scouter/scouter-db.sh pending
# Approve
agents/scouter/scouter-db.sh resolve 1 approved
# Stats
agents/scouter/scouter-db.sh stats
# Lock cycle
agents/scouter/scouter-db.sh lock
agents/scouter/scouter-db.sh is-locked && echo "LOCKED" || echo "UNLOCKED"
agents/scouter/scouter-db.sh unlock
agents/scouter/scouter-db.sh is-locked && echo "LOCKED" || echo "UNLOCKED"
# Last scan
agents/scouter/scouter-db.sh set-last-scan twitter
agents/scouter/scouter-db.sh last-scan twitter
# Cleanup
rm /tmp/test-lifecycle.db
```

Expected: Full lifecycle works without errors.

- [ ] **Step 4: Cross-check spec coverage**

Review the spec (`docs/superpowers/specs/2026-03-13-scouter-agent-design.md`) against the created files. Verify:
- [ ] All file structure items from spec are present
- [ ] All scouter-db.sh commands from spec are implemented
- [ ] Config schema matches spec
- [ ] SOUL.md covers all operational modes from spec
- [ ] USER.example.md covers all voice profile fields from spec
