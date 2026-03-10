#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== OpenClaw Setup ==="
echo ""

# --- Version pin ---
if [ -f .openclaw-version ]; then
    echo "[ok] .openclaw-version already exists ($(cat .openclaw-version)), skipping."
else
    LATEST=$(curl -sf "https://hub.docker.com/v2/repositories/alpine/openclaw/tags/?page_size=50&ordering=last_updated" \
      | jq -r '[.results[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | first' 2>/dev/null)
    if [ -n "$LATEST" ]; then
        echo "$LATEST" > .openclaw-version
        echo "[ok] Pinned OpenClaw version to $LATEST"
    else
        echo "latest" > .openclaw-version
        echo "[!!] Could not reach Docker Hub, defaulting to 'latest'"
    fi
fi

# --- .env ---
if [ -f .env ]; then
    echo "[ok] .env already exists, skipping."
else
    cp .env.example .env

    # Generate gateway token
    TOKEN=$(openssl rand -hex 32 2>/dev/null || head -c 64 /dev/urandom | od -An -tx1 | tr -d ' \n')
    sed -i "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=$TOKEN/" .env

    echo "[ok] Created .env with generated gateway token."
fi

# --- Directories ---
mkdir -p config/openclaw config/claude workspace/agents projects
echo "[ok] Runtime directories created."

# --- Install agents ---
if [ -d agents ]; then
    for agent_dir in agents/*/; do
        agent_name=$(basename "$agent_dir")
        target="workspace/agents/$agent_name"

        if [ -d "$target" ]; then
            echo "[ok] Agent '$agent_name' already installed, skipping."
        else
            cp -r "$agent_dir" "$target"

            # Rename example configs
            for example in "$target"/*.example.*; do
                [ -f "$example" ] || continue
                real="${example/.example/}"
                mv "$example" "$real"
            done

            echo "[ok] Installed agent '$agent_name'."
        fi
    done
else
    echo "[!!] No agents/ directory found."
fi

# --- Initialize Forge SQLite database ---
FORGE_DB_SH="workspace/agents/forge/forge-db.sh"
if [ -f "$FORGE_DB_SH" ]; then
    chmod +x "$FORGE_DB_SH"
    "$FORGE_DB_SH" init
    echo "[ok] Forge tracking database initialized."
fi

echo ""
echo "==========================================="
echo "  Setup complete. Follow these steps:"
echo "==========================================="
echo ""
echo "  STEP 1: Set your API keys"
echo ""
echo "    Edit .env and fill in:"
echo "      ANTHROPIC_API_KEY=sk-ant-..."
echo "      GITHUB_TOKEN=ghp_..."
echo ""
echo "  STEP 2: Build and start"
echo ""
echo "    make up"
echo ""
echo "  STEP 3: Run OpenClaw onboarding"
echo ""
echo "    make onboard"
echo ""
echo "    This walks you through:"
echo "    - LLM provider auth (Anthropic)"
echo "    - Telegram bot setup (optional)"
echo "    - Discord bot setup (optional)"
echo ""
echo "  STEP 4: Authenticate Claude Code (for Forge agent)"
echo ""
echo "    make shell"
echo "    claude"
echo ""
echo "    This opens the Claude CLI auth flow inside the"
echo "    container. Forge uses it to spawn coding sessions."
echo ""
echo "  STEP 5: Configure Forge"
echo ""
echo "    Edit workspace/agents/forge/config.json"
echo "    with your GitHub repos. Then message Forge via Telegram"
echo "    or run: make shell -> run the agent manually."
echo ""
echo "==========================================="
echo ""
