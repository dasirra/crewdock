#!/usr/bin/env bash
# installer/github.sh — GitHub PAT setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: GITHUB_SETUP_STATUS (validated|unverified|skipped)

GITHUB_SETUP_STATUS="skipped"

# run_github — collect and validate GitHub Personal Access Token
run_github() {
  print_info "You need a GitHub Personal Access Token (PAT) with 'repo' scope."
  print_info "Create one at: https://github.com/settings/tokens/new?scopes=repo"
  echo ""
  print_info "  1. Click the link above (or go to GitHub > Settings > Developer settings > Personal access tokens)"
  print_info "  2. Select 'repo' scope"
  print_info "  3. Click 'Generate token'"
  print_info "  4. Copy the token (it won't be shown again)"
  echo ""

  local existing_token
  existing_token=$(env_get "GH_TOKEN")

  local token token_status="unverified"

  while true; do
    if [ -n "$existing_token" ]; then
      print_info "Current token: $(mask_token "$existing_token")"
      token=$(gum_input_password "GitHub PAT (Enter to keep current)")
      if [ -z "$token" ]; then
        token="$existing_token"
      fi
    else
      token=$(gum_input_password "GitHub Personal Access Token")
    fi

    if [ -z "$token" ]; then
      print_warn "No token provided."
      local choice
      choice=$(printf 'Retry\nSkip' | gum choose --header "What would you like to do?")
      case "$choice" in
        "Retry") continue ;;
        "Skip") GITHUB_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi

    # Validate token
    print_info "Validating token..."
    local response http_code headers_file body_file
    headers_file=$(mktemp)
    body_file=$(mktemp)

    http_code=$(curl -s \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/vnd.github+json" \
      -D "$headers_file" \
      -o "$body_file" \
      -w "%{http_code}" \
      "https://api.github.com/user" 2>/dev/null || echo "000")

    if [ "$http_code" = "200" ]; then
      local gh_user
      gh_user=$(python3 -c "import sys,json; d=json.load(open('$body_file')); print(d.get('login',''))" 2>/dev/null || \
               grep -o '"login":"[^"]*"' "$body_file" | cut -d'"' -f4 || echo "")

      # Check scopes
      local scopes
      scopes=$(grep -i "^x-oauth-scopes:" "$headers_file" 2>/dev/null | cut -d: -f2- | tr -d ' \r' || echo "")

      rm -f "$headers_file" "$body_file"

      if echo "$scopes" | grep -q "repo"; then
        print_success "Token valid! GitHub user: $gh_user"
        token_status="validated"
        break
      else
        print_warn "Token valid but missing 'repo' scope. Current scopes: $scopes"
        local scope_choice
        scope_choice=$(printf 'Save anyway\nRetry with correct token\nSkip' | \
          gum choose --header "Token lacks 'repo' scope. What would you like to do?")
        case "$scope_choice" in
          "Save anyway") token_status="unverified"; break ;;
          "Retry with correct token") continue ;;
          "Skip") GITHUB_SETUP_STATUS="skipped"; return 0 ;;
        esac
      fi
    else
      rm -f "$headers_file" "$body_file"
      print_error "Token validation failed (HTTP $http_code)"
      local fail_choice
      fail_choice=$(printf 'Retry\nSave anyway\nSkip' | gum choose --header "What would you like to do?")
      case "$fail_choice" in
        "Retry") continue ;;
        "Save anyway") token_status="unverified"; break ;;
        "Skip") GITHUB_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi
  done

  env_set "GH_TOKEN" "$token"
  GITHUB_SETUP_STATUS="$token_status"
  print_success "GitHub token saved."
}
