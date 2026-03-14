#!/usr/bin/env bash
# 05-bindings.sh — Bind agents to Discord accounts
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
# Gateway is running at this point, so agents bind CLI works.

EXISTING_BINDINGS=$(node dist/index.js agents bindings 2>/dev/null || echo "")

for AGENT in $DISCORD_AGENTS; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    TOKEN="${!TOKEN_VAR:-}"

    if [ -z "$TOKEN" ]; then
        log "Skipping $AGENT (Discord not configured)"
        continue
    fi

    if echo "$EXISTING_BINDINGS" | grep -q "$AGENT.*discord"; then
        log "Agent '$AGENT' already bound to Discord, skipping."
        continue
    fi

    log "Binding $AGENT to Discord account..."
    node dist/index.js agents bind --agent "$AGENT" --bind "discord:$AGENT"
    log "OK"
done
