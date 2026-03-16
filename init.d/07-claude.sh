#!/usr/bin/env bash
# 07-claude.sh — Claude CLI settings and plugins
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

# Copy bundled commands
COMMANDS_SRC="/opt/claude/commands"
COMMANDS_DST="$CLAUDE_DIR/commands"
if [ -d "$COMMANDS_SRC" ]; then
    mkdir -p "$COMMANDS_DST"
    cp -r "$COMMANDS_SRC"/* "$COMMANDS_DST/"
    log "Installed bundled commands: $(ls "$COMMANDS_DST" | tr '\n' ' ')"
fi

# Add official marketplace and install plugins
log "Adding official plugin marketplace..."
claude plugin marketplace add anthropics/claude-plugins-official

log "Installing superpowers plugin..."
claude plugin install superpowers

log "OK"
