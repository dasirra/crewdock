#!/usr/bin/env bash
# 03-channels.sh — Configure Discord accounts (one per bot token)
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ]; then
        log "Skipping $AGENT (${TOKEN_VAR} not set)"
        continue
    fi

    # Check if this account is already configured
    EXISTING=$(node dist/index.js config get "channels.discord.accounts.$AGENT.token" 2>/dev/null || echo "")
    if [ -n "$EXISTING" ]; then
        log "Discord account '$AGENT' already configured, skipping."
        continue
    fi

    log "Configuring Discord account for $AGENT..."
    node dist/index.js config set "channels.discord.accounts.$AGENT.token" "\"$TOKEN\"" --json
    log "OK"
done
