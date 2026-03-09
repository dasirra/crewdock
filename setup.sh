#!/usr/bin/env bash
# setup.sh — Bootstrap Forge workspace
set -euo pipefail

WORKSPACE="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}"
FORGE_WORKSPACE="$WORKSPACE/agents/forge"

echo "Setting up Forge workspace at $FORGE_WORKSPACE..."

# Copy forge-db.sh to workspace
mkdir -p "$FORGE_WORKSPACE"
cp agents/forge/forge-db.sh "$FORGE_WORKSPACE/forge-db.sh"
chmod +x "$FORGE_WORKSPACE/forge-db.sh"

# Initialize the SQLite database
"$FORGE_WORKSPACE/forge-db.sh" init

echo "Setup complete."
