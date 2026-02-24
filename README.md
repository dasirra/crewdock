# OpenClaw NAS

Self-hosted AI agent running on a NAS. Chat via Telegram, sync notes with Obsidian, access Google Workspace, and run autonomous scheduled tasks.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  NAS (Docker)                                       │
│                                                     │
│  ┌──────────────────┐  ┌────────────────────────┐   │
│  │ openclaw-gateway  │  │ syncthing              │   │
│  │ :18789            │  │ :8385 (web UI)         │   │
│  │                   │  │                        │   │
│  │ LLM Providers:    │  │ Syncs workspace/vault  │   │
│  │  - OpenAI Codex   │  │ with Obsidian (mobile  │   │
│  │  - Anthropic      │  │ and desktop)           │   │
│  │  - Google Gemini  │  └────────────────────────┘   │
│  │                   │                               │
│  │ Channels:         │  ┌────────────────────────┐   │
│  │  - Telegram Bot   │  │ openclaw-cli           │   │
│  │                   │  │ (on-demand tools)      │   │
│  │ Skills:           │  └────────────────────────┘   │
│  │  - gog (Google)   │                               │
│  │  - obsidian-cli   │  ┌────────────────────────┐   │
│  │                   │  │ Tailscale (host)       │   │
│  │ Cron:             │  │ Secure remote access   │   │
│  │  - Scheduled jobs │  └────────────────────────┘   │
│  │                   │                               │
│  └──────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

## Services

| Service | Description | Port |
|---------|-------------|------|
| `openclaw-gateway` | Main agent runtime, API gateway, Telegram bot | 18789 |
| `syncthing` | Bidirectional sync between workspace vault and Obsidian | 8385 |
| `openclaw-cli` | Interactive CLI for admin tasks (runs on demand) | — |

## Directory Structure

```
openclaw/
├── Dockerfile              # Custom image (base + gog, obsidian-cli, tailscale)
├── docker-compose.yaml     # Service definitions
├── Makefile                # Shortcuts for common operations
├── .env                    # Secrets (not committed)
├── .gitignore
│
├── config/                 # OpenClaw system config (persisted volume)
│   ├── openclaw.json       # Main configuration
│   ├── cron/jobs.json      # Scheduled tasks
│   ├── agents/             # Agent sessions and auth
│   ├── credentials/        # OAuth tokens (not committed)
│   ├── identity/           # Device identity (not committed)
│   └── telegram/           # Telegram state
│
├── workspace/              # Agent workspace (persisted volume, synced via Syncthing)
│
├── gog-config/             # Google Workspace CLI config and tokens
├── syncthing-config/       # Syncthing state (not committed)
└── tailscale-state/        # Tailscale VPN state (not committed)
```

## Prerequisites

- Docker and Docker Compose
- A Telegram bot token (from [@BotFather](https://t.me/BotFather))
- Tailscale installed on the host (optional, for remote access)
- A Google Cloud project with OAuth credentials (for Google Workspace integration)

## Getting Started

### 1. Clone and configure

```bash
git clone <repo-url> /volume1/docker/openclaw
cd /volume1/docker/openclaw
```

Create `.env` from the template:

```bash
cat > .env << 'EOF'
# OpenClaw NAS - Environment Variables

OPENCLAW_GATEWAY_TOKEN=<generate-a-random-token>
TELEGRAM_BOT_TOKEN=<your-telegram-bot-token>

# Google Workspace (gog CLI)
GOG_ACCOUNT=you@gmail.com
GOG_KEYRING_PASSWORD=<a-secure-password-for-local-keyring>
EOF
```

Generate a gateway token:

```bash
openssl rand -hex 24
```

### 2. Build and start

```bash
make update    # or: sudo docker compose build && sudo docker compose up -d
```

### 3. Onboard (first run)

```bash
make onboard
```

This runs the setup wizard to authenticate with your LLM provider(s).

### 4. Set up Google Workspace (optional)

The `gog` CLI provides access to Gmail, Calendar, Drive, Contacts, Sheets, and Docs.

#### a. Create Google Cloud credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable **Gmail API** and **Google Calendar API** (and any others you need)
4. Go to **APIs & Services > OAuth consent screen**
   - Choose External (for @gmail.com accounts)
   - Add your email as a test user
   - Optionally click **Publish App** to prevent token expiry every 7 days
5. Go to **APIs & Services > Credentials > Create Credentials > OAuth client ID**
   - Type: **Desktop app**
   - Download the JSON file

#### b. Configure gog

```bash
# Copy credentials to the mounted volume
cp ~/Downloads/client_secret_*.json /volume1/docker/openclaw/gog-config/client_secret.json

# Open a shell in the container
sudo docker compose --profile tools run --rm --entrypoint bash openclaw-cli

# Inside the container:
gog auth keyring file
gog auth credentials /home/node/.config/gogcli/client_secret.json
gog auth add you@gmail.com --services gmail,calendar,drive,contacts --manual
```

The `--manual` flag prints a URL. Open it in your browser, authorize, and paste the code back.

#### c. Verify

```bash
gog gmail search 'is:unread' --max 5
gog calendar events --max 5
```

### 5. Configure Telegram

The bot token goes in `.env`. To set up the allowlist:

```bash
make cli
# Then: channels telegram setup
```

Or edit `config/openclaw.json` directly — set your Telegram user ID in `channels.telegram.allowFrom`.

## Daily Operations

```bash
make help              # Show all available commands

make up                # Start all services
make down              # Stop all services
make restart           # Restart all services
make restart-gateway   # Restart only the gateway

make logs              # Tail gateway logs
make logs-all          # Tail all service logs
make status            # Show running containers

make update            # Pull latest image, rebuild, restart
make version           # Compare running vs available versions

make cli               # Open interactive CLI
make clean             # Remove dangling Docker images
```

## Security

- **Gateway** binds to loopback only — not exposed to the network directly
- **Tailscale** provides encrypted VPN access from anywhere
- **Telegram** uses an allowlist — only authorized user IDs can interact
- **Secrets** (`.env`, credentials, identity) are excluded from git
- **Agent** asks before any external action (sending emails, public posts)

## Updating

```bash
make update
```

This pulls the latest `alpine/openclaw` image, rebuilds the custom layer (gog, obsidian-cli, tailscale), and restarts everything.
