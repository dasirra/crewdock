#!/usr/bin/env bash
# scouter-db.sh — SQLite helper for Scouter state tracking
# Location: agents/scouter/scouter-db.sh (tracked, copied to workspace on setup)

set -euo pipefail

DB="${SCOUTER_DB:-$HOME/.openclaw/workspace/agents/scouter/scouter.db}"

usage() {
  cat <<'EOF'
Usage: scouter-db.sh <command> [args]

Commands:
  init                                              Create tables if not exist
  scan <source> <source_name> <hash> <url> <title>  Record scanned item, returns ID
  is-scanned <hash>                                 Check if hash processed (exit 0=yes, 1=no)
  opportunity <item_id> <original> <draft> [template]  Create opportunity (optional template type)
  retype <id> <template>                               Change template type for pending opportunity
  resolve <id> <status> [edited_text]                  Mark approved/edited/discarded
  pending                                              List pending opportunities
  stats [days]                                         Approve/edit/discard rates (default: 30)
  cleanup [days]                                       Delete scanned_items older than N days (default: 90)
  migrate                                              Add new columns to existing DB
  lock                                              Set scan lock
  unlock                                            Release scan lock
  is-locked                                         Check lock (exit 0=locked, 1=unlocked)
  last-scan <source_name>                           Get last scan timestamp for a source
  set-last-scan <source_name>                       Set last scan timestamp to now
EOF
  exit 1
}

db() { sqlite3 "$DB" "$@"; }

# Escape single quotes for safe SQL interpolation: ' → ''
# Uses sed for bash 3.2 compatibility (parameter expansion backslash handling differs)
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

assert_int() {
  [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }
}

cmd_init() {
  mkdir -p "$(dirname "$DB")"
  db <<'SQL'
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS scanned_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    source_name TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    url TEXT,
    title TEXT,
    scanned_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_scanned_hash ON scanned_items(content_hash);
CREATE INDEX IF NOT EXISTS idx_scanned_source ON scanned_items(source, source_name);
CREATE INDEX IF NOT EXISTS idx_scanned_at ON scanned_items(scanned_at);

CREATE TABLE IF NOT EXISTS opportunities (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scanned_item_id INTEGER REFERENCES scanned_items(id) ON DELETE SET NULL,
    original_post TEXT NOT NULL,
    draft TEXT NOT NULL,
    template TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    edited_text TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_opp_status ON opportunities(status);
SQL
  echo "DB initialized: $DB"
  cmd_migrate
}

cmd_migrate() {
  local has_template
  has_template=$(db "SELECT COUNT(*) FROM pragma_table_info('opportunities') WHERE name='template';")
  if [[ "$has_template" == "0" ]]; then
    db "ALTER TABLE opportunities ADD COLUMN template TEXT;"
    echo "Migrated: added template column to opportunities."
  fi
}

cmd_scan() {
  local source; source=$(esc "$1")
  local source_name; source_name=$(esc "$2")
  local hash; hash=$(esc "$3")
  local url; url=$(esc "$4")
  local title; title=$(esc "$5")
  db "INSERT INTO scanned_items (source, source_name, content_hash, url, title) VALUES ('$source', '$source_name', '$hash', '$url', '$title'); SELECT last_insert_rowid();"
}

cmd_is_scanned() {
  local hash; hash=$(esc "$1")
  local count
  count=$(db "SELECT COUNT(*) FROM scanned_items WHERE content_hash='$hash';")
  [[ "$count" -gt 0 ]]
}

cmd_opportunity() {
  local item_id="$1"; assert_int "$item_id"
  local original; original=$(esc "$2")
  local draft; draft=$(esc "$3")
  local template="${4:-}"
  if [[ -n "$template" ]]; then
    template=$(esc "$template")
    db "INSERT INTO opportunities (scanned_item_id, original_post, draft, template) VALUES ($item_id, '$original', '$draft', '$template'); SELECT last_insert_rowid();"
  else
    db "INSERT INTO opportunities (scanned_item_id, original_post, draft) VALUES ($item_id, '$original', '$draft'); SELECT last_insert_rowid();"
  fi
}

cmd_resolve() {
  local id="$1"; assert_int "$id"
  local status; status=$(esc "$2")
  case "$status" in
    approved|edited|discarded) ;;
    *) echo "Error: invalid status '$status'. Must be: approved, edited, discarded" >&2; exit 1 ;;
  esac
  if [[ $# -ge 3 ]]; then
    local edited; edited=$(esc "$3")
    db "UPDATE opportunities SET status='$status', edited_text='$edited', resolved_at=datetime('now') WHERE id=$id;"
  else
    db "UPDATE opportunities SET status='$status', resolved_at=datetime('now') WHERE id=$id;"
  fi
}

cmd_retype() {
  local id="$1"; assert_int "$id"
  local template; template=$(esc "$2")
  local current_status
  current_status=$(db "SELECT status FROM opportunities WHERE id=$id;")
  if [[ "$current_status" != "pending" ]]; then
    echo "Error: opportunity $id is '$current_status', not 'pending'" >&2; exit 1
  fi
  db "UPDATE opportunities SET template='$template' WHERE id=$id;"
  echo "Opportunity $id retyped to: $template"
}

cmd_pending() {
  db -column -header "SELECT o.id, o.template, o.original_post, o.draft, o.created_at, s.source, s.url
      FROM opportunities o
      LEFT JOIN scanned_items s ON o.scanned_item_id = s.id
      WHERE o.status='pending'
      ORDER BY o.created_at ASC;"
}

cmd_stats() {
  local days="${1:-30}"
  assert_int "$days"
  echo "=== Scan stats (last $days days) ==="
  db -column -header "SELECT source, source_name, COUNT(*) as items
      FROM scanned_items
      WHERE scanned_at >= datetime('now', '-$days days')
      GROUP BY source, source_name
      ORDER BY items DESC;"
  echo ""
  echo "=== Opportunity stats (last $days days) ==="
  db -column -header "SELECT status, COUNT(*) as count
      FROM opportunities
      WHERE created_at >= datetime('now', '-$days days')
      GROUP BY status;"
}

cmd_cleanup() {
  local days="${1:-90}"
  assert_int "$days"
  local deleted
  deleted=$(db "DELETE FROM scanned_items WHERE scanned_at < datetime('now', '-$days days'); SELECT changes();")
  echo "Cleaned up $deleted scanned items older than $days days."
}

STALE_LOCK_MINUTES=30

cmd_lock() {
  db "INSERT OR REPLACE INTO meta (key, value, updated_at) VALUES ('scan_lock', datetime('now'), datetime('now'));"
}

cmd_unlock() {
  db "DELETE FROM meta WHERE key='scan_lock';"
}

cmd_is_locked() {
  local lock_time
  lock_time=$(db "SELECT value FROM meta WHERE key='scan_lock';")
  if [[ -z "$lock_time" ]]; then
    return 1
  fi
  # Check for stale lock
  local stale
  stale=$(db "SELECT CASE WHEN datetime('$lock_time', '+$STALE_LOCK_MINUTES minutes') < datetime('now') THEN 1 ELSE 0 END;")
  if [[ "$stale" == "1" ]]; then
    db "DELETE FROM meta WHERE key='scan_lock';"
    echo "Stale lock released (was set at $lock_time)." >&2
    return 1
  fi
  return 0
}

cmd_last_scan() {
  local source_name; source_name=$(esc "$1")
  db "SELECT value FROM meta WHERE key='last_scanned_$source_name';"
}

cmd_set_last_scan() {
  local source_name; source_name=$(esc "$1")
  db "INSERT OR REPLACE INTO meta (key, value, updated_at) VALUES ('last_scanned_$source_name', datetime('now'), datetime('now'));"
}

[[ $# -lt 1 ]] && usage

COMMAND="$1"; shift

case "$COMMAND" in
  init)          cmd_init ;;
  scan)          if [[ $# -ge 5 ]]; then cmd_scan "$1" "$2" "$3" "$4" "$5"; else usage; fi ;;
  is-scanned)    if [[ $# -ge 1 ]]; then cmd_is_scanned "$1"; else usage; fi ;;
  opportunity)   if [[ $# -ge 3 ]]; then cmd_opportunity "$@"; else usage; fi ;;
  resolve)       if [[ $# -ge 2 ]]; then cmd_resolve "$@"; else usage; fi ;;
  pending)       cmd_pending ;;
  stats)         cmd_stats "${1:-30}" ;;
  cleanup)       cmd_cleanup "${1:-90}" ;;
  migrate)       cmd_migrate ;;
  retype)        if [[ $# -ge 2 ]]; then cmd_retype "$1" "$2"; else usage; fi ;;
  lock)          cmd_lock ;;
  unlock)        cmd_unlock ;;
  is-locked)     cmd_is_locked ;;
  last-scan)     if [[ $# -ge 1 ]]; then cmd_last_scan "$1"; else usage; fi ;;
  set-last-scan) if [[ $# -ge 1 ]]; then cmd_set_last_scan "$1"; else usage; fi ;;
  *)             echo "Unknown command: $COMMAND"; usage ;;
esac
