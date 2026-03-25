#!/usr/bin/env bats
# Tests for agents/forge/providers/github.sh

load test_helper

GITHUB_PROVIDER_SH="$PROJECT_ROOT/agents/forge/providers/github.sh"

# ---------------------------------------------------------------------------
# provider_fetch_issues
# ---------------------------------------------------------------------------

@test "provider_fetch_issues: calls gh issue list with correct args" {
  local actual_args=""
  gh() { actual_args="$*"; echo '[]'; }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  provider_fetch_issues "owner/repo"

  [[ "$actual_args" == *"issue list"* ]]
  [[ "$actual_args" == *"--repo owner/repo"* ]]
  [[ "$actual_args" == *"--state open"* ]]
  [[ "$actual_args" == *"--sort created"* ]]
  [[ "$actual_args" == *"--limit 30"* ]]
}

@test "provider_fetch_issues: returns json array from gh" {
  gh() {
    echo '[{"number":1,"title":"Bug A","labels":[{"name":"bug"}],"createdAt":"2026-01-01T00:00:00.000Z"}]'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_fetch_issues "owner/repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":1'* ]]
  [[ "$output" == *'"title":"Bug A"'* ]]
}

@test "provider_fetch_issues: propagates gh failure" {
  gh() { return 1; }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_fetch_issues "owner/repo"

  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# provider_get_issue
# ---------------------------------------------------------------------------

@test "provider_get_issue: calls gh issue view with correct args" {
  local actual_args=""
  gh() { actual_args="$*"; echo '{"number":42,"title":"Fix it","body":"desc","url":"https://github.com/x/y/issues/42"}'; }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  provider_get_issue "owner/repo" "42"

  [[ "$actual_args" == *"issue view 42"* ]]
  [[ "$actual_args" == *"--repo owner/repo"* ]]
  [[ "$actual_args" == *"--json number,title,body,url"* ]]
}

@test "provider_get_issue: returns issue json" {
  gh() {
    echo '{"number":42,"title":"Fix it","body":"Some description","url":"https://github.com/x/y/issues/42"}'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_get_issue "owner/repo" "42"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"number":42'* ]]
  [[ "$output" == *'"title":"Fix it"'* ]]
}

# ---------------------------------------------------------------------------
# provider_has_open_pr
# ---------------------------------------------------------------------------

@test "provider_has_open_pr: returns 0 when matching branch exists" {
  gh() {
    echo '[{"headRefName":"build/42-fix-bug"},{"headRefName":"build/10-other"}]'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "42"

  [ "$status" -eq 0 ]
}

@test "provider_has_open_pr: returns 1 when no matching branch" {
  gh() {
    echo '[{"headRefName":"build/10-other"},{"headRefName":"feat/add-feature"}]'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "42"

  [ "$status" -eq 1 ]
}

@test "provider_has_open_pr: returns 1 when no open prs" {
  gh() { echo '[]'; }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "42"

  [ "$status" -eq 1 ]
}

@test "provider_has_open_pr: matches issue number in various branch formats" {
  gh() {
    echo '[{"headRefName":"fix-42"}]'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "42"

  [ "$status" -eq 0 ]
}

@test "provider_has_open_pr: does not match partial number (42 should not match 142)" {
  gh() {
    echo '[{"headRefName":"build/142-something"}]'
  }
  export -f gh

  source "$GITHUB_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "42"

  [ "$status" -eq 1 ]
}
