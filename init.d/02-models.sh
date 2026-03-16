#!/usr/bin/env bash
# 02-models.sh — LLM provider auth (Anthropic + optional OpenAI Codex)
# SCRIPT_NAME and log() are provided by docker-entrypoint.sh

# --- Anthropic (required) ---
if [ -z "${ANTHROPIC_OAUTH_TOKEN:-}" ]; then
    log "ERROR: ANTHROPIC_OAUTH_TOKEN is not set."
    return 1
fi

if node dist/index.js models status --probe 2>/dev/null | grep -qi "anthropic"; then
    log "Anthropic provider already configured, skipping."
else
    log "Configuring Anthropic provider..."
    echo "$ANTHROPIC_OAUTH_TOKEN" | node dist/index.js models auth paste-token --provider anthropic
    log "Anthropic OK"
fi

# --- OpenAI Codex (optional, requires prior 'make openai-codex') ---
if node dist/index.js models status --probe 2>/dev/null | grep -qi "openai-codex"; then
    log "OpenAI Codex provider detected, setting as default model..."
    node dist/index.js config set agents.defaults.model.primary openai-codex/gpt-5.4
    node dist/index.js config set agents.defaults.model.fallbacks '["anthropic/claude-sonnet-4-6"]' --json
    log "OpenAI Codex OK (fallback: anthropic/claude-sonnet-4-6)"
else
    log "OpenAI Codex not configured. Run 'make openai-codex' to set up (requires browser)."
fi
