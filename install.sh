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

# --- Helper: integration status ---
# _integration_status AGENT_ID INTEGRATION_KEY — returns "configured" or "not configured"
_integration_status() {
  local agent_id="$1"
  local intg="$2"
  local agent_upper
  agent_upper=$(echo "$agent_id" | tr '[:lower:]' '[:upper:]')
  case "$intg" in
    discord)
      local token
      token=$(env_get "DISCORD_${agent_upper}_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    github)
      local token
      token=$(env_get "GH_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    claude)
      local token
      token=$(env_get "CLAUDE_CODE_OAUTH_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    gws)
      [ -f "$SCRIPT_DIR/home/.config/gws/credentials.json" ] && echo "configured" || echo "not configured"
      ;;
    xurl)
      local token
      token=$(env_get "X_BEARER_TOKEN")
      [ -n "$token" ] && echo "configured" || echo "not configured"
      ;;
    *)
      echo "not configured"
      ;;
  esac
}

# --- Helper: git identity prompts ---
_run_git_identity() {
  print_header "Git Identity"
  print_info "Used for commits made by Forge."
  echo ""
  local existing_name existing_email git_name git_email
  existing_name=$(env_get "GIT_AUTHOR_NAME")
  existing_email=$(env_get "GIT_AUTHOR_EMAIL")
  git_name=$(gum_input "Full name" "${existing_name:-Your Name}")
  if [ -z "$git_name" ] && [ -n "$existing_name" ]; then
    git_name="$existing_name"
  fi
  git_email=$(gum_input "Email address" "${existing_email:-you@example.com}")
  if [ -z "$git_email" ] && [ -n "$existing_email" ]; then
    git_email="$existing_email"
  fi
  env_set "GIT_AUTHOR_NAME" "$git_name"
  env_set "GIT_AUTHOR_EMAIL" "$git_email"
  echo ""
}

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

  # Source all integration modules for reconfigure mode
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

  # --- Reconfigure: agent submenu ---
  _run_agent_submenu() {
    local agent_id="$1"
    local agent_name="$2"
    while true; do
      local menu_items=""
      # Git Identity first for Forge
      if [ "$agent_id" = "forge" ]; then
        local git_name
        git_name=$(env_get "GIT_AUTHOR_NAME")
        local git_status
        [ -n "$git_name" ] && git_status="configured" || git_status="not configured"
        menu_items="${menu_items}Git Identity (${git_status})\n"
      fi
      # Integrations from manifest
      local intg_ids
      intg_ids=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .integrations | keys[]' "$MANIFEST")
      for intg in $intg_ids; do
        local intg_label intg_status
        intg_label=$(jq -r --arg intg "$intg" '.integrations[$intg].label' "$MANIFEST")
        intg_status=$(_integration_status "$agent_id" "$intg")
        menu_items="${menu_items}${intg_label} (${intg_status})\n"
      done
      menu_items="${menu_items}Back"

      print_header "$agent_name"
      local choice
      choice=$(printf "%b" "$menu_items" | gum choose --header "")
      [ -z "$choice" ] && break
      [ "$choice" = "Back" ] && break

      # Strip " (status)" suffix to get the label
      local label
      label=$(echo "$choice" | sed 's/ ([^)]*)$//')
      case "$label" in
        "Git Identity")
          _run_git_identity
          ;;
        "Discord")
          run_discord_shared
          run_discord_agent "$agent_id" "$agent_name"
          ;;
        "GitHub")
          run_github
          ;;
        "Claude Code")
          run_claude
          ;;
        "Google Workspace")
          run_gws
          ;;
        "X/Twitter")
          run_xurl
          ;;
      esac
    done
  }

  # --- Reconfigure: top-level menu ---
  run_reconfigure_menu() {
    while true; do
      local menu_items=""
      local all_agent_ids
      all_agent_ids=$(jq -r '.agents[].id' "$MANIFEST")
      for aid in $all_agent_ids; do
        local aid_upper aname token_val
        aid_upper=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
        aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        token_val=$(env_get "DISCORD_${aid_upper}_TOKEN")
        if [ -n "$token_val" ]; then
          menu_items="${menu_items}${aname}\n"
        else
          menu_items="${menu_items}${aname} (not installed)\n"
        fi
      done
      menu_items="${menu_items}Done"

      local choice
      choice=$(printf "%b" "$menu_items" | gum choose --header "What would you like to configure?")
      [ -z "$choice" ] && break
      [ "$choice" = "Done" ] && break

      # Find agent id for chosen name
      local chosen_id="" chosen_name=""
      for aid in $all_agent_ids; do
        local aname
        aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        if [ "$choice" = "$aname" ] || [ "$choice" = "$aname (not installed)" ]; then
          chosen_id="$aid"
          chosen_name="$aname"
          break
        fi
      done
      [ -z "$chosen_id" ] && continue

      # Check if installed
      local aid_upper token_val
      aid_upper=$(echo "$chosen_id" | tr '[:lower:]' '[:upper:]')
      token_val=$(env_get "DISCORD_${aid_upper}_TOKEN")
      if [ -z "$token_val" ]; then
        run_full_agent_setup "$chosen_id"
      else
        _run_agent_submenu "$chosen_id" "$chosen_name"
      fi
    done
  }

  # --- Reconfigure: full agent setup (for not-installed agents) ---
  run_full_agent_setup() {
    local agent_id="$1"
    local agent_name
    agent_name=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .name' "$MANIFEST")

    print_header "Setting up $agent_name"

    # Git Identity for Forge
    if [ "$agent_id" = "forge" ]; then
      _run_git_identity
    fi

    # Run each integration
    local intg_ids
    intg_ids=$(jq -r --arg id "$agent_id" '.agents[] | select(.id == $id) | .integrations | keys[]' "$MANIFEST")
    for intg in $intg_ids; do
      case "$intg" in
        discord)
          print_header "Discord Setup"
          run_discord_shared
          run_discord_agent "$agent_id" "$agent_name"
          ;;
        github)
          print_header "GitHub Setup"
          run_github
          ;;
        claude)
          print_header "Claude Setup"
          run_claude
          ;;
        gws)
          print_header "Google Workspace Setup"
          run_gws
          ;;
        xurl)
          print_header "X/Twitter Setup"
          run_xurl
          ;;
      esac
    done
  }

  # --- Reconfigure: summary ---
  run_reconfigure_summary() {
    # Create runtime directories
    mkdir -p \
      "$SCRIPT_DIR/home/.openclaw/workspace" \
      "$SCRIPT_DIR/home/.claude" \
      "$SCRIPT_DIR/home/.config/gh" \
      "$SCRIPT_DIR/home/.config/gws"
    [ -f "$SCRIPT_DIR/home/.xurl" ] || touch "$SCRIPT_DIR/home/.xurl"

    echo ""
    print_header "Configuration Updated"
    echo ""

    gum style --foreground 212 "Configured agents:"
    local all_agent_ids
    all_agent_ids=$(jq -r '.agents[].id' "$MANIFEST")
    for aid in $all_agent_ids; do
      local aid_upper token aname
      aid_upper=$(echo "$aid" | tr '[:lower:]' '[:upper:]')
      token=$(env_get "DISCORD_${aid_upper}_TOKEN")
      if [ -n "$token" ]; then
        aname=$(jq -r --arg id "$aid" '.agents[] | select(.id == $id) | .name' "$MANIFEST")
        echo "  ✓ $aname"
      fi
    done
    echo ""

    gum style --foreground 212 "Integrations:"
    local gh_token claude_token x_token
    gh_token=$(env_get "GH_TOKEN")
    [ -n "$gh_token" ] && echo "  ✓ GitHub (configured)" || true
    claude_token=$(env_get "CLAUDE_CODE_OAUTH_TOKEN")
    [ -n "$claude_token" ] && echo "  ✓ Claude Code (configured)" || true
    [ -f "$SCRIPT_DIR/home/.config/gws/credentials.json" ] && echo "  ✓ Google Workspace (configured)" || true
    x_token=$(env_get "X_BEARER_TOKEN")
    [ -n "$x_token" ] && echo "  ✓ X/Twitter (configured)" || true
    echo ""

    if gum_confirm "Restart OpenClaw now? (make restart)"; then
      print_info "Running make restart..."
      make -C "$SCRIPT_DIR" restart
    else
      print_info "Run 'make restart' to apply changes."
    fi
  }

  run_reconfigure_menu
  run_reconfigure_summary
  exit 0
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
    _run_git_identity
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
