#!/usr/bin/env bash
# 04-agents.sh — Install new agents or sync definition files for existing ones
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

AGENT_TEMPLATES="/opt/openclaw-agents"
WORKSPACE="$HOME/.openclaw/workspace"

for agent_dir in "$AGENT_TEMPLATES"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name=$(basename "$agent_dir")
    target="$WORKSPACE/agents/$agent_name"

    if [ ! -d "$target" ]; then
        # --- New agent: full install ---
        log "Installing agent '$agent_name'..."

        if ! node dist/index.js agents add "$agent_name" --workspace "$target" --non-interactive 2>/dev/null; then
            log "WARNING: 'agents add' failed for $agent_name (may already be registered). Continuing."
        fi

        mkdir -p "$target"
        cp -r "$agent_dir"* "$target/"

        # Rename .example.* files to their real names
        for example in "$target"/*.example.*; do
            [ -f "$example" ] || continue
            real="${example/.example/}"
            mv "$example" "$real"
        done

        # Clear projects list (user adds repos via Discord)
        if [ -f "$target/config.json" ]; then
            jq '.projects = []' "$target/config.json" > "$target/config.json.tmp" \
                && mv "$target/config.json.tmp" "$target/config.json"
        fi

        # Configure heartbeat target if agent has a Discord channel
        UPPER=$(echo "$agent_name" | tr '[:lower:]' '[:upper:]')
        CHANNEL_VAR="DISCORD_${UPPER}_CHANNEL"
        CHANNEL="${!CHANNEL_VAR:-}"
        if [ -n "$CHANNEL" ]; then
            AGENT_INDEX=$(node dist/index.js config get agents.list 2>/dev/null \
                | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.findIndex(a=>a.id==='$agent_name'))" 2>/dev/null)
            if [ -n "$AGENT_INDEX" ] && [ "$AGENT_INDEX" != "-1" ]; then
                log "Configuring heartbeat for $agent_name (index: $AGENT_INDEX, channel: $CHANNEL)..."
                node dist/index.js config set "agents.list[$AGENT_INDEX].heartbeat.every" '"0m"' --json
                node dist/index.js config set "agents.list[$AGENT_INDEX].heartbeat.target" '"discord"' --json
                node dist/index.js config set "agents.list[$AGENT_INDEX].heartbeat.to" "\"channel:$CHANNEL\"" --json
                node dist/index.js config set "agents.list[$AGENT_INDEX].heartbeat.accountId" "\"$agent_name\"" --json
                node dist/index.js config set "agents.list[$AGENT_INDEX].heartbeat.directPolicy" '"block"' --json
            else
                log "WARNING: could not find agent index for $agent_name, skipping heartbeat config"
            fi
        fi

        log "Installed $agent_name."
    else
        # --- Existing agent: sync definition files ---
        log "Syncing agent '$agent_name'..."

        # Cache protected patterns (read .protected file once, not per-file)
        protected_patterns=()
        if [ -f "$agent_dir/.protected" ]; then
            while IFS= read -r pattern || [ -n "$pattern" ]; do
                [[ "$pattern" =~ ^[[:space:]]*$ || "$pattern" =~ ^# ]] && continue
                protected_patterns+=("$pattern")
            done < "$agent_dir/.protected"
        fi

        for src_file in "$agent_dir"*; do
            [ -e "$src_file" ] || continue
            filename=$(basename "$src_file")

            skip=false
            for pattern in "${protected_patterns[@]}"; do
                # shellcheck disable=SC2254
                [[ "$filename" == $pattern ]] && skip=true && break
            done
            if [ "$skip" = true ]; then
                log "  Protected: $filename"
                continue
            fi

            cp "$src_file" "$target/$filename"
            log "  Synced: $filename"
        done

        log "Synced $agent_name."
    fi
done

# Initialize agent databases (idempotent: CREATE TABLE IF NOT EXISTS)
for db_script in "$WORKSPACE"/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    chmod +x "$db_script"
    "$db_script" init
    log "$agent_name database initialized."
done
