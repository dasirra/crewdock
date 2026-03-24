#!/usr/bin/env bats
# Tests for installer/lib.sh (env_get, env_set, env_blank, mask_token)

load test_helper

setup() {
  setup_tmpdir
  # lib.sh reads _ENV_FILE based on SCRIPT_DIR
  export SCRIPT_DIR="$TEST_TMPDIR"
  # Stub gum so lib.sh can be sourced without it installed
  gum() { :; }
  export -f gum
  source "$PROJECT_ROOT/installer/lib.sh"
}

teardown() {
  teardown_tmpdir
}

# ---------------------------------------------------------------------------
# mask_token
# ---------------------------------------------------------------------------

@test "mask_token: long token shows last 4" {
  run mask_token "ghp_abcdefghijk1234"
  [ "$output" = "****...1234" ]
}

@test "mask_token: exactly 4 chars shows ****" {
  run mask_token "abcd"
  [ "$output" = "****" ]
}

@test "mask_token: shorter than 4 chars shows ****" {
  run mask_token "ab"
  [ "$output" = "****" ]
}

@test "mask_token: empty string shows ****" {
  run mask_token ""
  [ "$output" = "****" ]
}

@test "mask_token: 5 chars shows last 4" {
  run mask_token "12345"
  [ "$output" = "****...2345" ]
}

# ---------------------------------------------------------------------------
# env_get — read from .env
# ---------------------------------------------------------------------------

@test "env_get: missing file returns empty" {
  run env_get "MISSING_KEY"
  [ "$output" = "" ]
}

@test "env_get: reads unquoted value" {
  echo "MY_KEY=hello" > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "hello" ]
}

@test "env_get: reads double-quoted value" {
  echo 'MY_KEY="hello world"' > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "hello world" ]
}

@test "env_get: reads single-quoted value" {
  echo "MY_KEY='hello world'" > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "hello world" ]
}

@test "env_get: missing key returns empty" {
  echo "OTHER_KEY=value" > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "" ]
}

@test "env_get: value with equals sign" {
  echo "MY_KEY=a=b=c" > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "a=b=c" ]
}

@test "env_get: uses last occurrence when duplicated" {
  printf 'MY_KEY=first\nMY_KEY=second\n' > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "second" ]
}

@test "env_get: empty value" {
  echo "MY_KEY=" > "$TEST_TMPDIR/.env"
  run env_get "MY_KEY"
  [ "$output" = "" ]
}

# ---------------------------------------------------------------------------
# env_set — write to .env
# ---------------------------------------------------------------------------

@test "env_set: creates file if missing" {
  env_set "MY_KEY" "my_value"
  [ -f "$TEST_TMPDIR/.env" ]
  run env_get "MY_KEY"
  [ "$output" = "my_value" ]
}

@test "env_set: sets correct permissions" {
  env_set "MY_KEY" "my_value"
  perms=$(stat -f "%Lp" "$TEST_TMPDIR/.env" 2>/dev/null || stat -c "%a" "$TEST_TMPDIR/.env" 2>/dev/null)
  [ "$perms" = "600" ]
}

@test "env_set: updates existing key" {
  echo "MY_KEY=old" > "$TEST_TMPDIR/.env"
  chmod 600 "$TEST_TMPDIR/.env"
  env_set "MY_KEY" "new"
  run env_get "MY_KEY"
  [ "$output" = "new" ]
}

@test "env_set: appends new key" {
  echo "EXISTING=value" > "$TEST_TMPDIR/.env"
  chmod 600 "$TEST_TMPDIR/.env"
  env_set "NEW_KEY" "new_value"
  run env_get "EXISTING"
  [ "$output" = "value" ]
  run env_get "NEW_KEY"
  [ "$output" = "new_value" ]
}

@test "env_set: preserves other keys when updating" {
  printf 'KEY_A=aaa\nKEY_B=bbb\nKEY_C=ccc\n' > "$TEST_TMPDIR/.env"
  chmod 600 "$TEST_TMPDIR/.env"
  env_set "KEY_B" "updated"
  run env_get "KEY_A"
  [ "$output" = "aaa" ]
  run env_get "KEY_B"
  [ "$output" = "updated" ]
  run env_get "KEY_C"
  [ "$output" = "ccc" ]
}

# ---------------------------------------------------------------------------
# env_blank — set to empty
# ---------------------------------------------------------------------------

@test "env_blank: sets key to empty" {
  echo "MY_KEY=something" > "$TEST_TMPDIR/.env"
  chmod 600 "$TEST_TMPDIR/.env"
  env_blank "MY_KEY"
  run env_get "MY_KEY"
  [ "$output" = "" ]
}
