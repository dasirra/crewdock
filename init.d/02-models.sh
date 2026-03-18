#!/usr/bin/env bash
# 02-models.sh -- LLM provider credential persistence
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
#
# paste-token writes credentials to disk (no gateway needed).
# It is idempotent: re-running with the same token is safe.

if [ -z "${ANTHROPIC_OAUTH_TOKEN:-}" ]; then
    log "WARNING: ANTHROPIC_OAUTH_TOKEN is not set. Skipping."
    return 0
fi

log "Writing Anthropic credentials..."
echo "$ANTHROPIC_OAUTH_TOKEN" | node dist/index.js models auth paste-token --provider anthropic

log "OK"
