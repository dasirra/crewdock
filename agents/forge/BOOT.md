# Boot

Run a status check and report to Discord. Keep the output short. The user wants a quick glance, not a diagnostic dump.

1. Read `config.json`. If missing or empty, this is a **first boot**.
2. Run health checks with dependency chain (see below).
3. If first boot, use "First Boot" output.
4. If returning boot, use "Returning Boot" output.

## Health Checks

Run in order. If a check fails, **skip all checks that depend on it**.

1. `config.json` present and not empty.
2. `forge-db.sh init` (idempotent).
3. `gh auth status` — GitHub CLI authentication. Credentials in `~/.config/gh/hosts.yml`.
   - If this fails, skip check 6 (repo scanning requires GitHub auth).
4. `command -v claude` — Claude CLI installed (by `init.d/01-tools.sh`).
5. Heartbeat: run `openclaw config get agents.list`, find this agent by `id`, read `.heartbeat.every`. Value `"0m"` or absent = disabled.
6. Enabled project count: from `config.json`, count projects where `enabled` is `true`.
7. Active sessions: run `sessions_list`, count names matching `autopilot-*`.

**Output rules:**
- Never include raw command output, error messages, or stack traces in the Discord message.
- If a check fails, report it in one short phrase (e.g. "GitHub: not authenticated").
- If a check was skipped because its parent failed, do not mention it at all.

## First Boot

Use when `config.json` is missing or empty. Post to Discord:

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
[Only list items whose check failed. Omit this section entirely if all pass — end with "Ready. Monitoring N repos." instead.]
- GitHub: not authenticated. Set `GH_TOKEN` in `.env` on the host, then `make restart`.
- Claude CLI: not installed. Run `make restart` to re-trigger tool installation.
- Projects: none configured. Send `add owner/repo` to start.

## Returning Boot

Use when `config.json` exists and is not empty. Post to Discord:

**One line only.** Include only the fields you could actually check. Omit fields whose checks were skipped.

Examples:
- All OK: `Forge online. Repos: 3 monitored. Sessions: 1/4 active. Heartbeat: 15m. Queue: 2 pending.`
- GitHub missing: `Forge online. GitHub: not authenticated. Set `GH_TOKEN` in `.env`, then `make restart`.`
- Claude missing: `Forge online. Repos: 3. Claude CLI: not installed. Run `make restart`.`

Do not add extra warning lines. Everything fits in the status line.
