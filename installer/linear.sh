#!/usr/bin/env bash
# installer/linear.sh — Linear API key setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: LINEAR_SETUP_STATUS (validated|unverified|skipped)

LINEAR_SETUP_STATUS="skipped"

# run_linear — collect and validate Linear API key
run_linear() {
  print_info "You need a Linear API key to use Linear as an issue source."
  print_info "Create one at: https://linear.app/settings/api"
  echo ""
  print_info "  1. Go to Linear > Settings > API"
  print_info "  2. Click 'Create key'"
  print_info "  3. Give it a name (e.g., 'Forge')"
  print_info "  4. Copy the key"
  echo ""

  local existing_key
  existing_key=$(env_get "LINEAR_API_KEY")

  local api_key key_status="unverified"

  while true; do
    if [ -n "$existing_key" ]; then
      print_info "Current key: $(mask_token "$existing_key")"
      api_key=$(gum_input_password "Linear API key (Enter to keep current)")
      if [ -z "$api_key" ]; then
        api_key="$existing_key"
      fi
    else
      api_key=$(gum_input_password "Linear API key")
    fi

    if [ -z "$api_key" ]; then
      print_warn "No key provided."
      local choice
      choice=$(printf 'Retry\nSkip' | gum choose --header "What would you like to do?")
      case "$choice" in
        "Retry") continue ;;
        "Skip") LINEAR_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi

    # Validate key
    print_info "Validating key..."
    local body_file http_code
    body_file=$(mktemp)

    http_code=$(curl -s \
      -H "Authorization: Bearer $api_key" \
      -H "Content-Type: application/json" \
      -X POST \
      -o "$body_file" \
      -w "%{http_code}" \
      --data '{"query": "{ viewer { id login name } }"}' \
      "https://api.linear.app/graphql" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      local linear_user
      linear_user=$(python3 -c "import sys,json; d=json.load(open('$body_file')); print(d.get('data',{}).get('viewer',{}).get('name',''))" 2>/dev/null || \
                   grep -o '"name":"[^"]*"' "$body_file" | head -1 | cut -d'"' -f4 || echo "")

      rm -f "$body_file"

      if [ -n "$linear_user" ]; then
        print_success "Key valid! Linear user: $linear_user"
        key_status="validated"
        break
      else
        print_warn "Key valid but could not retrieve user info."
        local user_choice
        user_choice=$(printf 'Save anyway\nRetry\nSkip' | gum choose --header "What would you like to do?")
        case "$user_choice" in
          "Save anyway") key_status="unverified"; break ;;
          "Retry") continue ;;
          "Skip") LINEAR_SETUP_STATUS="skipped"; return 0 ;;
        esac
      fi
    else
      rm -f "$body_file"
      print_error "Key validation failed (HTTP $http_code)"
      local fail_choice
      fail_choice=$(printf 'Retry\nSave anyway\nSkip' | gum choose --header "What would you like to do?")
      case "$fail_choice" in
        "Retry") continue ;;
        "Save anyway") key_status="unverified"; break ;;
        "Skip") LINEAR_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi
  done

  env_set "LINEAR_API_KEY" "$api_key"
  LINEAR_SETUP_STATUS="$key_status"
  print_success "Linear API key saved."
}
