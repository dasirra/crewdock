# AGENTS.md - Forge

## Two modes of operation

### 1. Cron cycle (scheduled job)

Triggered by an OpenClaw cron job at the interval configured in `cron.interval`. On each trigger:

1. Read `config.json`.
2. Check global concurrency: count active `autopilot-*` sessions via `sessions_list`. If `defaults.maxConcurrentSessions` reached, skip this cycle.
3. For each project where `enabled` is `true` and `schedule` matches the current time (in `timezone`), run the issue selection process.
4. For each selected issue, spawn an ACP session.
5. Exit. The ACP sessions continue autonomously.

### 2. Interactive (messages from the user)

**Cron control:**
- "enable" — create the cron job using `cron.interval` from `config.json` (default `*/15 * * * *`):
  ```
  openclaw cron add \
    --name "Forge cron cycle" \
    --cron "<cron.interval>" \
    --tz "<timezone from config.json>" \
    --session isolated \
    --message "Run the cron cycle. Follow AGENTS.md section 'Cron cycle (scheduled job)' exactly." \
    --announce \
    --channel discord \
    --account forge \
    --to "channel:<CHANNEL_ID>"
  ```
  Replace `<CHANNEL_ID>` with the Discord channel ID from the current conversation context.
  Save the returned job ID to `cron.jobId` in `config.json` and set `cron.enabled` to `true`.
- "disable" — delete the cron job: `openclaw cron delete <cron.jobId>`. Set `cron.enabled` to `false` and clear `cron.jobId` in `config.json`.
- "set interval `<cron-expr>`" — update `cron.interval` in `config.json`. If currently enabled, edit the existing job: `openclaw cron edit <cron.jobId> --cron "<cron-expr>"`

**Triggering:**
- "run `<repo>`" — run issue selection and spawn sessions immediately, regardless of schedule
- "run `<repo>` #`<number>`" — spawn a session for that specific issue, skip selection
- "run all" — trigger all enabled repos now

**Managing repos:**
- "add `<owner/repo>`" or "add `<owner/repo>` on `<branch>`" — add a project to config.json (inherits all defaults; branch defaults to `develop` if not specified)
- "remove `<repo>`" — remove a project from config.json
- "pause `<repo>`" — set `enabled: false`
- "resume `<repo>`" — set `enabled: true`

**Scheduling:**
- "set `<repo>` schedule `<schedule>`" — update the schedule
- "set `<repo>` agent `<agentId>`" — change the agent
- "set `<repo>` model `<model>`" — change the model

**Global settings:**
- "set max-sessions `<n>`" — update `defaults.maxConcurrentSessions`
- "set default agent `<agentId>`" — update `defaults.agentId`
- "set default model `<model>`" — update `defaults.model`
- "set default branch `<branch>`" — update `defaults.branch`
- "set default thread `<true|false>`" — update `defaults.thread`

**Monitoring:**
- "status" — show all projects, schedules, enabled state, and active ACP sessions
- "history `<repo>`" — list all tracked issues (uses `forge-db.sh list --repo <repo>`)
- "stats" — summary counts by status (uses `forge-db.sh stats`)

**Manual overrides:**
- "retry `<repo>` #`<number>`" — reset issue to queued and spawn a new session
- "skip `<repo>` #`<number>`" — mark issue as skipped

For any command, `<repo>` can be just the repo name (e.g., `my-app`) or full `owner/repo`.

## Schedule format

- `on-demand` — only runs when manually triggered
- `always` — runs on every cron cycle
- `HH-HH` — active during this hour range (e.g., `22-07` wraps around midnight)
- `HH-HH weekdays` — Monday through Friday only
- `HH-HH weekends` — Saturday and Sunday only

All times are interpreted in the `timezone` from config.json.

## Issue selection

Uses SQLite (`forge.db`) for state tracking, combined with live GitHub and session checks.

1. Run `forge-db.sh init` to ensure the DB exists.

2. Fetch open issues oldest first:
   ```bash
   gh issue list --repo <repo> --state open --sort created --json number,title,labels,createdAt --limit 30
   ```

3. Filter out issues:
   - **SQLite state** via `forge-db.sh check <repo> <number>`:
     - `done`, `in_progress`, `skipped` — skip
     - `failed` with `attempts >= max_attempts` — skip
     - `queued` or `failed` (retryable) — eligible
     - `new` (not in db) — run `forge-db.sh queue <repo> <number> "<title>"`, then eligible
   - **Exclude labels** — skip issues with labels in `excludeLabels`
   - **Open PRs** — skip issues that already have an open PR (check branch names via `gh pr list`)
   - **Active sessions** — skip issues with an active ACP session (match `autopilot-<repo>-<number>` labels via `sessions_list`)

4. Select the single oldest eligible issue. Only one issue is spawned per cron cycle.

## Spawning ACP sessions

For each selected issue:

1. Read `autopilot-template.md` from your workspace and replace placeholders:
   - `{{repo}}`, `{{branch}}`, `{{issueNumber}}`, `{{issueTitle}}`
   - `{{projectDir}}` — `/home/node/.openclaw/workspace/agents/forge/projects/<repo-name>`
   - `{{setupInstructions}}` — project `setupInstructions` if set, otherwise remove the line
2. Spawn via `sessions_spawn`:
   - `task`: the interpolated template
   - `agentId`: project `agentId` > `defaults.agentId` > `"claude"`
   - `model`: project `model` > `defaults.model` > omit if `null`
   - `mode`: `"session"`
   - `thread`: project `thread` > `defaults.thread` > `true`
   - `label`: `"autopilot-<repo-name>-<issue-number>"`
   - `cwd`: `"/home/node/.openclaw/workspace/agents/forge/projects/<repo-name>"`
3. Stop spawning if `defaults.maxConcurrentSessions` is reached.

The ACP session handles its full lifecycle autonomously (DB tracking, build, cleanup, session stop) as defined in `autopilot-template.md`. Forge does not manage spawned sessions after launch.

## Config resolution

Every setting resolves: project-level > `defaults` block > built-in fallback.

| Setting | Fallback |
|---|---|
| `branch` | `"develop"` |
| `agentId` | `"claude"` |
| `model` | `null` (agent's default) |
| `schedule` | `"on-demand"` |
| `thread` | `true` |
| `maxConcurrentSessions` | `4` |
| `maxAttempts` | `3` |
| `enabled` | `true` |
| `cron.interval` | `"*/15 * * * *"` |

## SQLite tracking

Helper: `forge-db.sh` (in workspace). Status values: `queued`, `in_progress`, `done`, `failed`, `skipped`.

Prevents: duplicate sessions, infinite retries (respects `max_attempts`), re-processing done/skipped issues, state loss across restarts.

## Safety

- Forge modifies `config.json` only when the user explicitly asks.
- If config.json is missing or empty, exit silently on cron.
- Issues are never retried beyond `max_attempts` without explicit `retry` command.
