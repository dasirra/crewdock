#!/usr/bin/env bash
# 03-agents.sh -- Install new agents or sync definition files for existing ones
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
#
# Agent registration and heartbeat config are handled by 01-config.sh.
# This script only manages workspace files (templates, configs, databases).

AGENT_TEMPLATES="/opt/openclaw-agents"
WORKSPACE="$HOME/.openclaw/workspace"

for agent_dir in "$AGENT_TEMPLATES"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name=$(basename "$agent_dir")

    # Overlord template installs into the pre-registered "main" agent workspace
    if [ "$agent_name" = "overlord" ]; then
        target="$WORKSPACE/agents/main"
    else
        target="$WORKSPACE/agents/$agent_name"
    fi

    if [ ! -d "$target" ]; then
        # --- New agent: install workspace files ---
        log "Installing agent '$agent_name'..."

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

            cp -r "$src_file" "$target/$filename"
            log "  Synced: $filename"
        done

        log "Synced $agent_name."
    fi
done

# Shared USER.md: install once, symlink into each agent
if [ -f "$AGENT_TEMPLATES/USER.example.md" ] && [ ! -f "$WORKSPACE/agents/USER.md" ]; then
    cp "$AGENT_TEMPLATES/USER.example.md" "$WORKSPACE/agents/USER.md"
    log "Installed shared USER.md (edit to configure your voice profile)."
fi
if [ -f "$WORKSPACE/agents/USER.md" ]; then
    for agent_dir in "$WORKSPACE"/agents/*/; do
        [ -d "$agent_dir" ] || continue
        link="$agent_dir/USER.md"
        [ -L "$link" ] && continue
        [ -f "$link" ] && rm "$link"  # replace stale copy with symlink
        ln -s ../USER.md "$link"
        log "Linked USER.md -> $(basename "$agent_dir")/"
    done
fi

# Initialize agent databases (idempotent: CREATE TABLE IF NOT EXISTS)
for db_script in "$WORKSPACE"/agents/*/*-db.sh; do
    [ -f "$db_script" ] || continue
    agent_name=$(basename "$(dirname "$db_script")")
    chmod +x "$db_script"
    "$db_script" init
    log "$agent_name database initialized."
done
