#!/usr/bin/env bash
# 01-config.sh -- Build openclaw.json from env vars + preserved heartbeats
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
#
# Standalone usage (preview mode):
#   DISCORD_AGENTS="forge scouter alfred" bash init.d/01-config.sh --preview

# Support standalone preview mode (used by 'make config-preview')
if [ -z "${SCRIPT_NAME:-}" ]; then
    SCRIPT_NAME="01-config"
    log() { echo "[preview] $*"; }
    DISCORD_AGENTS="${DISCORD_AGENTS:-forge scouter alfred}"
fi

CONFIG_FILE="${HOME}/.openclaw/openclaw.json"
WORKSPACE="${HOME}/.openclaw/workspace"

PREVIEW=false
if [ "${1:-}" = "--preview" ] || [ "${CONFIG_PREVIEW:-}" = "1" ]; then
    PREVIEW=true
fi

# ---------- Step 1: Preserve heartbeat operational fields from existing config ----------

SAVED_HEARTBEATS='{}'
SAVED_GW_TOKEN=''

if [ -f "$CONFIG_FILE" ]; then
    SAVED_HEARTBEATS=$(jq '
        [.agents.list[]? | {
            key: .id,
            value: (.heartbeat // {}
                | del(.target, .accountId, .to, .directPolicy)
                | select(length > 0))
        }] | from_entries // {}
    ' "$CONFIG_FILE")
    SAVED_GW_TOKEN=$(jq -r '.gateway.auth.token // ""' "$CONFIG_FILE")
    log "Preserved heartbeat config from previous boot."
fi

# ---------- Step 2: Resolve gateway token ----------

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    GW_TOKEN="$OPENCLAW_GATEWAY_TOKEN"
    log "Using gateway token from environment."
elif [ -n "$SAVED_GW_TOKEN" ]; then
    GW_TOKEN="$SAVED_GW_TOKEN"
    log "Using gateway token from previous config."
else
    GW_TOKEN=$(openssl rand -hex 32)
    log "Generated new gateway token."
fi

# ---------- Step 3: Build agents data from env vars ----------

AGENTS_DATA='[]'
for agent in $DISCORD_AGENTS; do
    upper=$(echo "$agent" | tr '[:lower:]' '[:upper:]')
    token_var="DISCORD_${upper}_TOKEN"
    channel_var="DISCORD_${upper}_CHANNEL"
    token="${!token_var:-}"
    channel="${!channel_var:-}"

    [ -z "$token" ] && continue

    AGENTS_DATA=$(echo "$AGENTS_DATA" | jq \
        --arg id "$agent" \
        --arg token "$token" \
        --arg channel "$channel" \
        '. + [{id: $id, token: $token, channel: $channel}]')
done

log "Discord agents: $(echo "$AGENTS_DATA" | jq -r '[.[].id] | join(", ")') ($(echo "$AGENTS_DATA" | jq length) configured)"

# ---------- Step 4: Build core config with jq ----------

CORE=$(jq -n \
    --arg gw_token "$GW_TOKEN" \
    --arg guild "${DISCORD_GUILD:-}" \
    --arg workspace "$WORKSPACE" \
    --argjson agents "$AGENTS_DATA" \
    '
    {
        gateway: {
            mode: "local",
            auth: { token: $gw_token },
            controlUi: { allowedOrigins: ["*"] }
        },

        agents: {
            defaults: {
                memorySearch: { enabled: false }
            },
            list: [
                $agents[] | {
                    id: .id,
                    name: .id,
                    workspace: ($workspace + "/agents/" + .id),
                    agentDir: ($workspace + "/agents/" + .id)
                } + (if .channel != "" then {
                    heartbeat: {
                        every: "0m",
                        target: "discord",
                        to: ("channel:" + .channel),
                        accountId: .id,
                        directPolicy: "block"
                    }
                } else {} end)
            ]
        },

        channels: {
            discord: {
                groupPolicy: "open",
                accounts: (
                    $agents | map({
                        key: .id,
                        value: (
                            { token: .token, groupPolicy: "open" }
                            + (if $guild != "" then {
                                guilds: {
                                    ($guild): (if .channel != "" then {
                                        channels: {
                                            (.channel): {
                                                allow: true,
                                                requireMention: false
                                            }
                                        }
                                    } else {} end)
                                }
                            } else {} end)
                            + (if .id == "forge" then {
                                threadBindings: {
                                    enabled: true,
                                    spawnAcpSessions: true
                                }
                            } else {} end)
                        )
                    }) | from_entries
                )
            }
        },

        bindings: [
            $agents[] | {
                agentId: .id,
                channel: "discord",
                accountId: .id
            }
        ],

        plugins: {
            allow: ["acpx"],
            entries: {
                acpx: {
                    enabled: true,
                    config: { permissionMode: "approve-all" }
                }
            }
        },

        acp: {
            enabled: true,
            backend: "acpx"
        },

        session: {
            threadBindings: { enabled: true }
        }
    }
    ')

# ---------- Step 5: Merge preserved heartbeats ----------

FINAL=$(echo "$CORE" | jq --argjson hb "$SAVED_HEARTBEATS" '
    .agents.list |= map(
        if .heartbeat and $hb[.id] then .heartbeat += $hb[.id] else . end
    )
')

# ---------- Step 6: Write or preview ----------

if [ "$PREVIEW" = true ]; then
    echo "$FINAL" | jq .
else
    mkdir -p "$(dirname "$CONFIG_FILE")"
    echo "$FINAL" > "$CONFIG_FILE"
    log "Config written to $CONFIG_FILE"
fi
