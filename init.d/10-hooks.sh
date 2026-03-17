#!/usr/bin/env bash
# 10-hooks.sh — Configure OpenClaw hooks for GitHub webhook integration
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

if [ -z "${HOOKS_TOKEN:-}" ]; then
    log "HOOKS_TOKEN not set, skipping hooks configuration."
    return 0
fi

# Check if route already configured
EXISTING=$(node dist/index.js config get "hooks.routes" 2>/dev/null || echo "")
if echo "$EXISTING" | grep -q "/hooks/github"; then
    log "Hooks route /hooks/github already configured, skipping."
    return 0
fi

log "Configuring GitHub webhook hooks route..."

node dist/index.js config set "hooks.token" "\"${HOOKS_TOKEN}\"" --json

node dist/index.js config set "hooks.routes" \
    '[{"path":"/hooks/github","agentId":"forge","messageTemplate":"run {{repository.full_name}} #{{issue.number}}"}]' \
    --json

log "OK"
