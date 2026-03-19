#!/usr/bin/env bash
set -euo pipefail

# If running as root, fix permissions and re-exec as node
if [ "$(id -u)" = "0" ]; then
    chown -R node:node /home/node /home/node/projects
    exec gosu node "$0" "$@"
fi

# Init scripts are `source`d (not executed as subprocesses), so they share
# this shell's environment and should use `return` (not `exit`) to bail out.

INIT_DIR="/usr/local/lib/openclaw-init.d"

# Shared helpers for init scripts (sourced into same shell)
log() { echo "[init] $SCRIPT_NAME: $*"; }

# Agents with Discord integration (used by 01-config.sh and 03-agents.sh)
DISCORD_AGENTS="forge scouter alfred"

# Run pre-boot init scripts (gateway is NOT running yet)
for script in "$INIT_DIR"/*.sh; do
    [ -f "$script" ] || continue
    SCRIPT_NAME="$(basename "$script" .sh)"
    echo "[init] Running $(basename "$script")..."
    # shellcheck source=/dev/null
    source "$script"
done

echo "[init] Init complete. Starting gateway..."
exec "$@"
