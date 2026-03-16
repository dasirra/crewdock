#!/usr/bin/env bash
# 08-gh.sh — Persist GitHub CLI auth (so ACP sessions can use gh)
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
# acpx strips GH_TOKEN/GITHUB_TOKEN from spawned processes,
# so gh must be authenticated via its own credential store.

GH_HOSTS="$HOME/.config/gh/hosts.yml"

if [ -f "$GH_HOSTS" ]; then
    log "GitHub CLI credentials already stored, skipping."
    return 0
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
    log "GITHUB_TOKEN not set, skipping gh auth."
    return 0
fi

# Write credentials directly (gh auth login validates scopes
# and rejects tokens missing read:org, but repo scope is enough)
log "Persisting GitHub CLI credentials..."
mkdir -p "$(dirname "$GH_HOSTS")"
cat > "$GH_HOSTS" <<EOF
github.com:
    oauth_token: $GITHUB_TOKEN
    git_protocol: https
EOF

log "OK"
