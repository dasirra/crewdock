#!/usr/bin/env bash
# 03-channels.sh — Add Discord channels (one per bot token)
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh

EXISTING_CHANNELS=$(node dist/index.js channels list 2>/dev/null || echo "")

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ]; then
        log "Skipping $AGENT (${TOKEN_VAR} not set)"
        continue
    fi

    if echo "$EXISTING_CHANNELS" | grep -q "$AGENT"; then
        log "Discord channel for $AGENT already exists, skipping."
        continue
    fi

    log "Adding Discord channel for $AGENT..."
    node dist/index.js channels add --channel discord --account "$AGENT" --token "$TOKEN"
    log "OK"
done
