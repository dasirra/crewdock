#!/usr/bin/env bash
# 05-bindings.sh — Bind agents to Discord accounts
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
# Uses jq to write bindings directly to config (agents bind CLI needs the gateway running)

CONFIG_FILE="$HOME/.openclaw/openclaw.json"

if [ ! -f "$CONFIG_FILE" ]; then
    log "WARNING: $CONFIG_FILE not found, skipping bindings."
    return 0
fi

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ]; then
        log "Skipping $AGENT (Discord not configured)"
        continue
    fi

    # Check if binding already exists
    if jq -e ".bindings[]? | select(.agentId == \"$AGENT\" and .match.channel == \"discord\")" "$CONFIG_FILE" >/dev/null 2>&1; then
        log "Agent '$AGENT' already bound to Discord, skipping."
        continue
    fi

    log "Binding $AGENT to Discord account..."
    jq ".bindings = (.bindings // []) + [{\"agentId\": \"$AGENT\", \"match\": {\"channel\": \"discord\", \"accountId\": \"$AGENT\"}}]" \
        "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    log "OK"
done
