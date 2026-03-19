# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

OpenClaw NAS — a self-hosted AI assistant running 24/7 on a NAS via Docker, built on [OpenClaw](https://github.com/openclaw/openclaw). For upstream docs, APIs, and troubleshooting, check the [documentation](https://docs.openclaw.ai/start/getting-started). When debugging issues, consult these resources for possible solutions before assuming the problem is local.

Two main components:

- **OpenClaw Gateway** — always-on LLM agent with Telegram, Google Workspace integrations
- **Forge** — autonomous dev agent that picks up GitHub issues, writes code, and opens PRs using Claude CLI

## Commands

```bash
make init               # First-time: creates runtime directories (run before first 'make up')
make up                 # Build and start services
make down               # Stop services
make restart            # Restart all; make restart-gateway for just gateway
make logs               # Tail gateway logs; make logs-all for all services
make shell              # Bash into the gateway container
make update             # Pull latest image, rebuild, restart
make config-preview     # Preview generated openclaw.json (no Docker needed)
```

## Project Structure

```
agents/forge/           # Forge agent definition (tracked in git, copied to workspace on setup)
home/                   # Persistent /home/node volume — all runtime config and data (gitignored)
```

Only `agents/`, `docker-compose.yaml`, `Dockerfile`, `docker-entrypoint.sh`, `init.d/`, `Makefile`, and `docs/` are tracked in git. Everything under `home/` is gitignored runtime data.

## Forge Architecture

Forge is the autonomous development orchestrator. Understanding its flow is key to working in this repo.

**Two modes:** cron heartbeat (every 15 min, 24/7) and interactive Telegram commands.

**Cron cycle flow:**
1. Reads `workspace/agents/forge/config.json` for project list and defaults
2. Checks concurrency via `sessions_list` (max 4 active `autopilot-*` sessions)
3. For each enabled project whose schedule matches: fetches open GitHub issues, filters through SQLite DB + active sessions + open PRs + exclude labels
4. Spawns native sessions (with thread binding) that invoke `acpx` CLI with interpolated `autopilot-template.md`
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

The OpenClaw base image version is pinned in `.openclaw-version` (CalVer `YYYY.M.D-patch`). The Dockerfile receives it as a build arg `OPENCLAW_VERSION`. Base image is `ghcr.io/openclaw/openclaw`. `make up` pulls the base image if the pinned version isn't cached locally. `make update` checks GHCR for newer versions and only rebuilds if one exists. `make version` shows pinned, running, and latest versions.

## Docker Setup

- Base image: `ghcr.io/openclaw/openclaw:<version>` (Debian-based, version from `.openclaw-version`)
- `Dockerfile` adds: git, gh CLI, jq, sqlite3, python3, build-essential
- `Dockerfile.local` — personal tool additions (gitignored, built from `.example`)
- `docker-compose.override.yaml` — personal service additions (gitignored, merges automatically)
- Network mode: host. Container user: `node`. Home: `/home/node`

Volume mount: `./home` -> `/home/node` (single persistent volume for all runtime data)

Claude CLI and GWS skills are installed at first boot by `init.d/00-tools.sh` and persist in the home volume.

## Git Conventions

- Branch naming: `feat/`, `fix/`, `chore/` prefixes, or issue-number based (`1-sqlite-tracking`)
- Commit messages: `feat:`, `fix:`, `chore:`, `merge:` prefixes
- Never push to main directly — always feature branches + PRs
- Forge creates worktree-based feature branches per issue

## Config Hot-Reload

OpenClaw watches `openclaw.json` and hot-applies most changes without restart (default mode: `hybrid`). Agents can use `config set` or `config.patch` to modify settings at runtime.

**Hot-applies instantly (no restart):** channels, agent routing, models, heartbeat, cron, automation, sessions, tools, logging.

**Requires gateway restart:** gateway server settings (port, auth, TLS), plugins, discovery, canvasHost.

For partial config updates from agent code, use `config.patch` RPC (requires `baseHash` from `config.get`). For single keys, use `openclaw config set`. Both trigger hot-reload automatically.

## Key Patterns

- **Agent installation:** Agent templates are baked into the Docker image at `/opt/openclaw-agents/` and copied to the workspace volume on first boot by `init.d/03-agents.sh`. Edit templates in `agents/forge/`, rebuild the image with `make up` to pick up changes. The init script skips agents whose workspace directory already exists.
- **Forge config changes:** Forge can modify `config.json` only when the user explicitly asks. Never autonomously.
- **Autopilot sessions:** hybrid spawn — `sessions_spawn` (native runtime, no `agentId`) with `thread: true` creates a Discord thread; the native session invokes `acpx` CLI directly for the coding work. This works around the ACP runtime flag-ordering bug.
- **Concurrency:** checked via `sessions_list` counting `autopilot-*` sessions, capped at `defaults.maxConcurrentSessions`.
