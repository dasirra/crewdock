#!/usr/bin/env bash
set -euo pipefail

# Init scripts are `source`d (not executed as subprocesses), so they share
# this shell's environment and should use `return` (not `exit`) to bail out.

INIT_DIR="/usr/local/lib/openclaw-init.d"
MARKER="$HOME/.openclaw/workspace/.initialized"

if [ -f "$MARKER" ]; then
    echo "[init] Already initialized. Starting gateway..."
else
    echo "[init] First boot detected. Running initialization..."

    for script in "$INIT_DIR"/*.sh; do
        [ -f "$script" ] || continue
        echo "[init] Running $(basename "$script")..."
        # shellcheck source=/dev/null
        source "$script"
    done

    mkdir -p "$(dirname "$MARKER")"
    touch "$MARKER"
    echo "[init] Setup complete. Starting gateway..."
fi

exec "$@"
