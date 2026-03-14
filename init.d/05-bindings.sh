#!/usr/bin/env bash
# 05-bindings.sh — Bind agents to Discord channels
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh

EXISTING_BINDINGS=$(node dist/index.js agents list --bindings 2>/dev/null || echo "")

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    CHANNEL_VAR="DISCORD_${UPPER}_CHANNEL"
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    CHANNEL="${!CHANNEL_VAR:-}"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ] || [ -z "$CHANNEL" ]; then
        log "Skipping $AGENT (Discord not configured)"
        continue
    fi

    if echo "$EXISTING_BINDINGS" | grep -q "$AGENT.*discord"; then
        log "Agent '$AGENT' already bound to Discord, skipping."
        continue
    fi

    log "Binding $AGENT to Discord channel..."
    node dist/index.js agents bind --agent "$AGENT" --bind "discord:$AGENT"
    log "OK"
done
