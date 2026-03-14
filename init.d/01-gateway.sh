#!/usr/bin/env bash
# 01-gateway.sh — Gateway token configuration

SCRIPT_NAME="01-gateway"
log() { echo "[init] $SCRIPT_NAME: $*"; }

# Check if gateway token is already configured
if node dist/index.js config get gateway.token 2>/dev/null | grep -q .; then
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

node dist/index.js config set gateway.token "$TOKEN"
log "OK"
