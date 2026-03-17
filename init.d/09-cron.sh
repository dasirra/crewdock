#!/usr/bin/env bash
# 09-cron.sh — Install agent cron jobs from workspace configs
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
#
# Scans all agent config.json files for a `briefing` block.
# If briefing.enabled is true and briefing.cron is set, installs a
# crontab entry that triggers the agent's heartbeat via the gateway RPC.
# Generic: any agent with a briefing config gets cron support.

WORKSPACE="$HOME/.openclaw/workspace"
PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

# Read gateway auth token for RPC calls.
# Prefer env var: after secrets migration, the config value is a SecretRef object,
# not a plaintext string. If OPENCLAW_GATEWAY_TOKEN is not set, the gateway token
# was not migrated and the config still holds a plaintext string.
if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    TOKEN="$OPENCLAW_GATEWAY_TOKEN"
else
    TOKEN=$(jq -r '.gateway.auth.token // empty' "$HOME/.openclaw/openclaw.json" 2>/dev/null)
fi
if [ -z "$TOKEN" ]; then
    log "No gateway token found, skipping cron setup."
    return 0
fi

CRON_ENTRIES=""

for config_file in "$WORKSPACE"/agents/*/config.json; do
    [ -f "$config_file" ] || continue
    agent_name=$(basename "$(dirname "$config_file")")

    cron_expr=$(jq -r '.briefing.cron // empty' "$config_file" 2>/dev/null)
    enabled=$(jq -r '.briefing.enabled // false' "$config_file" 2>/dev/null)

    if [ -n "$cron_expr" ] && [ "$enabled" = "true" ]; then
        # Build cron entry that triggers agent heartbeat via gateway RPC
        CRON_ENTRIES="${CRON_ENTRIES}${cron_expr} curl -sf -X POST http://127.0.0.1:${PORT}/rpc -H 'Content-Type: application/json' -H 'Authorization: Bearer ${TOKEN}' -d '{\"jsonrpc\":\"2.0\",\"method\":\"agents_heartbeat\",\"params\":{\"agentId\":\"${agent_name}\"},\"id\":1}' >/dev/null 2>&1
"
        log "Cron: $agent_name at '$cron_expr'"
    fi
done

if [ -n "$CRON_ENTRIES" ]; then
    # Write crontab (overwrites previous entries on each boot)
    echo "$CRON_ENTRIES" | crontab -u node -
    # Start cron daemon if not already running
    service cron start >/dev/null 2>&1 || cron 2>/dev/null || true
    log "Installed cron jobs and started daemon."
else
    # Clear any stale crontab
    crontab -u node -r 2>/dev/null || true
    log "No cron jobs needed."
fi
