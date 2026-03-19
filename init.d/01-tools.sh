#!/usr/bin/env bash
# 00-tools.sh -- Install user-space tools into persistent $HOME volume
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# Runs as `node` user. Tools are installed once and persist across restarts.

# --- Claude Code CLI ---
if command -v claude &>/dev/null; then
    log "Claude CLI already installed: $(claude --version 2>/dev/null || echo 'unknown')"
else
    log "Installing Claude CLI..."
    curl -fsSL https://claude.ai/install.sh | bash
    log "Claude CLI installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi

# --- Google Workspace CLI skills ---
if npx skills list 2>/dev/null | grep -q googleworkspace; then
    log "GWS skills already installed."
else
    log "Installing Google Workspace skills..."
    npx -y skills add https://github.com/googleworkspace/cli -y
    log "GWS skills installed."
fi

log "OK"
