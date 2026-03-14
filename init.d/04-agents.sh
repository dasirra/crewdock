#!/usr/bin/env bash
# 04-agents.sh — Install agents and initialize databases

SCRIPT_NAME="04-agents"
log() { echo "[init] $SCRIPT_NAME: $*"; }

AGENT_TEMPLATES="/opt/openclaw-agents"
WORKSPACE="$HOME/.openclaw/workspace"

for agent_dir in "$AGENT_TEMPLATES"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name=$(basename "$agent_dir")
    target="$WORKSPACE/agents/$agent_name"
    sentinel="$target/SOUL.md"

    # Check sentinel file for complete installation
    if [ -f "$sentinel" ]; then
        log "Agent '$agent_name' already installed, skipping."
        continue
    fi

    log "Installing agent '$agent_name'..."

    # Register agent with OpenClaw (may fail if already partially registered)
    if ! node dist/index.js agents add "$agent_name" --workspace "$target" --non-interactive 2>/dev/null; then
        log "WARNING: 'agents add' failed for $agent_name (may already be registered). Continuing with file copy."
    fi

    # Copy agent files from template
    mkdir -p "$target"
    cp -r "$agent_dir"* "$target/"

    # Rename .example.* files to their real names
    for example in "$target"/*.example.*; do
        [ -f "$example" ] || continue
        real="${example/.example/}"
        mv "$example" "$real"
    done

    log "OK"
done

# Initialize agent databases (runs for all agents, not just newly installed ones).
# The *-db.sh init commands are idempotent (CREATE TABLE IF NOT EXISTS).
for db_script in "$WORKSPACE"/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    chmod +x "$db_script"
    "$db_script" init
    log "$agent_name database initialized."
done
