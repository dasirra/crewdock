#!/usr/bin/env bash
# 02-models.sh — LLM provider auth (Anthropic)
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

if [ -z "${ANTHROPIC_OAUTH_TOKEN:-}" ]; then
    log "ERROR: ANTHROPIC_OAUTH_TOKEN is not set."
    return 1
fi

# Check if Anthropic is already configured
if node dist/index.js models status --probe 2>/dev/null | grep -qi "anthropic"; then
    log "Anthropic provider already configured, skipping."
    return 0
fi

log "Configuring Anthropic provider..."
echo "$ANTHROPIC_OAUTH_TOKEN" | node dist/index.js models auth paste-token --provider anthropic
log "OK"
