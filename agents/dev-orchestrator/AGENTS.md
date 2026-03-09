# AGENTS.md - Forge

## Workflow

### Cron cycle (every 15 minutes, 24/7)

1. Read `SOUL.md` for identity and constraints.
2. Read `forge-config.json` for the project list.
3. Check global concurrency via `sessions_list`: count active `autopilot-*` sessions. If already 4, skip.
4. For each enabled project whose schedule matches the current time:
   a. Read `autopilot-template.md`, interpolate placeholders.
   b. Spawn an ACP session via `sessions_spawn` (agentId from project config, `mode: run`, `thread: true`, `label: autopilot-<repo-name>-<issue-number>`).
   c. Stop spawning if the 4-session limit is reached.
5. Exit immediately. The spawned sessions continue autonomously.

### Interactive (messages)

Forge responds to conversational commands from the user:
- `run <repo>` — trigger immediately
- `add/remove <repo>` — manage project list
- `pause/resume <repo>` — toggle enabled state
- `set <repo> schedule <schedule>` — change schedule
- `status` — overview of all repos and active sessions

See SOUL.md for the full command reference.

## Schedule

Single cron job fires every 15 minutes, 24/7. Per-repo schedules in `forge-config.json` control which repos are active at any given time.

Schedule format:
- `on-demand` — manual trigger only
- `always` — every cron cycle
- `HH-HH` — hour range (e.g., `22-07`)
- `HH-HH weekdays` — weekdays only
- `HH-HH weekends` — weekends only

## Process management

- Active sessions checked via `sessions_list`, matched by `autopilot-*` labels
- Results announced via OpenClaw completion events
- Concurrency: max 4 active `autopilot-*` sessions globally. Multiple per repo allowed.
- Labels are unique per issue: `autopilot-<repo-name>-<issue-number>`

## Config

`forge-config.json`:
```json
{
  "timezone": "Europe/Madrid",
  "projects": [
    {
      "repo": "owner/repo",
      "branch": "main",
      "agentId": "claude",
      "schedule": "22-07",
      "enabled": true,
      "excludeLabels": ["wontfix"],
      "testCommand": "npm test",
      "setupInstructions": "npm install"
    }
  ]
}
```

Required fields: `repo`, `branch`
Defaults: `agentId: "claude"`, `schedule: "on-demand"`, `enabled: true`
Optional: `excludeLabels`, `testCommand`, `setupInstructions`

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
For manual queries: message Forge with "status".

## Safety
- Forge modifies `forge-config.json` only when the user explicitly asks.
- If forge-config.json is missing or empty, exit silently on cron.
