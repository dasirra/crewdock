# Boot

Run a status check and report to Discord.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks (all checks run regardless of boot type).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run these in order. Record pass/fail for each.

1. `config.json` present and not empty.
2. `forge-db.sh init` (idempotent, ensures DB and migrations are up to date).
3. `gh auth status` — check GitHub CLI authentication. Credentials stored in `~/.config/gh/hosts.yml`.
4. `command -v claude` — check Claude CLI is installed (installed by `init.d/01-tools.sh`).
5. Heartbeat: run `openclaw config get agents.list`, parse the JSON array to find the entry matching this agent's `id`, then read `.heartbeat.every`. A value of `"0m"` or absent means disabled.
6. Enabled project count: read `config.json`, count projects where `enabled` is `true`.
7. Active sessions: run `sessions_list`, count sessions with names matching `autopilot-*`.

If a health check command itself fails (timeout, crash), report it as failed with the error output. Do not silently skip it.

## First Boot

Use this output when `config.json` is missing or empty.

Post to Discord:

**Forge online.** Autonomous dev orchestrator.

I monitor GitHub repos, pick up open issues, and ship PRs.

**What I do:**
- Scan repos on schedule for open issues
- Spawn coding sessions that implement them
- Open PRs against the configured base branch
- Track issue state in SQLite (no duplicates, no infinite retries)

**Commands:**
- `status` — repos, active sessions, queue
- `run` — trigger a scan cycle now
- `history` — recent issues and their outcomes
- `add <owner/repo>` — add a repo to monitor
- `pause/resume <owner/repo>` — toggle a repo

**Setup needed:**
[List only the items whose health check failed. If all pass, replace this section with: "Ready. Monitoring N repos."]
- GitHub: not authenticated. Set `GH_TOKEN` in `.env` on the host, then `make restart`.
- Claude CLI: not installed. Run `make restart` to re-trigger tool installation.
- Projects: none configured. Send `add owner/repo` to start.

## Returning Boot

Use this output when `config.json` exists and is not empty.

Post to Discord:

Forge online. Repos: N monitored. Sessions: N/M active. Heartbeat: <status>. Queue: N issues pending.

If any health check failed, append warnings below the status line. One line per warning.
