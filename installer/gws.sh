#!/usr/bin/env bash
# installer/gws.sh — Google Workspace credentials setup flow
# Bash 3.2+ compatible
# Sources lib.sh (assumed already sourced by orchestrator)
# Exports: GWS_SETUP_STATUS (validated|unverified|skipped)

GWS_SETUP_STATUS="skipped"

# run_gws — collect and validate Google Workspace credentials JSON
run_gws() {
  print_info "You need OAuth 2.0 Desktop credentials from Google Cloud Console."
  echo ""
  print_info "Steps:"
  print_info "  1. Go to https://console.cloud.google.com"
  print_info "  2. Create a project (or select an existing one)"
  print_info "  3. Enable APIs: Gmail, Calendar, Drive, Sheets"
  print_info "     (APIs & Services > Library, search and enable each)"
  print_info "  4. Go to APIs & Services > Credentials"
  print_info "  5. Click 'Create Credentials' > 'OAuth client ID'"
  print_info "  6. Application type: Desktop app"
  print_info "  7. Download the JSON file"
  print_info "  8. Open it and paste its contents below"
  echo ""

  local creds_dir="${SCRIPT_DIR:-.}/home/.config/gws"
  local creds_file="$creds_dir/credentials.json"

  if [ -f "$creds_file" ]; then
    print_info "Existing credentials found at: home/.config/gws/credentials.json"
    if ! gum_confirm "Replace existing credentials?"; then
      GWS_SETUP_STATUS="unverified"
      print_info "Keeping existing credentials."
      return 0
    fi
  fi

  local json_content status="unverified"

  while true; do
    print_info "Paste your credentials JSON (Ctrl+D when done):"
    json_content=$(gum_write "Paste credentials JSON:")

    if [ -z "$json_content" ]; then
      print_warn "No content provided."
      local choice
      choice=$(printf 'Retry\nSkip' | gum choose --header "What would you like to do?")
      case "$choice" in
        "Retry") continue ;;
        "Skip") GWS_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi

    # Validate JSON structure
    # Supports three formats:
    #   1. OAuth Desktop/Web: {"installed": {"client_id": ..., "client_secret": ...}}
    #   2. OAuth Web:         {"web": {"client_id": ..., "client_secret": ...}}
    #   3. Exported auth:     {"client_id": ..., "client_secret": ..., "type": "authorized_user"}
    local valid=0
    if command -v python3 >/dev/null 2>&1; then
      client_id=$(echo "$json_content" | python3 -c "
import sys, json
try:
    d = json.loads(sys.stdin.read())
    creds = d.get('installed') or d.get('web') or d
    if creds.get('client_id') and creds.get('client_secret'):
        print('valid')
    else:
        print('invalid')
except:
    print('invalid')
" 2>/dev/null || echo "invalid")
      if [ "$client_id" = "valid" ]; then
        valid=1
      fi
    elif command -v jq >/dev/null 2>&1; then
      local cid csc
      cid=$(echo "$json_content" | jq -r '.installed.client_id // .web.client_id // .client_id // empty' 2>/dev/null || echo "")
      csc=$(echo "$json_content" | jq -r '.installed.client_secret // .web.client_secret // .client_secret // empty' 2>/dev/null || echo "")
      if [ -n "$cid" ] && [ -n "$csc" ]; then
        valid=1
      fi
    else
      # Can't validate, save anyway
      print_warn "Cannot validate JSON (python3/jq not available). Saving as-is."
      valid=1
      status="unverified"
    fi

    if [ "$valid" -eq 1 ]; then
      print_success "Credentials JSON looks valid."
      status="validated"
      break
    else
      print_error "Invalid credentials JSON. Expected 'client_id' and 'client_secret' fields (nested under 'installed'/'web' or at top level)."
      local fail_choice
      fail_choice=$(printf 'Retry\nSave anyway\nSkip' | gum choose --header "What would you like to do?")
      case "$fail_choice" in
        "Retry") continue ;;
        "Save anyway") status="unverified"; break ;;
        "Skip") GWS_SETUP_STATUS="skipped"; return 0 ;;
      esac
    fi
  done

  # Write credentials file
  mkdir -p "$creds_dir"
  printf '%s' "$json_content" > "$creds_file"
  chmod 600 "$creds_file"

  GWS_SETUP_STATUS="$status"
  print_success "GWS credentials saved to home/.config/gws/credentials.json"
}
