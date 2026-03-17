#!/usr/bin/env bash
# 01-gateway.sh — Gateway token configuration
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

# Set gateway mode (required by doctor)
node dist/index.js config set gateway.mode local

# Disable memory search (no embedding provider configured)
node dist/index.js config set agents.defaults.memorySearch.enabled false

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

# Allow Control UI access from any origin (safe on private/Tailscale networks)
node dist/index.js config set gateway.controlUi.allowedOrigins '["*"]' --json

log "OK"
