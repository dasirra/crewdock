# AGENTS.md - Forge

## Workflow

### Cron cycle (every 15 minutes, 24/7)

1. Read `SOUL.md` for identity and constraints.
2. Read `config.json` for the project list and defaults.
3. Check global concurrency via `sessions_list`: count active `autopilot-*` sessions. If `defaults.maxConcurrentSessions` reached, skip.
4. Run `forge-db.sh init` to ensure the tracking database exists.
5. For each enabled project whose schedule matches the current time:
   a. Run `forge-db.sh check` for each open issue to determine eligibility (see SOUL.md).
   b. Read `autopilot-template.md`, interpolate placeholders.
   c. Spawn an ACP session via `sessions_spawn`. Resolve `agentId`, `model`, `thread` from project config → defaults → built-in fallbacks.
   d. Run `forge-db.sh start` to mark the issue in_progress.
   e. Stop spawning if the session limit is reached.
6. On session completion, run `forge-db.sh done` or `forge-db.sh fail`.
7. Exit immediately. The spawned sessions continue autonomously.

### Interactive (messages)

Forge responds to conversational commands from the user:
- `run <repo>` — trigger immediately
- `run <repo> #<number>` — trigger specific issue
- `add/remove <repo>` — manage project list
- `pause/resume <repo>` — toggle enabled state
- `set <repo> schedule/agent/model <value>` — change project settings
- `set max-sessions/default <key> <value>` — change global settings
- `status` — overview of all repos and active sessions
- `history <repo>` — list all tracked issues (from forge.db)
- `stats` — summary counts by status (from forge.db)
- `retry <repo> #<number>` — reset issue to queued and spawn
- `skip <repo> #<number>` — mark issue as skipped

See SOUL.md for the full command reference.

## Schedule

Single cron job fires every 15 minutes, 24/7. Per-repo schedules in `config.json` control which repos are active at any given time. Unset schedules fall back to `defaults.schedule`.

Schedule format:
- `on-demand` — manual trigger only
- `always` — every cron cycle
- `HH-HH` — hour range (e.g., `22-07`)
- `HH-HH weekdays` — weekdays only
- `HH-HH weekends` — weekends only

## Process management

- Active sessions checked via `sessions_list`, matched by `autopilot-*` labels
- Issue state tracked in SQLite (`forge.db`) — replaces fragile branch-name parsing
- Results announced via OpenClaw completion events
- Concurrency: respect `defaults.maxConcurrentSessions`. Multiple per repo allowed.
- Labels are unique per issue: `autopilot-<repo-name>-<issue-number>`

## SQLite tracking database

Location: `$HOME/.openclaw/workspace/agents/forge/forge.db`
Helper: `$HOME/.openclaw/workspace/agents/forge/forge-db.sh`

Status values: `queued`, `in_progress`, `done`, `failed`, `skipped`

The database prevents:
- Duplicate sessions for the same issue
- Infinite retry loops on failed issues (respects `max_attempts`)
- Re-processing issues that are already done or skipped
- Loss of state across restarts

## Config

`config.json`:
```json
{
  "timezone": "Europe/Madrid",
  "defaults": {
    "agentId": "claude",
    "model": null,
    "schedule": "on-demand",
    "thread": true,
    "maxConcurrentSessions": 4,
    "maxAttempts": 3
  },
  "projects": [
    {
      "repo": "owner/repo",
      "branch": "main",
      "agentId": "claude",
      "model": "claude-sonnet-4-5-20250514",
      "schedule": "22-07",
      "thread": false,
      "enabled": true,
      "excludeLabels": ["wontfix"],
      "testCommand": "npm test",
      "setupInstructions": "npm install"
    }
  ]
}
```

**Global settings** (`defaults`):
| Field | Default | Description |
|---|---|---|
| `agentId` | `"claude"` | ACP agent for sessions |
| `model` | `null` | Model override (`null` = agent's default) |
| `schedule` | `"on-demand"` | Default schedule for new projects |
| `thread` | `true` | Create a thread per session |
| `maxConcurrentSessions` | `4` | Max active autopilot sessions |
| `maxAttempts` | `3` | Max retry attempts per issue |

**Per-project fields:**
| Field | Required | Description |
|---|---|---|
| `repo` | Yes | GitHub repo (`owner/name`) |
| `branch` | Yes | Base branch to work from |
| `agentId` | No | Override default agent |
| `model` | No | Override default model |
| `schedule` | No | Override default schedule |
| `thread` | No | Override default thread setting |
| `enabled` | No | Toggle on/off (default: `true`) |
| `excludeLabels` | No | Issue labels to skip |
| `testCommand` | No | Custom test command (default: auto-detect) |
| `setupInstructions` | No | Run before each session |

## Autopilot template

`autopilot-template.md` defines the task sent to each ACP session:
- Scans repo for custom commands, agents, and skills
- Discovers and filters GitHub issues (oldest first)
- Creates a worktree per issue
- Implements using a team of agents (repo-defined or ad-hoc)
- Tests, commits, pushes, creates PR
- Cleans up the worktree

## Reporting

Forge checks for completed sessions on each cron cycle and announces results.
For manual queries: message Forge with "status", "history <repo>", or "stats".

## Safety
- Forge modifies `config.json` only when the user explicitly asks.
- If config.json is missing or empty, exit silently on cron.
- Issues are never retried beyond `max_attempts` without explicit `retry` command.
