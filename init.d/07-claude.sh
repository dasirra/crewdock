#!/usr/bin/env bash
# 07-claude.sh — Claude CLI settings
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# Auth is handled by CLAUDE_CODE_OAUTH_TOKEN env var (no setup needed).

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ -f "$SETTINGS" ]; then
    log "Claude CLI settings already exist, skipping."
    return 0
fi

log "Creating Claude CLI settings..."
mkdir -p "$CLAUDE_DIR"
cat > "$SETTINGS" <<'JSON'
{"plugins":{"allow":["acpx"]}}
JSON

log "OK"
