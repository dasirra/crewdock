#!/usr/bin/env bash
# 06-claude.sh — Claude CLI auth configuration
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

CLAUDE_DIR="$HOME/.claude"

# Check if Claude auth is already configured
if [ -f "$CLAUDE_DIR/.credentials.json" ] || [ -f "$HOME/.claude.json" ]; then
    log "Claude CLI already configured, skipping."
    return 0
fi

if [ -z "${ANTHROPIC_OAUTH_TOKEN:-}" ]; then
    log "WARNING: ANTHROPIC_OAUTH_TOKEN not set, skipping Claude CLI setup."
    return 0
fi

log "Configuring Claude CLI auth..."
mkdir -p "$CLAUDE_DIR"

# The bind mount (./config/claude:/home/node/.claude) starts empty, so we
# create settings.json here. Auth uses ANTHROPIC_AUTH_TOKEN env var
# (set in docker-compose.yaml), no credential file needed.
cat > "$CLAUDE_DIR/settings.json" <<'SETTINGS'
{"plugins":{"allow":["acpx"]}}
SETTINGS

log "OK (using ANTHROPIC_AUTH_TOKEN env var for auth)"
