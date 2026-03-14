#!/usr/bin/env bash
# 03-acpx.sh — Install acpx plugin and enable ACP sessions with threading
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

# Install acpx plugin if not already present
if node dist/index.js config get plugins.entries.acpx.enabled 2>/dev/null | grep -q "true"; then
    log "acpx plugin already enabled, skipping install."
else
    log "Installing acpx plugin..."
    node dist/index.js plugins install acpx
    node dist/index.js config set plugins.entries.acpx.enabled true
fi

# Enable ACP with acpx backend
if node dist/index.js config get acp.enabled 2>/dev/null | grep -q "true"; then
    log "ACP already enabled, skipping."
else
    log "Enabling ACP sessions (backend: acpx)..."
    node dist/index.js config set acp.enabled true
    node dist/index.js config set acp.backend acpx
fi

# Enable thread bindings for forge only
log "Configuring thread bindings for forge..."
node dist/index.js config set session.threadBindings.enabled true
node dist/index.js config set channels.discord.accounts.forge.threadBindings.enabled true
node dist/index.js config set channels.discord.accounts.forge.threadBindings.spawnAcpSessions true

log "OK"
