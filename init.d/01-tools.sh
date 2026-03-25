#!/usr/bin/env bash
# 00-tools.sh -- Install user-space tools into persistent $HOME volume
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# Runs as `node` user. Tools are installed once and persist across restarts.

# --- Claude Code CLI ---
# Pre-installed in the Docker image at build time; this is a no-op check.
if command -v claude &>/dev/null; then
    log "Claude CLI already installed: $(claude --version 2>/dev/null || echo 'unknown')"
else
    log "WARNING: Claude CLI not found. It should be pre-installed in the Docker image."
fi

# --- Google Workspace CLI skills ---
# Pinned to a specific commit to prevent supply-chain attacks.
GWS_COMMIT="a52d297cdfafbc53dfed66a3721a9bbd1d50dc31"
if npx skills list 2>/dev/null | grep -q googleworkspace; then
    log "GWS skills already installed."
else
    log "Installing Google Workspace skills (pinned commit: ${GWS_COMMIT})..."
    npx -y skills add "https://github.com/googleworkspace/cli#${GWS_COMMIT}" -y
    log "GWS skills installed."
fi

log "OK"
