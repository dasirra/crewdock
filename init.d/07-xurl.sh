#!/usr/bin/env bash
# 07-xurl.sh -- X/Twitter API auth for xurl CLI
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

XURL_DIR="$HOME/.xurl"

# Check if xurl is already authenticated
if [ -d "$XURL_DIR" ] && xurl auth status >/dev/null 2>&1; then
    log "xurl already authenticated."
    return 0
fi

# Auto-configure bearer token if provided via env var
if [ -n "${X_BEARER_TOKEN:-}" ]; then
    log "Configuring xurl with bearer token..."
    mkdir -p "$XURL_DIR"
    xurl auth apps add scouter --client-id "${X_CLIENT_ID:-none}" --client-secret "${X_CLIENT_SECRET:-none}" 2>/dev/null || true
    xurl auth app --bearer-token "$X_BEARER_TOKEN" 2>/dev/null
    if xurl auth status >/dev/null 2>&1; then
        log "OK"
        return 0
    fi
    log "WARNING: xurl auth setup failed. Try manual setup with: make auth-xurl"
    return 0
fi

log "xurl not authenticated. Scouter's Twitter/X scanning is disabled."
log "To set up X API access:"
log "  1. Create an app at https://developer.x.com/en/portal/dashboard"
log "  2. Copy the Bearer Token"
log "  3. Add to .env: X_BEARER_TOKEN=your_token_here"
log "  4. Restart: make restart"
log "  Or run interactively: make auth-xurl"
