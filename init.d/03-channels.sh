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

    # Configure guild allowlist with channel restriction
    CHANNEL_VAR="DISCORD_${UPPER}_CHANNEL"
    CHANNEL="${!CHANNEL_VAR:-}"
    if [ -n "${DISCORD_GUILD:-}" ]; then
        if [ -n "$CHANNEL" ]; then
            log "Setting guild allowlist for $AGENT (guild: $DISCORD_GUILD, channel: $CHANNEL)..."
            node dist/index.js config set "channels.discord.accounts.$AGENT.guilds" \
                "{\"$DISCORD_GUILD\":{\"channels\":{\"$CHANNEL\":{\"allow\":true}}}}" --json
        else
            log "Setting guild allowlist for $AGENT (guild: $DISCORD_GUILD, all channels)..."
            node dist/index.js config set "channels.discord.accounts.$AGENT.guilds" "{\"$DISCORD_GUILD\":{}}" --json
        fi
    fi

    log "OK"
done
