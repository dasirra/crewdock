# OpenClaw NAS

A self-hosted AI agent system running 24/7 on a NAS. It chats via Telegram, syncs notes with Obsidian, integrates with Google Workspace, and autonomously resolves GitHub issues while you sleep.

## Why

Cloud-hosted AI assistants are stateless, sandboxed, and forget everything between sessions. This project puts an AI agent on hardware you own, with persistent memory, access to your tools, and the ability to act autonomously on a schedule. It runs on a consumer NAS using Docker, costs nothing beyond the API calls, and stays under your control.

## What It Does

- **Personal assistant** via Telegram: manages calendar, email, tasks, notes, and answers questions
- **Autonomous developer** ("Forge"): picks up GitHub issues, writes code, runs tests, and opens PRs without human intervention
- **Content pipeline**: generates daily tech briefings, drafts posts, archives to Obsidian
- **Proactive monitoring**: heartbeat-driven checks for unread emails, upcoming calendar events, pending tasks
- **Note sync**: bidirectional sync between the agent's workspace and Obsidian (mobile + desktop) via Syncthing

## Architecture

```
                        ┌─────────────────────────────────────────────────┐
  Telegram              │  NAS (Docker)                                   │
  ────────────────────► │                                                 │
                        │  ┌─────────────────────────────────────────┐    │
  Google Workspace      │  │  openclaw-gateway                       │    │
  (Gmail, Calendar,     │  │                                         │    │
   Drive, Tasks)        │  │  Agents:                                │    │
  ◄───────────────────► │  │   ├── Echo (main) ── Telegram bot      │    │
                        │  │   ├── Forge ──────── Dev orchestrator   │    │
  GitHub                │  │   └── Content ────── Briefings/posts    │    │
  (Issues, PRs,         │  │                                         │    │
   Repos)               │  │  Tools: gog, obsidian-cli, gh, claude   │    │
  ◄───────────────────► │  │                                         │    │
                        │  │  Cron: heartbeats, briefings, Forge     │    │
                        │  └─────────────────────────────────────────┘    │
  Obsidian              │                                                 │
  (Mobile + Desktop)    │  ┌──────────────┐    ┌──────────────────────┐   │
  ◄───────────────────► │  │  Syncthing   │    │  Tailscale (host)    │   │
                        │  │  :8385       │    │  Encrypted VPN       │   │
                        │  └──────────────┘    └──────────────────────┘   │
                        └─────────────────────────────────────────────────┘
```

## The Agent System

[OpenClaw](https://github.com/nichochar/openclaw) provides the runtime: an LLM gateway with built-in Telegram integration, multi-agent support, cron scheduling, and a persistent workspace. This repo is the configuration and customization layer on top of it.

### Agents

Each agent has its own workspace directory with identity, personality, memory, and behavior files:

| Agent | Role | Runs via |
|-------|------|----------|
| **Echo** | Personal assistant. Telegram conversations, email, calendar, tasks, notes. | Telegram messages + heartbeat cron |
| **Forge** | Autonomous developer. Picks GitHub issues, writes code, opens PRs. | 15-minute cron + Telegram commands |
| **Content Creator** | Generates tech briefings and content drafts. | Daily cron |

### Agent Workspace Structure

Each agent's workspace follows the same convention:

```
workspace/agents/<agent-name>/
├── IDENTITY.md          # Name, role, emoji
├── SOUL.md              # Personality, constraints, behavior rules
├── AGENTS.md            # Workflow definitions, session protocol
├── HEARTBEAT.md         # Periodic tasks to check
├── MEMORY.md            # Curated long-term memory
├── TOOLS.md             # Environment-specific tool notes
├── USER.md              # Context about the user
└── memory/              # Daily logs (YYYY-MM-DD.md)
```

The main agent (Echo) uses the root `workspace/` directory. Sub-agents use `workspace/agents/<name>/`.

### Memory System

Agents wake up stateless each session. Continuity comes from the filesystem:

- **Daily logs** (`memory/YYYY-MM-DD.md`): raw session notes, decisions, events
- **Long-term memory** (`MEMORY.md`): curated insights distilled from daily logs
- **Heartbeat maintenance**: agents periodically review daily logs and update long-term memory, like journaling

This is intentionally file-based. No vector database, no embeddings. Plain markdown that's easy to read, edit, and sync.

## Forge: Autonomous Development

Forge is the most interesting part. It's a dev orchestrator that turns GitHub issues into pull requests without human involvement.

### How It Works

1. **Cron fires every 15 minutes**. Forge reads its config, checks which repos are scheduled to run.
2. **Issue selection**: fetches open issues from GitHub, filters out issues that already have PRs or active sessions, picks the oldest eligible ones.
3. **Spawns autonomous coding sessions**: each session gets a single issue and runs in isolation using Claude Code CLI (`claude --dangerously-skip-permissions`).
4. **The coding session**:
   - Clones/updates the repo
   - Reads the GitHub issue
   - Creates a git worktree for isolation
   - Scans the repo for custom agent definitions (`.claude/agents/`, `.agents/commands/`)
   - Implements the fix using a team of sub-agents (implementation, testing, review)
   - Runs tests
   - Commits, pushes, and creates a PR
   - Cleans up the worktree
5. **Reports results** via Telegram.

### Forge Config

```json
{
  "timezone": "Europe/Madrid",
  "projects": [
    {
      "repo": "owner/repo-name",
      "branch": "develop",
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

### Schedule Formats

| Format | Meaning |
|--------|---------|
| `on-demand` | Only runs when manually triggered via Telegram |
| `always` | Runs on every cron cycle (every 15 min) |
| `HH-HH` | Active during hour range (e.g., `22-07` wraps midnight) |
| `HH-HH weekdays` | Hour range, Monday-Friday only |
| `HH-HH weekends` | Hour range, Saturday-Sunday only |

### Telegram Commands

Forge responds to natural language commands:

- `run <repo>` -- trigger issue selection and coding sessions immediately
- `run <repo> #123` -- work on a specific issue
- `status` -- show all projects, schedules, and active sessions
- `add owner/repo on main` -- register a new project
- `pause/resume <repo>` -- toggle a project
- `set <repo> schedule 22-07 weekdays` -- update schedule

### Constraints

- Max 4 concurrent coding sessions globally
- Never pushes to main/master directly (always feature branches + PRs)
- One issue per session
- Uses git worktrees for isolation (parallel work on multiple issues is safe)
- Config changes only happen when explicitly requested by the user

## Cron Jobs

The system runs several scheduled jobs:

| Job | Schedule | What it does |
|-----|----------|--------------|
| Daily summary | 05:00 | Sends pending tasks, today's calendar, important emails via Telegram |
| Tech briefing | 09:00 | Generates a curated tech news briefing, archives to Obsidian |
| Forge heartbeat | Every 15 min | Checks for eligible repos/issues, spawns coding sessions |
| Log archiver | Every 5 min | Archives completed coding session logs |

All times are in the configured timezone.

## Services

| Service | Image | Description |
|---------|-------|-------------|
| `openclaw-gateway` | Custom (see Dockerfile) | Main runtime: agents, Telegram bot, cron, API gateway |
| `syncthing` | `linuxserver/syncthing` | Bidirectional file sync with Obsidian |
| `openclaw-cli` | Same as gateway | Interactive CLI for admin (runs on demand) |

## Dockerfile

The custom image extends `alpine/openclaw` with:

- **[gog](https://github.com/steipete/gogcli)**: Google Workspace CLI (Gmail, Calendar, Drive, Tasks, Contacts, Sheets, Docs)
- **[obsidian-cli](https://github.com/Yakitrak/obsidian-cli)**: Read/write Obsidian vaults from the command line
- **[gh](https://cli.github.com/)**: GitHub CLI for issue/PR management
- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)**: Anthropic's CLI agent, used by Forge to spawn autonomous coding sessions
- **[Flutter SDK](https://flutter.dev/)**: For mobile app development projects
- **[Tailscale](https://tailscale.com/)**: VPN client for secure remote access

## Directory Structure

```
openclaw/
├── Dockerfile                  # Custom image build
├── docker-compose.yaml         # Service definitions
├── Makefile                    # Operational shortcuts
├── .env                        # Secrets (not committed)
├── .gitignore
├── tailscale-serve.json        # Tailscale HTTPS proxy config
│
├── config/                     # OpenClaw runtime config (persisted)
│   ├── openclaw.json           # Main configuration
│   ├── cron/jobs.json          # Scheduled jobs
│   ├── agents/                 # Agent sessions and auth state
│   ├── credentials/            # OAuth tokens
│   └── telegram/               # Telegram bot state
│
├── workspace/                  # Agent workspace (synced via Syncthing)
│   ├── SOUL.md                 # Main agent personality
│   ├── IDENTITY.md             # Main agent identity
│   ├── AGENTS.md               # Session protocol and behavior rules
│   ├── HEARTBEAT.md            # Periodic check tasks
│   ├── MEMORY.md               # Long-term curated memory
│   ├── USER.md                 # User context
│   ├── TOOLS.md                # Environment-specific tool notes
│   ├── vault/                  # Obsidian vault (synced)
│   ├── memory/                 # Daily logs
│   └── agents/                 # Sub-agent workspaces
│       ├── dev-orchestator/    # Forge
│       │   ├── forge-config.json
│       │   ├── autopilot-template.md
│       │   ├── logs/autopilot/
│       │   └── ...
│       └── content-creator/
│
├── projects/                   # Git repos for Forge to work on
├── gog-config/                 # Google Workspace CLI tokens
├── syncthing-config/           # Syncthing state
├── claude-config/              # Claude Code CLI config
└── tailscale-state/            # Tailscale VPN state
```

## Setup

### Prerequisites

- Docker and Docker Compose
- A NAS or any always-on Linux machine
- A Telegram bot token ([BotFather](https://t.me/BotFather))
- API keys for your LLM provider(s) (Anthropic, OpenAI, Google, etc.)
- A Google Cloud project with OAuth credentials (optional, for Google Workspace)
- Tailscale account (optional, for remote access)

### 1. Clone and configure

```bash
git clone https://github.com/dasirra/openclaw-nas.git /volume1/docker/openclaw
cd /volume1/docker/openclaw
```

Create `.env`:

```bash
cat > .env << 'EOF'
OPENCLAW_GATEWAY_TOKEN=<generate-with-openssl-rand-hex-24>

# Google Workspace (gog CLI)
GOG_ACCOUNT=you@gmail.com
GOG_KEYRING_PASSWORD=<password-for-local-keyring>

# Forge (autonomous dev)
GITHUB_TOKEN=<github-personal-access-token>
GIT_AUTHOR_NAME=Your Name
GIT_AUTHOR_EMAIL=you@example.com
EOF
```

### 2. Build and start

```bash
make update
```

This pulls the base image, builds the custom layer, and starts all services.

### 3. Onboard

```bash
make onboard
```

Runs the setup wizard to authenticate with your LLM provider(s) and configure Telegram.

### 4. Set up Google Workspace (optional)

1. Create a Google Cloud project and enable the APIs you need (Gmail, Calendar, Drive, etc.)
2. Create OAuth credentials (Desktop app type)
3. Copy the credentials JSON to `gog-config/client_secret.json`
4. Authenticate:

```bash
make cli
# Inside the container:
gog auth keyring file
gog auth credentials /home/node/.config/gogcli/client_secret.json
gog auth add you@gmail.com --services gmail,calendar,drive,contacts --manual
```

### 5. Configure Forge (optional)

Edit `workspace/agents/dev-orchestator/forge-config.json` to add your repos. Then enable the Forge cron job through the CLI or Telegram.

## Operations

```bash
make help              # Show all commands

make up                # Start services
make down              # Stop services
make restart           # Restart all
make restart-gateway   # Restart gateway only

make logs              # Tail gateway logs
make logs-all          # Tail all logs
make status            # Show running containers

make update            # Pull + rebuild + restart
make cli               # Interactive CLI shell
make clean             # Remove dangling images
```

## Security

- **Gateway** binds to localhost only, not exposed to the network
- **Tailscale** provides encrypted, zero-config VPN access from anywhere
- **Telegram** uses an allowlist (only authorized user IDs can interact)
- **Secrets** (`.env`, OAuth tokens, identity keys) are gitignored
- **Agent boundaries**: agents ask before any external action (sending emails, creating public posts)
- **Forge safety**: never pushes to protected branches, always uses feature branches and PRs

## How It All Connects

```
You (phone/laptop)
  │
  ├── Telegram ──────────► Echo (main agent) ──► Google Workspace (gog)
  │                              │               ► Obsidian (obsidian-cli)
  │                              │               ► GitHub (gh)
  │                              │
  │                              ├── Forge (dev agent)
  │                              │     └── Claude Code sessions
  │                              │           └── git worktrees
  │                              │                 └── PRs on GitHub
  │                              │
  │                              └── Content Creator
  │                                    └── Briefings ──► Obsidian vault
  │
  ├── Obsidian app ◄────► Syncthing ◄────► workspace/vault/
  │
  └── Tailscale VPN ────► NAS (direct access when needed)
```

## Limitations and Trade-offs

- **Cost**: autonomous coding sessions burn tokens. Forge's 15-minute cron with 4 concurrent sessions can add up. Use schedules (`22-07 weekdays`) to control when it runs.
- **Quality**: Forge produces working PRs for well-scoped issues with good test coverage. Vague issues or repos without tests yield worse results. Writing clear issues is the best way to improve output.
- **Memory**: the file-based memory system is simple but doesn't scale to thousands of entries. It works well for personal use.
- **Single user**: this is designed for one person. Multi-user support would need auth, workspace isolation, and separate Telegram bots.

## Built With

- [OpenClaw](https://github.com/nichochar/openclaw) -- AI agent runtime
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) -- Autonomous coding CLI
- [gog](https://github.com/steipete/gogcli) -- Google Workspace CLI
- [obsidian-cli](https://github.com/Yakitrak/obsidian-cli) -- Obsidian vault CLI
- [Syncthing](https://syncthing.net/) -- Decentralized file sync
- [Tailscale](https://tailscale.com/) -- Zero-config VPN

## License

MIT
