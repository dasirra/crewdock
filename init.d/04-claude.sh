#!/usr/bin/env bash
# 04-claude.sh -- Claude CLI settings, commands, and plugins
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# Auth is handled by CLAUDE_CODE_OAUTH_TOKEN env var (no setup needed).

CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

# --- Settings (user data, create only if missing) ---
if [ ! -f "$SETTINGS" ]; then
    log "Creating Claude CLI settings..."
    mkdir -p "$CLAUDE_DIR"
    cat > "$SETTINGS" <<'JSON'
{"plugins":{"allow":["acpx"]}}
JSON
fi

# --- Bundled commands (always sync from image) ---
COMMANDS_SRC="/opt/claude/commands"
COMMANDS_DST="$CLAUDE_DIR/commands"
if [ -d "$COMMANDS_SRC" ]; then
    mkdir -p "$COMMANDS_DST"
    cp -r "$COMMANDS_SRC"/* "$COMMANDS_DST/"
    log "Synced bundled commands: $(ls "$COMMANDS_DST" | tr '\n' ' ')"
fi

# --- Plugins (install only if not already set up) ---
if [ ! -d "$CLAUDE_DIR/plugins" ]; then
    log "Adding official plugin marketplace..."
    claude plugin marketplace add anthropics/claude-plugins-official

    log "Installing superpowers plugin..."
    claude plugin install superpowers
else
    log "Claude plugins already installed."
fi

log "OK"
