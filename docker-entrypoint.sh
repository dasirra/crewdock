#!/usr/bin/env bash
set -euo pipefail

# Init scripts are `source`d (not executed as subprocesses), so they share
# this shell's environment and should use `return` (not `exit`) to bail out.

INIT_DIR="/usr/local/lib/openclaw-init.d"
MARKER="$HOME/.openclaw/workspace/.initialized"

# Shared helpers for init scripts (sourced into same shell)
log() { echo "[init] $SCRIPT_NAME: $*"; }

# Agents with Discord integration (used by 03-channels.sh and 05-bindings.sh)
DISCORD_AGENTS="forge scouter"

if [ -f "$MARKER" ]; then
    echo "[init] Already initialized. Starting gateway..."
    exec "$@"
fi

# First boot: start gateway in background so CLI commands can talk to it
echo "[init] First boot detected. Starting gateway for configuration..."
"$@" &
GATEWAY_PID=$!

# Forward signals to the gateway process
trap 'kill "$GATEWAY_PID" 2>/dev/null; wait "$GATEWAY_PID" 2>/dev/null' SIGTERM SIGINT

# Wait for gateway to accept connections
echo "[init] Waiting for gateway to be ready..."
for i in $(seq 1 60); do
    if ! kill -0 "$GATEWAY_PID" 2>/dev/null; then
        echo "[init] ERROR: Gateway process died during startup."
        exit 1
    fi
    if curl -sf "http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}/" >/dev/null 2>&1; then
        echo "[init] Gateway ready. Running initialization..."
        break
    fi
    sleep 1
done

# Run init scripts (gateway is running, full CLI available)
for script in "$INIT_DIR"/*.sh; do
    [ -f "$script" ] || continue
    SCRIPT_NAME="$(basename "$script" .sh)"
    echo "[init] Running $(basename "$script")..."
    # shellcheck source=/dev/null
    source "$script"
done

# Apply any config migrations flagged by the CLI
node dist/index.js doctor --fix 2>/dev/null || true

mkdir -p "$(dirname "$MARKER")"
touch "$MARKER"
echo "[init] Setup complete. Gateway is running."

# Keep container alive by waiting on the gateway process
wait "$GATEWAY_PID"
