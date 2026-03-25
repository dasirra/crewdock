#!/usr/bin/env bash
# install.sh — CrewDock interactive TUI installation wizard
# Entry point: git clone ... && cd crewdock && ./install.sh
# Power user alternative: cp .env.example .env && vim .env && make up

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared helpers
# shellcheck source=installer/lib.sh
source "$SCRIPT_DIR/installer/lib.sh"

# Detect and install gum
# shellcheck source=installer/gum.sh
source "$SCRIPT_DIR/installer/gum.sh"
gum_ensure

# --- Dependency checks ---
check_deps jq curl docker

# --- Load manifest ---
MANIFEST="$SCRIPT_DIR/installer/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  print_error "installer/manifest.json not found. Installation cannot continue."
  exit 1
fi

# --- Detect mode ---
RECONFIG=0
EXISTING_ENV="$SCRIPT_DIR/.env"
if [ -f "$EXISTING_ENV" ]; then
  RECONFIG=1
fi

# --- Screen 1: Welcome ---
echo ""
gum style \
  --border double \
  --border-foreground 212 \
  --padding "1 4" \
  --align center \
  --width 60 \
  "CrewDock" \
  "Installation Wizard"
echo ""

if [ "$RECONFIG" -eq 1 ]; then
  # Detect currently configured agents from .env
  CURRENT_AGENTS=""
  ALL_AGENT_IDS=$(jq -r '.agents[].id' "$MANIFEST")
  for aid in $ALL_AGENT_IDS; do
    AID_UPPER=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
    token_val=$(env_get "DISCORD_${AID_UPPER}_TOKEN")
    if [ -n "$token_val" ]; then
      aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
      CURRENT_AGENTS="$CURRENT_AGENTS $aname"
    fi
  done
  CURRENT_AGENTS="${CURRENT_AGENTS# }"
  print_info "Existing configuration found."
  if [ -n "$CURRENT_AGENTS" ]; then
    print_info "Current agents: $CURRENT_AGENTS"
  fi
  print_info "You can add, remove, or update settings."
  echo ""
fi

# --- Screen 2: Agent Selection ---
print_header "Select Agents"
print_info "Choose which agents to configure:"
echo ""

# Build agent list for gum choose
AGENT_CHOICES=""
ALL_AGENTS=$(jq -r '.agents[] | .id + "|" + .name + " — " + .description' "$MANIFEST")
while IFS= read -r line; do
  AGENT_CHOICES="$AGENT_CHOICES
$(echo "$line" | cut -d'|' -f2)"
done <<EOF
$ALL_AGENTS
EOF
AGENT_CHOICES="${AGENT_CHOICES#$'\n'}"

# In reconfigure mode, we'll just show all options
SELECTED_DISPLAY=$(echo "$AGENT_CHOICES" | gum choose --no-limit --header "Space to select, Enter to confirm:")
if [ -z "$SELECTED_DISPLAY" ]; then
  print_warn "No agents selected. Exiting."
  exit 0
fi

# Map display names back to IDs
SELECTED_AGENT_IDS=""
while IFS= read -r line; do
  if [ -z "$line" ]; then continue; fi
  # Extract just the agent name (before " — ")
  display_name=$(echo "$line" | sed 's/ — .*//')
  agent_id=$(jq -r --arg name "$display_name" '.agents[] | select(.name == $name) | .id' "$MANIFEST")
  if [ -n "$agent_id" ]; then
    SELECTED_AGENT_IDS="$SELECTED_AGENT_IDS $agent_id"
  fi
done <<EOF
$SELECTED_DISPLAY
EOF
SELECTED_AGENT_IDS="${SELECTED_AGENT_IDS# }"

if [ -z "$SELECTED_AGENT_IDS" ]; then
  print_error "Could not map agent selection. Exiting."
  exit 1
fi

echo ""
print_success "Selected: $SELECTED_AGENT_IDS"
echo ""

# --- Helper: agents needing a given integration ---
# agents_for_integration INTEGRATION_KEY — returns "Agent1, Agent2 (optional)" string
agents_for_integration() {
  local intg="$1"
  local result=""
  for aid in $SELECTED_AGENT_IDS; do
    local needs
    needs=$(jq -r --arg id "$aid" --arg intg "$intg" \
      '.agents[] | select(.id == $id) | .integrations[$intg] // "none"' "$MANIFEST")
    if [ "$needs" != "none" ]; then
      local aname
      aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
      local label=""
      [ "$needs" = "optional" ] && label=" (optional)"
      if [ -n "$result" ]; then
        result="$result, $aname$label"
      else
        result="$aname$label"
      fi
    fi
  done
  echo "$result"
}

# --- Screen 3: Git Identity (only for Forge) ---
case " $SELECTED_AGENT_IDS " in
  *" forge "*)
    print_header "Git Identity"
    print_info "Used for commits made by Forge."
    echo ""

    EXISTING_NAME=$(env_get "GIT_AUTHOR_NAME")
    EXISTING_EMAIL=$(env_get "GIT_AUTHOR_EMAIL")

    GIT_NAME=$(gum_input "Full name" "${EXISTING_NAME:-Your Name}")
    if [ -z "$GIT_NAME" ] && [ -n "$EXISTING_NAME" ]; then
      GIT_NAME="$EXISTING_NAME"
    fi

    GIT_EMAIL=$(gum_input "Email address" "${EXISTING_EMAIL:-you@example.com}")
    if [ -z "$GIT_EMAIL" ] && [ -n "$EXISTING_EMAIL" ]; then
      GIT_EMAIL="$EXISTING_EMAIL"
    fi

    env_set "GIT_AUTHOR_NAME" "$GIT_NAME"
    env_set "GIT_AUTHOR_EMAIL" "$GIT_EMAIL"
    echo ""
    ;;
esac

# --- Compute required and optional integrations ---
REQUIRED_INTEGRATIONS=""
OPTIONAL_INTEGRATIONS=""

for agent_id in $SELECTED_AGENT_IDS; do
  agent_required=$(jq -r --arg id "$agent_id" \
    '.agents[] | select(.id == $id) | .integrations | to_entries[] | select(.value == "required") | .key' \
    "$MANIFEST")
  agent_optional=$(jq -r --arg id "$agent_id" \
    '.agents[] | select(.id == $id) | .integrations | to_entries[] | select(.value == "optional") | .key' \
    "$MANIFEST")

  for intg in $agent_required; do
    # Add if not already in required
    case " $REQUIRED_INTEGRATIONS " in
      *" $intg "*) ;;
      *) REQUIRED_INTEGRATIONS="$REQUIRED_INTEGRATIONS $intg" ;;
    esac
    # Remove from optional if it was there
    OPTIONAL_INTEGRATIONS=$(echo "$OPTIONAL_INTEGRATIONS" | tr ' ' '\n' | grep -v "^${intg}$" | tr '\n' ' ')
  done

  for intg in $agent_optional; do
    # Add to optional only if not already required
    case " $REQUIRED_INTEGRATIONS " in
      *" $intg "*) ;;
      *)
        case " $OPTIONAL_INTEGRATIONS " in
          *" $intg "*) ;;
          *) OPTIONAL_INTEGRATIONS="$OPTIONAL_INTEGRATIONS $intg" ;;
        esac
        ;;
    esac
  done
done

REQUIRED_INTEGRATIONS="${REQUIRED_INTEGRATIONS# }"
OPTIONAL_INTEGRATIONS="${OPTIONAL_INTEGRATIONS# }"

# --- Track integration status for summary ---
# Status values: validated, unverified, skipped
INTG_STATUS_discord=""
INTG_STATUS_github=""
INTG_STATUS_claude=""
INTG_STATUS_gws=""
INTG_STATUS_xurl=""
INTG_STATUS_linear=""

# --- Run integration flows ---
# Order: discord > github > claude > gws > xurl

# Source all modules
# shellcheck source=installer/discord.sh
source "$SCRIPT_DIR/installer/discord.sh"
# shellcheck source=installer/github.sh
source "$SCRIPT_DIR/installer/github.sh"
# shellcheck source=installer/claude.sh
source "$SCRIPT_DIR/installer/claude.sh"
# shellcheck source=installer/gws.sh
source "$SCRIPT_DIR/installer/gws.sh"
# shellcheck source=installer/xurl.sh
source "$SCRIPT_DIR/installer/xurl.sh"
# shellcheck source=installer/linear.sh
source "$SCRIPT_DIR/installer/linear.sh"

# Discord (shared + per-agent)
case " $REQUIRED_INTEGRATIONS $OPTIONAL_INTEGRATIONS " in
  *" discord "*)
    print_header "Discord Setup"
    print_info "Agents: $(agents_for_integration discord)"
    echo ""
    run_discord_shared
    for agent_id in $SELECTED_AGENT_IDS; do
      # Check if this agent needs discord
      needs_discord=$(jq -r --arg id "$agent_id" \
        '.agents[] | select(.id == $id) | .integrations.discord // "none"' "$MANIFEST")
      if [ "$needs_discord" != "none" ]; then
        aname=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        run_discord_agent "$agent_id" "$aname"
      fi
    done
    INTG_STATUS_discord="${DISCORD_SETUP_STATUS:-unverified}"
    ;;
esac

# GitHub
case " $REQUIRED_INTEGRATIONS " in
  *" github "*)
    print_header "GitHub Setup"
    print_info "Agents: $(agents_for_integration github)"
    echo ""
    run_github
    INTG_STATUS_github="${GITHUB_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" github "*)
        if gum_confirm "Set up GitHub integration? (optional for $(agents_for_integration github))"; then
          print_header "GitHub Setup"
          print_info "Agents: $(agents_for_integration github)"
          echo ""
          run_github
          INTG_STATUS_github="${GITHUB_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_github="skipped"
        fi
        ;;
    esac
    ;;
esac

# Claude
case " $REQUIRED_INTEGRATIONS " in
  *" claude "*)
    print_header "Claude Setup"
    print_info "Agents: $(agents_for_integration claude)"
    echo ""
    run_claude
    INTG_STATUS_claude="${CLAUDE_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" claude "*)
        if gum_confirm "Set up Claude integration? (optional for $(agents_for_integration claude))"; then
          print_header "Claude Setup"
          print_info "Agents: $(agents_for_integration claude)"
          echo ""
          run_claude
          INTG_STATUS_claude="${CLAUDE_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_claude="skipped"
        fi
        ;;
    esac
    ;;
esac

# GWS
case " $REQUIRED_INTEGRATIONS " in
  *" gws "*)
    print_header "Google Workspace Setup"
    print_info "Agents: $(agents_for_integration gws)"
    echo ""
    run_gws
    INTG_STATUS_gws="${GWS_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" gws "*)
        if gum_confirm "Set up Google Workspace integration? (optional for $(agents_for_integration gws))"; then
          print_header "Google Workspace Setup"
          print_info "Agents: $(agents_for_integration gws)"
          echo ""
          run_gws
          INTG_STATUS_gws="${GWS_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_gws="skipped"
        fi
        ;;
    esac
    ;;
esac

# X/Twitter
case " $REQUIRED_INTEGRATIONS " in
  *" xurl "*)
    print_header "X/Twitter Setup"
    print_info "Agents: $(agents_for_integration xurl)"
    echo ""
    run_xurl
    INTG_STATUS_xurl="${XURL_SETUP_STATUS:-unverified}"
    ;;
  *)
    case " $OPTIONAL_INTEGRATIONS " in
      *" xurl "*)
        XURL_AGENTS=$(agents_for_integration xurl)
        if gum_confirm "$XURL_AGENTS can optionally use X/Twitter for monitoring. Set it up?"; then
          print_header "X/Twitter Setup"
          print_info "Agents: $XURL_AGENTS"
          echo ""
          run_xurl
          INTG_STATUS_xurl="${XURL_SETUP_STATUS:-unverified}"
        else
          INTG_STATUS_xurl="skipped"
        fi
        ;;
    esac
    ;;
esac

# Linear
case " $OPTIONAL_INTEGRATIONS " in
  *" linear "*)
    FORGE_AGENTS=$(agents_for_integration linear)
    if gum_confirm "Set up Linear integration? (optional for $FORGE_AGENTS)"; then
      print_header "Linear Setup"
      print_info "Agents: $FORGE_AGENTS"
      echo ""
      run_linear
      INTG_STATUS_linear="${LINEAR_SETUP_STATUS:-unverified}"
    else
      INTG_STATUS_linear="skipped"
    fi
    ;;
esac

# Set OPENCLAW_GATEWAY_TOKEN as empty (auto-generated on boot)
env_set "OPENCLAW_GATEWAY_TOKEN" ""

# --- Create runtime directories ---
mkdir -p \
  "$SCRIPT_DIR/home/.openclaw/workspace" \
  "$SCRIPT_DIR/home/.claude" \
  "$SCRIPT_DIR/home/.config/gh" \
  "$SCRIPT_DIR/home/.config/gws"
[ -f "$SCRIPT_DIR/home/.xurl" ] || touch "$SCRIPT_DIR/home/.xurl"

# --- Summary Screen ---
echo ""
print_header "Setup Complete"
echo ""

gum style --foreground 212 "Selected agents:"
for agent_id in $SELECTED_AGENT_IDS; do
  aname=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
  echo "  ✓ $aname"
done
echo ""

gum style --foreground 212 "Integrations:"

_status_icon() {
  case "$1" in
    validated) echo "✓" ;;
    unverified) echo "⚠" ;;
    skipped) echo "—" ;;
    *) echo "—" ;;
  esac
}

# Verifiable integrations: show validation status
[ -n "$INTG_STATUS_discord" ] && echo "  $(_status_icon "$INTG_STATUS_discord") Discord ($INTG_STATUS_discord)"
[ -n "$INTG_STATUS_github" ]  && echo "  $(_status_icon "$INTG_STATUS_github") GitHub ($INTG_STATUS_github)"
[ -n "$INTG_STATUS_xurl" ]    && echo "  $(_status_icon "$INTG_STATUS_xurl") X/Twitter ($INTG_STATUS_xurl)"
[ -n "$INTG_STATUS_linear" ]  && echo "  $(_status_icon "$INTG_STATUS_linear") Linear ($INTG_STATUS_linear)"
# Non-verifiable integrations: show configured/skipped only
if [ -n "$INTG_STATUS_claude" ]; then
  if [ "$INTG_STATUS_claude" = "skipped" ]; then
    echo "  — Claude (skipped)"
  else
    echo "  ✓ Claude (configured, verified on boot)"
  fi
fi
if [ -n "$INTG_STATUS_gws" ]; then
  if [ "$INTG_STATUS_gws" = "skipped" ]; then
    echo "  — Google Workspace (skipped)"
  elif [ "$INTG_STATUS_gws" = "validated" ]; then
    echo "  ✓ Google Workspace (validated)"
  else
    echo "  ✓ Google Workspace (configured)"
  fi
fi

echo ""

gum style --foreground 3 "Next step: LLM Provider"
echo ""
print_info "Agents need at least one LLM provider to work."
print_info "After the container is running, authenticate a provider with:"
echo ""
print_info "  make auth"
echo ""

if gum_confirm "Start OpenClaw now? (make up)"; then
  print_info "Running make up..."
  make -C "$SCRIPT_DIR" up
  echo ""
  if gum_confirm "Authenticate an LLM provider now? (make auth)"; then
    make -C "$SCRIPT_DIR" auth
  else
    print_info "Run 'make auth' when ready to authenticate a provider."
  fi
else
  print_info "Run 'make up' when ready, then 'make auth' to authenticate a provider."
fi
