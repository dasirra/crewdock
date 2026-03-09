#!/usr/bin/env bash
# forge-db.sh — SQLite helper for Forge issue tracking
# Location: agents/forge/forge-db.sh (tracked, copied to workspace on setup)

set -euo pipefail

DB="${FORGE_DB:-$HOME/.openclaw/workspace/agents/forge/forge.db}"

usage() {
  cat <<'EOF'
Usage: forge-db.sh <command> [args]

Commands:
  init                                      Create tables if not exist
  check <repo> <issue_number>               Print status (or 'new')
  queue <repo> <issue_number> <title>       Insert as queued
  start <repo> <issue_number> <session_id>  Set in_progress, increment attempts
  done  <repo> <issue_number> <pr_number>   Set done, store PR number
  fail  <repo> <issue_number> 'error msg'   Set failed, store error
  skip  <repo> <issue_number> 'reason'      Set skipped
  list  [--status <status>] [--repo <repo>] List issues with filters
  eligible <repo>                           List eligible issues (number title)
  reset <repo> <issue_number>               Reset to queued (manual retry)
  stats                                     Summary counts by status
EOF
  exit 1
}

db() { sqlite3 "$DB" "$@"; }

cmd_init() {
  mkdir -p "$(dirname "$DB")"
  db <<'SQL'
CREATE TABLE IF NOT EXISTS issues (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    issue_number INTEGER NOT NULL,
    title TEXT,
    status TEXT NOT NULL DEFAULT 'queued',
    session_id TEXT,
    pr_number INTEGER,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 3,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    error TEXT,
    UNIQUE(repo, issue_number)
);
SQL
  echo "DB initialized: $DB"
}

cmd_check() {
  local repo="$1" num="$2"
  local status
  status=$(db "SELECT status FROM issues WHERE repo='$repo' AND issue_number=$num;")
  echo "${status:-new}"
}

cmd_queue() {
  local repo="$1" num="$2" title="$3"
  db "INSERT OR IGNORE INTO issues (repo, issue_number, title, status) VALUES ('$repo', $num, '$title', 'queued');
      UPDATE issues SET updated_at=datetime('now') WHERE repo='$repo' AND issue_number=$num AND status='queued';"
}

cmd_start() {
  local repo="$1" num="$2" session_id="$3"
  db "UPDATE issues SET status='in_progress', session_id='$session_id', attempts=attempts+1, updated_at=datetime('now')
      WHERE repo='$repo' AND issue_number=$num;"
}

cmd_done() {
  local repo="$1" num="$2" pr_number="$3"
  db "UPDATE issues SET status='done', pr_number=$pr_number, updated_at=datetime('now')
      WHERE repo='$repo' AND issue_number=$num;"
}

cmd_fail() {
  local repo="$1" num="$2" error="$3"
  db "UPDATE issues SET status='failed', error='$error', updated_at=datetime('now')
      WHERE repo='$repo' AND issue_number=$num;"
}

cmd_skip() {
  local repo="$1" num="$2" reason="$3"
  db "UPDATE issues SET status='skipped', error='$reason', updated_at=datetime('now')
      WHERE repo='$repo' AND issue_number=$num;"
}

cmd_list() {
  local where="1=1"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) where="$where AND status='$2'"; shift 2 ;;
      --repo)   where="$where AND repo='$2'";   shift 2 ;;
      *) echo "Unknown option: $1"; usage ;;
    esac
  done
  db -column -header "SELECT repo, issue_number, title, status, attempts, pr_number, updated_at FROM issues WHERE $where ORDER BY updated_at DESC;"
}

cmd_eligible() {
  local repo="$1"
  db "SELECT issue_number, title FROM issues
      WHERE repo='$repo'
        AND (
          status='queued'
          OR (status='failed' AND attempts < max_attempts)
        )
      ORDER BY created_at ASC;"
}

cmd_reset() {
  local repo="$1" num="$2"
  db "UPDATE issues SET status='queued', error=NULL, updated_at=datetime('now')
      WHERE repo='$repo' AND issue_number=$num;"
}

cmd_stats() {
  db -column -header "SELECT status, COUNT(*) as count FROM issues GROUP BY status;"
}

[[ $# -lt 1 ]] && usage

COMMAND="$1"; shift

case "$COMMAND" in
  init)     cmd_init ;;
  check)    [[ $# -ge 2 ]] && cmd_check "$1" "$2" || usage ;;
  queue)    [[ $# -ge 3 ]] && cmd_queue "$1" "$2" "$3" || usage ;;
  start)    [[ $# -ge 3 ]] && cmd_start "$1" "$2" "$3" || usage ;;
  done)     [[ $# -ge 3 ]] && cmd_done "$1" "$2" "$3" || usage ;;
  fail)     [[ $# -ge 3 ]] && cmd_fail "$1" "$2" "$3" || usage ;;
  skip)     [[ $# -ge 3 ]] && cmd_skip "$1" "$2" "$3" || usage ;;
  list)     cmd_list "$@" ;;
  eligible) [[ $# -ge 1 ]] && cmd_eligible "$1" || usage ;;
  reset)    [[ $# -ge 2 ]] && cmd_reset "$1" "$2" || usage ;;
  stats)    cmd_stats ;;
  *)        echo "Unknown command: $COMMAND"; usage ;;
esac
