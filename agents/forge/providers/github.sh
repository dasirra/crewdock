#!/usr/bin/env bash
# agents/forge/providers/github.sh — GitHub Issues provider
# Source this file; do not execute directly.
# Implements: provider_fetch_issues, provider_get_issue, provider_has_open_pr
# Requires: gh CLI

# provider_fetch_issues <github_repo>
# github_repo: "owner/repo" string
# Outputs JSON array: [{"number":N,"title":"...","labels":[{"name":"..."}],"createdAt":"..."}]
provider_fetch_issues() {
  local repo="$1"
  gh issue list --repo "$repo" --state open --sort created \
    --json number,title,labels,createdAt --limit 30
}

# provider_get_issue <github_repo> <issue_number>
# Outputs single issue JSON: {"number":N,"title":"...","body":"...","url":"..."}
provider_get_issue() {
  local repo="$1"
  local number="$2"
  gh issue view "$number" --repo "$repo" --json number,title,body,url
}

# provider_has_open_pr <github_repo> <issue_number>
# Returns 0 if an open PR exists for this issue, 1 if not.
# Checks whether any open PR branch name contains the issue number.
provider_has_open_pr() {
  local repo="$1"
  local issue_number="$2"
  local branches
  branches=$(gh pr list --repo "$repo" --state open --json headRefName 2>/dev/null | \
    python3 -c "import sys,json; data=json.load(sys.stdin); print('\n'.join(p['headRefName'] for p in data))" \
    2>/dev/null || true)
  if echo "$branches" | grep -qE "(^|[^0-9])${issue_number}([^0-9]|$)"; then
    return 0
  fi
  return 1
}
