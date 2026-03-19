#!/usr/bin/env bash
# 08-welcome.sh -- Send setup reminder to Discord if no LLM provider is authenticated
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

MAIN_DIR="$HOME/.openclaw/workspace/agents/main"
AUTH_FILE="$MAIN_DIR/auth-profiles.json"

# Skip if auth is already configured
if [ -f "$AUTH_FILE" ]; then
    log "LLM auth found, skipping welcome message."
    return 0
fi

# Skip if no Discord credentials for Alfred
if [ -z "${DISCORD_ALFRED_TOKEN:-}" ] || [ -z "${DISCORD_ALFRED_CHANNEL:-}" ]; then
    log "No Discord credentials for Alfred, skipping welcome message."
    return 0
fi

log "No LLM auth configured. Sending setup reminder to Discord..."

curl -sf -X POST \
    "https://discord.com/api/v10/channels/${DISCORD_ALFRED_CHANNEL}/messages" \
    -H "Authorization: Bot ${DISCORD_ALFRED_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "embeds": [{
            "title": "Setup Required",
            "description": "No LLM provider is authenticated yet. I cannot respond to messages until you configure at least one provider.\n\n**Run one of these on the host:**\n```\nmake auth-codex\nmake auth-anthropic\n```\nThen restart: `make restart`",
            "color": 16753920
        }]
    }' >/dev/null 2>&1 && log "Welcome message sent." || log "Failed to send welcome message."

log "OK"
