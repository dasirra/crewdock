#!/usr/bin/env bash
# 03-channels.sh — Configure Discord accounts (one per bot token)
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh

# Allow all guild members to interact (top-level default)
node dist/index.js config set channels.discord.groupPolicy '"open"' --json

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ]; then
        log "Skipping $AGENT (${TOKEN_VAR} not set)"
        continue
    fi

    # Set token if not already configured
    EXISTING=$(node dist/index.js config get "channels.discord.accounts.$AGENT.token" 2>/dev/null || echo "")
    if [ -z "$EXISTING" ]; then
        log "Configuring Discord account for $AGENT..."
        node dist/index.js config set "channels.discord.accounts.$AGENT.token" "\"$TOKEN\"" --json
    fi

    # Allow all guild members to interact
    node dist/index.js config set "channels.discord.accounts.$AGENT.groupPolicy" '"open"' --json

    # Always ensure guild allowlist is configured (idempotent)
    CHANNEL_VAR="DISCORD_${UPPER}_CHANNEL"
    CHANNEL="${!CHANNEL_VAR:-}"
    if [ -n "${DISCORD_GUILD:-}" ]; then
        if [ -n "$CHANNEL" ]; then
            log "Ensuring guild allowlist for $AGENT (guild: $DISCORD_GUILD, channel: $CHANNEL)..."
            node dist/index.js config set "channels.discord.accounts.$AGENT.guilds" \
                "{\"$DISCORD_GUILD\":{\"channels\":{\"$CHANNEL\":{\"allow\":true,\"requireMention\":false}}}}" --json
        else
            log "Ensuring guild allowlist for $AGENT (guild: $DISCORD_GUILD, all channels)..."
            node dist/index.js config set "channels.discord.accounts.$AGENT.guilds" "{\"$DISCORD_GUILD\":{}}" --json
        fi
    fi

    log "OK"
done
