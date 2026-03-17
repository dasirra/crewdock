#!/usr/bin/env bash
# 03-agents.sh -- Install new agents or sync definition files for existing ones
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh
#
# Agent registration and heartbeat config are handled by 01-config.sh.
# This script only manages workspace files (templates, configs, databases).

AGENT_TEMPLATES="/opt/openclaw-agents"
WORKSPACE="$HOME/.openclaw/workspace"

# --- Overlord: install and sync as main agent ---
# main is the gateway's pre-registered default agent; we skip `agents add` (would fail).
OVERLORD_TEMPLATE="$AGENT_TEMPLATES/overlord"
MAIN_WORKSPACE="$WORKSPACE/agents/main"
OVERLORD_SENTINEL="$MAIN_WORKSPACE/SOUL.md"

if [ -d "$OVERLORD_TEMPLATE" ]; then
    if [ ! -f "$OVERLORD_SENTINEL" ]; then
        # --- New install ---
        log "Installing Overlord as main agent..."
        mkdir -p "$MAIN_WORKSPACE"
        cp -r "$OVERLORD_TEMPLATE/"* "$MAIN_WORKSPACE/"

        # Rename .example.* files to their real names
        for example in "$MAIN_WORKSPACE"/*.example.*; do
            [ -f "$example" ] || continue
            real="${example/.example/}"
            mv "$example" "$real"
        done

        # Set identity name via CLI
        MAIN_INDEX=$(node dist/index.js config get agents.list 2>/dev/null \
            | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.findIndex(a=>a.id==='main'))" 2>/dev/null)
        if [ -n "$MAIN_INDEX" ] && [ "$MAIN_INDEX" != "-1" ]; then
            log "Setting main agent identity to Overlord (index: $MAIN_INDEX)..."
            node dist/index.js config set "agents.list[$MAIN_INDEX].identity.name" '"Overlord"' --json
        else
            log "WARNING: could not find main agent index, skipping identity config"
        fi

        log "Installed Overlord."
    else
        # --- Sync: update definition files, respecting .protected ---
        log "Syncing Overlord (main agent)..."

        protected_patterns=()
        if [ -f "$OVERLORD_TEMPLATE/.protected" ]; then
            while IFS= read -r pattern || [ -n "$pattern" ]; do
                [[ "$pattern" =~ ^[[:space:]]*$ || "$pattern" =~ ^# ]] && continue
                protected_patterns+=("$pattern")
            done < "$OVERLORD_TEMPLATE/.protected"
        fi

        for src_file in "$OVERLORD_TEMPLATE"/*; do
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

            cp "$src_file" "$MAIN_WORKSPACE/$filename"
            log "  Synced: $filename"
        done

        log "Synced Overlord."
    fi
fi

for agent_dir in "$AGENT_TEMPLATES"/*/; do
    [ -d "$agent_dir" ] || continue
    agent_name=$(basename "$agent_dir")
    # overlord is handled above as the main agent — skip here
    [ "$agent_name" = "overlord" ] && continue
    target="$WORKSPACE/agents/$agent_name"

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
