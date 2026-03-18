#!/usr/bin/env bash
# 01-config.sh -- Build openclaw.json from env vars + preserved heartbeats
# SCRIPT_NAME, log(), and DISCORD_AGENTS are provided by docker-entrypoint.sh
#
# Standalone usage (preview mode):
#   DISCORD_AGENTS="forge scouter alfred" bash init.d/01-config.sh --preview

# Support standalone preview mode (used by 'make config-preview')
if [ -z "${SCRIPT_NAME:-}" ]; then
    SCRIPT_NAME="01-config"
    log() { echo "[preview] $*" >&2; }
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

if [ -f "$CONFIG_FILE" ]; then
    SAVED_HEARTBEATS=$(jq '
        [.agents.list[]? | {
            key: .id,
            value: (.heartbeat // {}
                | del(.target, .accountId, .to, .directPolicy)
                | select(length > 0))
        }] | from_entries // {}
    ' "$CONFIG_FILE")
    log "Preserved heartbeat config from previous boot."
fi

# ---------- Step 2: Resolve gateway token (persisted file + env export) ----------

if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    log "Using gateway token from environment."
else
    TOKEN_FILE="$HOME/.openclaw/.gateway-token"
    if [ -f "$TOKEN_FILE" ]; then
        export OPENCLAW_GATEWAY_TOKEN=$(cat "$TOKEN_FILE")
        log "Using gateway token from persisted file."
    else
        export OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
        echo "$OPENCLAW_GATEWAY_TOKEN" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        log "Generated and persisted new gateway token."
    fi
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
        --arg channel "$channel" \
        '. + [{id: $id, channel: $channel}]')
done

log "Discord agents: $(echo "$AGENTS_DATA" | jq -r '[.[].id] | join(", ")') ($(echo "$AGENTS_DATA" | jq length) configured)"

# ---------- Step 4: Build core config with jq ----------

CORE=$(jq -n \
    --arg guild "${DISCORD_GUILD:-}" \
    --arg workspace "$WORKSPACE" \
    --argjson agents "$AGENTS_DATA" \
    '
    {
        gateway: {
            mode: "local",
            auth: { token: { source: "env", provider: "default", id: "OPENCLAW_GATEWAY_TOKEN" } },
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
                            { token: { source: "env", provider: "default", id: ("DISCORD_" + (.id | ascii_upcase) + "_TOKEN") }, groupPolicy: "open" }
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
                match: { channel: "discord", accountId: .id }
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

        hooks: {
            internal: {
                enabled: true,
                entries: {
                    "boot-md": { enabled: true }
                }
            }
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
