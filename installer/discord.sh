#!/usr/bin/env bash
# installer/discord.sh — Discord bot setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: DISCORD_SETUP_STATUS (validated|unverified|skipped)

DISCORD_SETUP_STATUS="skipped"

# run_discord_shared — collect shared Discord settings (guild ID)
run_discord_shared() {
  print_info "Discord Developer Mode must be enabled to copy IDs."
  print_info "Settings > Advanced > Developer Mode = ON"
  echo ""

  local existing_guild
  existing_guild=$(env_get "DISCORD_GUILD")

  local guild_id
  if [ -n "$existing_guild" ]; then
    print_info "Current guild ID: $(mask_token "$existing_guild")"
    guild_id=$(gum_input "Server (Guild) ID" "Press Enter to keep current")
    if [ -z "$guild_id" ]; then
      guild_id="$existing_guild"
    fi
  else
    guild_id=$(gum_input "Server (Guild) ID" "Right-click your server icon > Copy Server ID")
  fi

  if [ -n "$guild_id" ]; then
    env_set "DISCORD_GUILD" "$guild_id"
    DISCORD_SETUP_STATUS="unverified"
  fi
}

# run_discord_agent AGENT_ID AGENT_NAME — per-agent Discord bot setup
run_discord_agent() {
  local agent_id="$1"
  local agent_name="$2"
  local agent_upper
  agent_upper=$(echo "$agent_id" | tr '[:lower:]' '[:upper:]')

  echo ""
  gum style --bold "Configure Discord bot for $agent_name"
  echo ""
  print_info "Steps to create a Discord bot:"
  print_info "  1. Go to: https://discord.com/developers/applications"
  print_info "  2. Click 'New Application', give it a name (e.g. $agent_name)"
  print_info "  3. Go to 'Bot' in the left sidebar"
  print_info "  4. Click 'Add Bot' (or 'Reset Token' if one exists)"
  print_info "  5. Copy the token"
  print_info "  6. Enable 'Message Content Intent' under Privileged Gateway Intents"
  print_info "  7. Go to 'OAuth2 > URL Generator', select 'bot' scope + 'Send Messages' permission"
  print_info "  8. Open the generated URL to invite the bot to your server"
  echo ""

  local existing_token
  existing_token=$(env_get "DISCORD_${agent_upper}_TOKEN")

  # Collect bot token
  local token
  local token_status="unverified"
  local bot_username=""

  while true; do
    if [ -n "$existing_token" ]; then
      print_info "Current token: $(mask_token "$existing_token")"
      token=$(gum_input_password "Bot token (Enter to keep current)")
      if [ -z "$token" ]; then
        token="$existing_token"
        token_status="unverified"
        break
      fi
    else
      token=$(gum_input_password "Bot token")
    fi

    if [ -z "$token" ]; then
      print_warn "No token provided."
      break
    fi

    # Validate token
    print_info "Validating token..."
    local response http_code
    response=$(curl -sf -w "\n%{http_code}" \
      -H "Authorization: Bot $token" \
      "https://discord.com/api/v10/users/@me" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$response" | tail -1)
    local body
    body=$(echo "$response" | head -n -1)

    if [ "$http_code" = "200" ]; then
      bot_username=$(echo "$body" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null || \
                    echo "$body" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
      print_success "Token valid! Bot username: $bot_username"
      token_status="validated"
      break
    else
      print_error "Token validation failed (HTTP $http_code)"
      local choice
      choice=$(printf 'Retry\nSave anyway\nSkip' | gum choose --header "What would you like to do?")
      case "$choice" in
        "Retry") continue ;;
        "Save anyway") token_status="unverified"; break ;;
        "Skip") token=""; token_status="skipped"; break ;;
      esac
    fi
  done

  if [ "$token_status" = "skipped" ] || [ -z "$token" ]; then
    print_warn "Skipping Discord setup for $agent_name"
    env_blank "DISCORD_${agent_upper}_TOKEN"
    env_blank "DISCORD_${agent_upper}_CHANNEL"
    return 0
  fi

  env_set "DISCORD_${agent_upper}_TOKEN" "$token"

  # Collect channel ID
  local existing_channel
  existing_channel=$(env_get "DISCORD_${agent_upper}_CHANNEL")
  local channel_id

  if [ -n "$existing_channel" ]; then
    print_info "Current channel ID: $(mask_token "$existing_channel")"
    channel_id=$(gum_input "Channel ID (Enter to keep current)" "Right-click channel > Copy Channel ID")
    if [ -z "$channel_id" ]; then
      channel_id="$existing_channel"
    fi
  else
    channel_id=$(gum_input "Channel ID" "Right-click channel > Copy Channel ID")
  fi

  if [ -n "$channel_id" ]; then
    # Validate channel
    print_info "Validating channel access..."
    local ch_response ch_code
    ch_response=$(curl -sf -w "\n%{http_code}" \
      -H "Authorization: Bot $token" \
      "https://discord.com/api/v10/channels/$channel_id" 2>/dev/null || echo -e "\n000")
    ch_code=$(echo "$ch_response" | tail -1)

    if [ "$ch_code" = "200" ]; then
      print_success "Channel access confirmed."
      if [ "$token_status" = "validated" ]; then
        DISCORD_SETUP_STATUS="validated"
      else
        DISCORD_SETUP_STATUS="unverified"
      fi
    else
      print_warn "Could not verify channel access (HTTP $ch_code)"
      local ch_choice
      ch_choice=$(printf 'Save anyway\nSkip channel' | gum choose --header "What would you like to do?")
      case "$ch_choice" in
        "Skip channel") channel_id="$existing_channel" ;;
      esac
      DISCORD_SETUP_STATUS="unverified"
    fi
  fi

  env_set "DISCORD_${agent_upper}_CHANNEL" "$channel_id"
  print_success "$agent_name Discord bot configured."
}
