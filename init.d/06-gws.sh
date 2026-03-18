#!/usr/bin/env bash
# 06-gws.sh -- Google Workspace CLI credentials check
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

GWS_CREDS="${GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE:-$HOME/.config/gws/credentials.json}"

if [ -f "$GWS_CREDS" ]; then
    log "Google Workspace CLI credentials found."
    return 0
fi

log "Google Workspace CLI credentials not found at $GWS_CREDS"
log "To authenticate (requires a browser):"
log "  1. On your local machine: npx @googleworkspace/cli auth login"
log "  2. Export credentials:    npx @googleworkspace/cli auth export --unmasked > config/gws/credentials.json"
log "  3. Restart the container: make restart"
