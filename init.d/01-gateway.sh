#!/usr/bin/env bash
# 01-gateway.sh — Gateway token configuration
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

# Check if gateway token is already configured
if node dist/index.js config get gateway.auth.token 2>/dev/null | grep -q .; then
    log "Gateway token already configured, skipping."
    return 0
fi

# Use env var or generate a new token
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    TOKEN="$OPENCLAW_GATEWAY_TOKEN"
    log "Using gateway token from environment."
else
    TOKEN=$(openssl rand -hex 32)
    log "Generated new gateway token."
fi

node dist/index.js config set gateway.auth.token "$TOKEN"

# Allow Control UI access from configured origins (or wildcard if unset)
ORIGINS="${OPENCLAW_ALLOWED_ORIGINS:-*}"
ORIGINS_JSON=$(echo "$ORIGINS" | jq -R 'split(",")')
node dist/index.js config set gateway.controlUi.allowedOrigins "$ORIGINS_JSON" --json

if [ "$ORIGINS" = "*" ]; then
    log "WARNING: controlUi.allowedOrigins is set to '*'. Set OPENCLAW_ALLOWED_ORIGINS in .env to restrict access."
fi

log "OK"
