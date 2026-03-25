#!/usr/bin/env bats
# Tests for agents/forge/providers/linear.sh

load test_helper

LINEAR_PROVIDER_SH="$PROJECT_ROOT/agents/forge/providers/linear.sh"

# Mock curl: reads response from MOCK_CURL_RESPONSE env var, writes to -o file, prints MOCK_CURL_CODE.
# Usage: set MOCK_CURL_RESPONSE and MOCK_CURL_CODE before defining/exporting curl.
_setup_curl_mock() {
  curl() {
    local output_file="" prev=""
    for arg in "$@"; do
      [ "$prev" = "-o" ] && output_file="$arg"
      prev="$arg"
    done
    [ -n "$output_file" ] && printf '%s' "$MOCK_CURL_RESPONSE" > "$output_file"
    echo "${MOCK_CURL_CODE:-200}"
  }
  export -f curl
}

# ---------------------------------------------------------------------------
# provider_fetch_issues
# ---------------------------------------------------------------------------

@test "provider_fetch_issues: exits 1 when LINEAR_API_KEY is not set" {
  unset LINEAR_API_KEY
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run bash -c "source \"$LINEAR_PROVIDER_SH\"; provider_fetch_issues project-id 2>&1"

  [ "$status" -ne 0 ]
  [[ "$output" == *"LINEAR_API_KEY"* ]]
}

@test "provider_fetch_issues: returns normalized json array" {
  export LINEAR_API_KEY="lin_api_test"
  export MOCK_CURL_CODE="200"
  export MOCK_CURL_RESPONSE='{"data":{"project":{"issues":{"nodes":[{"number":1,"title":"Linear Bug","state":{"type":"unstarted","name":"Todo"},"labels":{"nodes":[{"name":"bug"}]},"createdAt":"2026-01-01T00:00:00.000Z"}]}}}}'
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run provider_fetch_issues "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"number"'* ]]
  [[ "$output" == *'"title"'* ]]
  [[ "$output" == *'Linear Bug'* ]]
  [[ "$output" == *'bug'* ]]
}

@test "provider_fetch_issues: output is a json array" {
  export LINEAR_API_KEY="lin_api_test"
  export MOCK_CURL_CODE="200"
  export MOCK_CURL_RESPONSE='{"data":{"project":{"issues":{"nodes":[{"number":2,"title":"Issue Two","state":{"type":"started","name":"In Progress"},"labels":{"nodes":[]},"createdAt":"2026-01-02T00:00:00.000Z"}]}}}}'
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run provider_fetch_issues "project-id"

  [ "$status" -eq 0 ]
  [[ "${output:0:1}" == "[" ]]
}

@test "provider_fetch_issues: returns empty array when no issues" {
  export LINEAR_API_KEY="lin_api_test"
  export MOCK_CURL_CODE="200"
  export MOCK_CURL_RESPONSE='{"data":{"project":{"issues":{"nodes":[]}}}}'
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run provider_fetch_issues "project-id"

  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "provider_fetch_issues: exits 1 on API error" {
  export LINEAR_API_KEY="lin_api_test"
  export MOCK_CURL_CODE="401"
  export MOCK_CURL_RESPONSE='{"errors":[{"message":"Unauthorized"}]}'
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run provider_fetch_issues "project-id"

  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# provider_get_issue
# ---------------------------------------------------------------------------

@test "provider_get_issue: returns normalized json with body field" {
  export LINEAR_API_KEY="lin_api_test"
  export MOCK_CURL_CODE="200"
  export MOCK_CURL_RESPONSE='{"data":{"project":{"issues":{"nodes":[{"number":5,"title":"My Issue","description":"The description text","url":"https://linear.app/team/issue/TEAM-5"}]}}}}'
  _setup_curl_mock

  source "$LINEAR_PROVIDER_SH"
  run provider_get_issue "project-id" "5"

  [ "$status" -eq 0 ]
  [[ "$output" == *'"number"'* ]]
  [[ "$output" == *'My Issue'* ]]
  [[ "$output" == *'"body"'* ]]
  [[ "$output" == *'"url"'* ]]
  # description must be mapped to body (not kept as description key)
  [[ "$output" != *'"description"'* ]]
}

# ---------------------------------------------------------------------------
# provider_has_open_pr (delegates to GitHub)
# ---------------------------------------------------------------------------

@test "provider_has_open_pr: returns 0 when matching github pr branch exists" {
  export LINEAR_API_KEY="lin_api_test"
  gh() {
    echo '[{"headRefName":"build/7-fix-bug"},{"headRefName":"main"}]'
  }
  export -f gh

  source "$LINEAR_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "7"

  [ "$status" -eq 0 ]
}

@test "provider_has_open_pr: returns 1 when no matching pr" {
  export LINEAR_API_KEY="lin_api_test"
  gh() { echo '[]'; }
  export -f gh

  source "$LINEAR_PROVIDER_SH"
  run provider_has_open_pr "owner/repo" "7"

  [ "$status" -eq 1 ]
}
