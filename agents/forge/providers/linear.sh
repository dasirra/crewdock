#!/usr/bin/env bash
# agents/forge/providers/linear.sh — Linear Issues provider
# Source this file; do not execute directly.
# Implements: provider_fetch_issues, provider_get_issue, provider_has_open_pr
# Requires: LINEAR_API_KEY env var, curl, python3

# _linear_graphql <query_json>
# Internal helper: POST a GraphQL query to Linear API, outputs response body.
# Exits 1 on HTTP error or GraphQL-level error (errors key in response).
_linear_graphql() {
  local query_json="$1"
  if [ -z "${LINEAR_API_KEY:-}" ]; then
    echo "Error: LINEAR_API_KEY is not set" >&2
    return 1
  fi
  local body_file
  body_file=$(mktemp)
  local http_code
  http_code=$(curl -s \
    -H "Authorization: Bearer $LINEAR_API_KEY" \
    -H "Content-Type: application/json" \
    -X POST \
    -o "$body_file" \
    -w "%{http_code}" \
    --data "$query_json" \
    "https://api.linear.app/graphql" 2>/dev/null || echo "000")
  if [ "$http_code" != "200" ]; then
    echo "Error: Linear API request failed (HTTP $http_code)" >&2
    rm -f "$body_file"
    return 1
  fi
  # Check for GraphQL-level errors (HTTP 200 with errors key)
  if python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
if 'errors' in d:
    msgs = '; '.join(e.get('message','unknown') for e in d['errors'])
    print('Error: Linear GraphQL error: ' + msgs, file=sys.stderr)
    sys.exit(1)
" < "$body_file" 2>&1; then
    cat "$body_file"
    rm -f "$body_file"
  else
    rm -f "$body_file"
    return 1
  fi
}

# provider_fetch_issues <linear_project_id>
# linear_project_id: Linear project UUID (e.g. "a1b2c3d4-e5f6-7890-abcd-ef1234567890")
# Outputs JSON array matching github.sh format:
# [{"number":N,"title":"...","labels":[{"name":"..."}],"createdAt":"..."}]
provider_fetch_issues() {
  local project_id="$1"
  local query_json
  query_json=$(python3 -c "
import json, sys
q = '''
query ProjectIssues(\$projectId: String!, \$first: Int!) {
  project(id: \$projectId) {
    issues(
      filter: { state: { type: { nin: [\"completed\", \"cancelled\"] } } }
      orderBy: createdAt
      first: \$first
    ) {
      nodes {
        number
        title
        state { type name }
        labels { nodes { name } }
        createdAt
      }
    }
  }
}
'''.strip()
print(json.dumps({'query': q, 'variables': {'projectId': sys.argv[1], 'first': 30}}))
" "$project_id")

  local response
  response=$(_linear_graphql "$query_json") || return 1

  # Transform Linear response format to match github.sh output format
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
project = data.get('data', {}).get('project')
if project is None:
    print('Error: project not found — check linearProject UUID in config.json', file=sys.stderr)
    sys.exit(1)
nodes = project.get('issues', {}).get('nodes', [])
result = []
for n in nodes:
    result.append({
        'number': n['number'],
        'title': n['title'],
        'labels': [{'name': lbl['name']} for lbl in n.get('labels', {}).get('nodes', [])],
        'createdAt': n['createdAt']
    })
print(json.dumps(result))
" <<< "$response"
}

# provider_get_issue <linear_project_id> <issue_number>
# Outputs single issue JSON: {"number":N,"title":"...","body":"...","url":"..."}
# Reserved for future use (e.g. passing issue body into autopilot context).
provider_get_issue() {
  local project_id="$1"
  local number="$2"
  local query_json
  query_json=$(python3 -c "
import json, sys
q = '''
query IssueDetail(\$projectId: String!, \$number: Int!) {
  project(id: \$projectId) {
    issues(filter: { number: { eq: \$number } }, first: 1) {
      nodes {
        number
        title
        description
        url
      }
    }
  }
}
'''.strip()
print(json.dumps({'query': q, 'variables': {'projectId': sys.argv[1], 'number': int(sys.argv[2])}}))
" "$project_id" "$number")

  local response
  response=$(_linear_graphql "$query_json") || return 1

  # Transform: map description -> body for consistency with github.sh output
  python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
project = data.get('data', {}).get('project')
if project is None:
    print('Error: project not found — check linearProject UUID in config.json', file=sys.stderr)
    sys.exit(1)
nodes = project.get('issues', {}).get('nodes', [])
if not nodes:
    print('{}')
    sys.exit(0)
n = nodes[0]
print(json.dumps({
    'number': n['number'],
    'title': n['title'],
    'body': n.get('description') or '',
    'url': n.get('url') or ''
}))
" <<< "$response"
}

# provider_has_open_pr <github_repo> <issue_number>
# Returns 0 if an open PR exists for this issue, 1 if not.
# PRs always go to GitHub regardless of issue provider.
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
