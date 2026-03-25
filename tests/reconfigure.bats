#!/usr/bin/env bats
# Tests for _integration_status helper in install.sh

load test_helper

setup() {
  setup_tmpdir
  export SCRIPT_DIR="$TEST_TMPDIR"
  # Stub gum so lib.sh can be sourced without it installed
  gum() { :; }
  export -f gum
  source "$PROJECT_ROOT/installer/lib.sh"

  # Define _integration_status as extracted from install.sh
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
  export -f _integration_status
}

teardown() {
  teardown_tmpdir
}

# ---------------------------------------------------------------------------
# discord
# ---------------------------------------------------------------------------

@test "_integration_status: discord configured when DISCORD_FORGE_TOKEN set" {
  echo "DISCORD_FORGE_TOKEN=some-token" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "discord"
  [ "$output" = "configured" ]
}

@test "_integration_status: discord not configured when DISCORD_FORGE_TOKEN empty" {
  echo "DISCORD_FORGE_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "discord"
  [ "$output" = "not configured" ]
}

@test "_integration_status: discord not configured when DISCORD_FORGE_TOKEN absent" {
  run _integration_status "forge" "discord"
  [ "$output" = "not configured" ]
}

@test "_integration_status: discord uses agent id uppercased (scouter)" {
  echo "DISCORD_SCOUTER_TOKEN=abc123" > "$TEST_TMPDIR/.env"
  run _integration_status "scouter" "discord"
  [ "$output" = "configured" ]
}

# ---------------------------------------------------------------------------
# github
# ---------------------------------------------------------------------------

@test "_integration_status: github configured when GH_TOKEN set" {
  echo "GH_TOKEN=ghp_abc123" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "github"
  [ "$output" = "configured" ]
}

@test "_integration_status: github not configured when GH_TOKEN empty" {
  echo "GH_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "github"
  [ "$output" = "not configured" ]
}

@test "_integration_status: github not configured when GH_TOKEN absent" {
  run _integration_status "forge" "github"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# claude
# ---------------------------------------------------------------------------

@test "_integration_status: claude configured when CLAUDE_CODE_OAUTH_TOKEN set" {
  echo "CLAUDE_CODE_OAUTH_TOKEN=oauth-token-xyz" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "claude"
  [ "$output" = "configured" ]
}

@test "_integration_status: claude not configured when CLAUDE_CODE_OAUTH_TOKEN empty" {
  echo "CLAUDE_CODE_OAUTH_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "claude"
  [ "$output" = "not configured" ]
}

@test "_integration_status: claude not configured when CLAUDE_CODE_OAUTH_TOKEN absent" {
  run _integration_status "forge" "claude"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# gws
# ---------------------------------------------------------------------------

@test "_integration_status: gws configured when credentials.json exists" {
  mkdir -p "$TEST_TMPDIR/home/.config/gws"
  touch "$TEST_TMPDIR/home/.config/gws/credentials.json"
  run _integration_status "forge" "gws"
  [ "$output" = "configured" ]
}

@test "_integration_status: gws not configured when credentials.json absent" {
  run _integration_status "forge" "gws"
  [ "$output" = "not configured" ]
}

@test "_integration_status: gws not configured when config dir exists but file missing" {
  mkdir -p "$TEST_TMPDIR/home/.config/gws"
  run _integration_status "forge" "gws"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# xurl
# ---------------------------------------------------------------------------

@test "_integration_status: xurl configured when X_BEARER_TOKEN set" {
  echo "X_BEARER_TOKEN=bearer-xyz" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "xurl"
  [ "$output" = "configured" ]
}

@test "_integration_status: xurl not configured when X_BEARER_TOKEN empty" {
  echo "X_BEARER_TOKEN=" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "xurl"
  [ "$output" = "not configured" ]
}

@test "_integration_status: xurl not configured when X_BEARER_TOKEN absent" {
  run _integration_status "forge" "xurl"
  [ "$output" = "not configured" ]
}

# ---------------------------------------------------------------------------
# unknown integration
# ---------------------------------------------------------------------------

@test "_integration_status: unknown integration returns not configured" {
  run _integration_status "forge" "nonexistent"
  [ "$output" = "not configured" ]
}

@test "_integration_status: unknown integration with token in env still returns not configured" {
  echo "SOME_TOKEN=value" > "$TEST_TMPDIR/.env"
  run _integration_status "forge" "unknown_intg"
  [ "$output" = "not configured" ]
}
