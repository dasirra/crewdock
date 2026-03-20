#!/usr/bin/env bash
# installer/claude.sh — Claude OAuth token setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: CLAUDE_SETUP_STATUS (validated|unverified|skipped)

CLAUDE_SETUP_STATUS="skipped"

# run_claude — collect Claude OAuth token (not validated on host)
run_claude() {
  print_info "You need a Claude Code OAuth token."
  print_info "To obtain one:"
  echo ""
  print_info "  1. Run 'claude' in your terminal (install from https://claude.ai/code if needed)"
  print_info "  2. Complete the sign-in flow in your browser"
  print_info "  3. Find your token in: ~/.claude/.credentials.json"
  print_info "     Look for: { \"claudeAiOauth\": { \"accessToken\": \"sk-ant-oat...\" } }"
  echo ""
  print_info "Note: This token is verified on container boot, not here."
  echo ""

  local existing_token
  existing_token=$(env_get "CLAUDE_CODE_OAUTH_TOKEN")

  if [ -n "$existing_token" ]; then
    print_info "Current token: $(mask_token "$existing_token")"
    local new_token
    new_token=$(gum_input_password "Claude OAuth token (Enter to keep current)")
    if [ -z "$new_token" ]; then
      CLAUDE_SETUP_STATUS="unverified"
      print_info "Keeping existing token."
      return 0
    fi
    env_set "CLAUDE_CODE_OAUTH_TOKEN" "$new_token"
    CLAUDE_SETUP_STATUS="unverified"
    print_success "Claude token saved (will be verified on container boot)."
    return 0
  fi

  local token
  while true; do
    token=$(gum_input_password "Claude OAuth token")

    if [ -n "$token" ]; then
      break
    fi

    print_warn "No token provided."
    local choice
    choice=$(printf 'Retry\nSkip' | gum choose --header "What would you like to do?")
    case "$choice" in
      "Skip") CLAUDE_SETUP_STATUS="skipped"; return 0 ;;
      "Retry") continue ;;
    esac
  done

  env_set "CLAUDE_CODE_OAUTH_TOKEN" "$token"
  # Not validated on host — verified on container boot
  CLAUDE_SETUP_STATUS="unverified"
  print_success "Claude token saved (will be verified on container boot)."
}
