# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OpenClaw NAS — a self-hosted AI assistant running 24/7 on a NAS via Docker. Two main components:

- **OpenClaw Gateway** — always-on LLM agent with Telegram, Google Workspace integrations
- **Forge** — autonomous dev agent that picks up GitHub issues, writes code, and opens PRs using Claude CLI

## Commands

```bash
make setup              # First-time: creates .env, directories, installs agents, inits forge.db
make up                 # Build and start services
make down               # Stop services
make restart            # Restart all; make restart-gateway for just gateway
make logs               # Tail gateway logs; make logs-all for all services
make shell              # Bash into the gateway container
make update             # Pull latest image, rebuild, restart
```

## Project Structure

```
agents/forge/           # Forge agent definition (tracked in git, copied to workspace on setup)
config/                 # Runtime config — openclaw, claude, gws, syncthing (gitignored)
workspace/              # Runtime agent data — installed agents, vault, memory (gitignored)
projects/               # Cloned repos Forge works on (gitignored)
```

Only `agents/`, `docker-compose.yaml`, `Dockerfile`, `Makefile`, `setup.sh`, and `docs/` are tracked in git. Everything under `config/`, `workspace/`, and `projects/` is gitignored runtime data.

## Forge Architecture

Forge is the autonomous development orchestrator. Understanding its flow is key to working in this repo.

**Two modes:** cron heartbeat (every 15 min, 24/7) and interactive Telegram commands.

**Cron cycle flow:**
1. Reads `workspace/agents/forge/config.json` for project list and defaults
2. Checks concurrency via `sessions_list` (max 4 active `autopilot-*` sessions)
3. For each enabled project whose schedule matches: fetches open GitHub issues, filters through SQLite DB + active sessions + open PRs + exclude labels
4. Spawns ACP sessions using interpolated `autopilot-template.md`
5. Exits — sessions continue autonomously

**Key Forge files (in `agents/forge/`):**
- `SOUL.md` — identity, constraints, full command reference, issue selection algorithm
- `AGENTS.md` — workflow summary and config reference
- `autopilot-template.md` — task template with `{{placeholders}}` sent to each coding session
- `forge-db.sh` — SQLite helper for issue tracking (statuses: queued, in_progress, done, failed, skipped)
- `config.example.json` — config template (real config lives in `workspace/agents/forge/config.json`)

**Config resolution:** project-level -> `defaults` block -> built-in fallback.

**SQLite DB** (`forge.db`): tracks issue state to prevent duplicate sessions, infinite retries, and re-processing. Uses `esc()` for SQL injection protection. `assert_int()` validates numeric inputs.

## Version Pinning

The OpenClaw base image version is pinned in `.openclaw-version` (CalVer `YYYY.M.D`). The Dockerfile receives it as a build arg `OPENCLAW_VERSION`. `make update` checks Docker Hub for newer versions and only rebuilds if one exists. `make version` shows pinned, running, and latest versions.

## Docker Setup

- Base image: `alpine/openclaw:<version>` (Debian-based despite the name, version from `.openclaw-version`)
- `Dockerfile` adds: git, gh CLI, jq, sqlite3, tailscale, python3, build-essential, Claude CLI
- `Dockerfile.local` — personal tool additions (gitignored, built from `.example`)
- `docker-compose.override.yaml` — personal service additions (gitignored, merges automatically)
- Network mode: host. Container user: `node`. Home: `/home/node`

Volume mounts map local dirs into the container:
- `./config/openclaw` -> `/home/node/.openclaw`
- `./workspace` -> `/home/node/.openclaw/workspace`
- `./projects` -> `/home/node/projects`
- `./config/claude` -> `/home/node/.claude`

## Git Conventions

- Branch naming: `feat/`, `fix/`, `chore/` prefixes, or issue-number based (`1-sqlite-tracking`)
- Commit messages: `feat:`, `fix:`, `chore:`, `merge:` prefixes
- Never push to main directly — always feature branches + PRs
- Forge creates worktree-based feature branches per issue

## Key Patterns

- **Agent installation:** `setup.sh` copies `agents/` to `workspace/agents/`, renames `.example.*` files. Edit templates in `agents/forge/`, run `make setup` to reinstall (skips existing).
- **Forge config changes:** Forge can modify `config.json` only when the user explicitly asks. Never autonomously.
- **Autopilot sessions:** spawned via `sessions_spawn` with label `autopilot-<repo-name>-<issue-number>`, run in `session` mode with thread support.
- **Concurrency:** checked via `sessions_list` counting `autopilot-*` sessions, capped at `defaults.maxConcurrentSessions`.
