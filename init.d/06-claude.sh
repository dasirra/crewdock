#!/usr/bin/env bash
# 06-claude.sh — Claude CLI auth configuration

SCRIPT_NAME="06-claude"
log() { echo "[init] $SCRIPT_NAME: $*"; }

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

# The Dockerfile creates settings.json in the image layer, but the bind mount
# (./config/claude:/home/node/.claude) masks it. We recreate it here.
# Auth uses ANTHROPIC_AUTH_TOKEN env var (set in docker-compose.yaml), no credential file needed.
cat > "$CLAUDE_DIR/settings.json" <<'SETTINGS'
{"plugins":{"allow":["acpx"]}}
SETTINGS

log "OK (using ANTHROPIC_AUTH_TOKEN env var for auth)"
