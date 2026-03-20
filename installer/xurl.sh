#!/usr/bin/env bash
# installer/xurl.sh — X/Twitter API setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: XURL_SETUP_STATUS (validated|unverified|skipped)

XURL_SETUP_STATUS="skipped"

# run_xurl — collect and validate X/Twitter API credentials
run_xurl() {
  print_info "You need an X/Twitter API Bearer Token."
  print_info "Get one at: https://developer.x.com/en/portal/dashboard"
  echo ""
  print_info "  1. Go to the X Developer Portal link above"
  print_info "  2. Create a project and app (or use an existing one)"
  print_info "  3. Go to your app's 'Keys and tokens' section"
  print_info "  4. Copy the 'Bearer Token'"
  echo ""

  local existing_bearer
  existing_bearer=$(env_get "X_BEARER_TOKEN")

  local bearer_token bearer_status="unverified"

  while true; do
    if [ -n "$existing_bearer" ]; then
      print_info "Current bearer token: $(mask_token "$existing_bearer")"
      bearer_token=$(gum_input_password "Bearer token (Enter to keep current)")
      if [ -z "$bearer_token" ]; then
        bearer_token="$existing_bearer"
        bearer_status="unverified"
        break
      fi
    else
      bearer_token=$(gum_input_password "Bearer Token")
    fi

    if [ -z "$bearer_token" ]; then
      print_warn "No token provided."
      local choice
      choice=$(printf 'Retry\nSkip' | gum choose --header "What would you like to do?")
      case "$choice" in
        "Retry") continue ;;
        "Skip") XURL_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi

    # Validate bearer token
    print_info "Validating bearer token..."
    local response http_code body_file
    body_file=$(mktemp)

    http_code=$(curl -sf \
      -H "Authorization: Bearer $bearer_token" \
      -o "$body_file" \
      -w "%{http_code}" \
      "https://api.x.com/2/users/me" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      local x_username
      x_username=$(python3 -c "import sys,json; d=json.load(open('$body_file')); print(d.get('data',{}).get('username',''))" 2>/dev/null || \
                   grep -o '"username":"[^"]*"' "$body_file" | cut -d'"' -f4 || echo "")
      rm -f "$body_file"
      print_success "Token valid! X username: $x_username"
      bearer_status="validated"
      break
    else
      rm -f "$body_file"
      print_error "Token validation failed (HTTP $http_code)"
      local fail_choice
      fail_choice=$(printf 'Retry\nSave anyway\nSkip' | gum choose --header "What would you like to do?")
      case "$fail_choice" in
        "Retry") continue ;;
        "Save anyway") bearer_status="unverified"; break ;;
        "Skip") XURL_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi
  done

  env_set "X_BEARER_TOKEN" "$bearer_token"

  # Optional: client ID and secret
  echo ""
  if gum_confirm "Add optional X API client credentials? (for write access)"; then
    local existing_client_id existing_client_secret
    existing_client_id=$(env_get "X_CLIENT_ID")
    existing_client_secret=$(env_get "X_CLIENT_SECRET")

    if [ -n "$existing_client_id" ]; then
      print_info "Current client ID: $(mask_token "$existing_client_id")"
      local new_client_id
      new_client_id=$(gum_input "Client ID (Enter to keep current)" "")
      if [ -n "$new_client_id" ]; then
        env_set "X_CLIENT_ID" "$new_client_id"
      fi
    else
      local client_id
      client_id=$(gum_input "Client ID" "From X Developer Portal app settings")
      if [ -n "$client_id" ]; then
        env_set "X_CLIENT_ID" "$client_id"
      fi
    fi

    if [ -n "$existing_client_secret" ]; then
      print_info "Current client secret: $(mask_token "$existing_client_secret")"
      local new_client_secret
      new_client_secret=$(gum_input_password "Client Secret (Enter to keep current)")
      if [ -n "$new_client_secret" ]; then
        env_set "X_CLIENT_SECRET" "$new_client_secret"
      fi
    else
      local client_secret
      client_secret=$(gum_input_password "Client Secret")
      if [ -n "$client_secret" ]; then
        env_set "X_CLIENT_SECRET" "$client_secret"
      fi
    fi
  fi

  XURL_SETUP_STATUS="$bearer_status"
  print_success "X/Twitter credentials saved."
}
