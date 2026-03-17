#!/usr/bin/env bash
# 11-secrets.sh — Convert plaintext tokens to SecretRefs
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
#
# Reads env vars for known tokens and applies a secrets plan so openclaw.json
# stores SecretRefs instead of plaintext values. Idempotent: safe to re-run.
# Gateway token migration is opt-in: requires OPENCLAW_GATEWAY_TOKEN in .env.

PLAN='{"version":1,"protocolVersion":1,"targets":[]}'

# Gateway token (opt-in: only if OPENCLAW_GATEWAY_TOKEN is set in env)
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    PLAN=$(echo "$PLAN" | jq '.targets += [{
      "type": "gateway.auth.token",
      "path": "gateway.auth.token",
      "ref": {"source":"env","provider":"default","id":"OPENCLAW_GATEWAY_TOKEN"}
    }]')
fi

# Discord tokens (forge, scouter, alfred, etc.)
# DISCORD_AGENTS is set in docker-entrypoint.sh; default guard for safety.
for AGENT in ${DISCORD_AGENTS:-forge scouter alfred}; do
    UPPER=$(echo "$AGENT" | tr '[:lower:]' '[:upper:]')
    TOKEN_VAR="DISCORD_${UPPER}_TOKEN"
    if [ -n "${!TOKEN_VAR:-}" ]; then
        PLAN=$(echo "$PLAN" | jq --arg agent "$AGENT" --arg var "$TOKEN_VAR" \
          '.targets += [{
            "type": "channels.discord.accounts.*.token",
            "path": ("channels.discord.accounts." + $agent + ".token"),
            "ref": {"source":"env","provider":"default","id": $var}
          }]')
    fi
done

# Apply only if there are targets
TARGET_COUNT=$(echo "$PLAN" | jq '.targets | length')
if [ "$TARGET_COUNT" -gt 0 ]; then
    echo "$PLAN" > /tmp/secrets-plan.json
    trap 'rm -f /tmp/secrets-plan.json' EXIT
    log "Applying secrets plan ($TARGET_COUNT targets)..."
    node dist/index.js secrets apply --from /tmp/secrets-plan.json
    rm -f /tmp/secrets-plan.json
    trap - EXIT
    log "OK"
else
    log "No token env vars found, skipping secrets migration."
fi
