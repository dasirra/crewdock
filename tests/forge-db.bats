#!/usr/bin/env bats
# Tests for agents/forge/forge-db.sh

load test_helper

FORGE_DB_SH="$PROJECT_ROOT/agents/forge/forge-db.sh"

setup() {
  setup_tmpdir
  export FORGE_DB="$TEST_TMPDIR/forge.db"
  bash "$FORGE_DB_SH" init >/dev/null
}

teardown() {
  teardown_tmpdir
}

# ---------------------------------------------------------------------------
# esc() — SQL injection protection (tested via queue + sqlite3 read)
# ---------------------------------------------------------------------------

@test "esc: single quotes are stored correctly" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "it's a test"
  result=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ "$result" = "it's a test" ]
}

@test "esc: multiple single quotes" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "it'''s"
  result=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ "$result" = "it'''s" ]
}

@test "esc: no quotes passes through" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "clean string"
  result=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ "$result" = "clean string" ]
}

@test "esc: empty string passes through" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" ""
  result=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ -z "$result" ]
}

@test "esc: SQL injection attempt is neutralized" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "'; DROP TABLE issues; --"
  # Table still exists and has the row
  result=$(sqlite3 "$FORGE_DB" "SELECT COUNT(*) FROM issues;")
  [ "$result" = "1" ]
  title=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ "$title" = "'; DROP TABLE issues; --" ]
}

# ---------------------------------------------------------------------------
# assert_int() — integer validation
# ---------------------------------------------------------------------------

@test "assert_int: valid integer passes" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "42"
  [ "$status" -eq 0 ]
}

@test "assert_int: zero passes" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "0"
  [ "$status" -eq 0 ]
}

@test "assert_int: negative number rejected" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "-1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected integer"* ]]
}

@test "assert_int: float rejected" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "3.14"
  [ "$status" -eq 1 ]
}

@test "assert_int: string rejected" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "abc"
  [ "$status" -eq 1 ]
}

@test "assert_int: empty string rejected" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int ""
  [ "$status" -eq 1 ]
}

@test "assert_int: SQL injection rejected" {
  assert_int() { [[ "$1" =~ ^[0-9]+$ ]] || { echo "Error: expected integer, got '$1'" >&2; exit 1; }; }
  run assert_int "1; DROP TABLE issues"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# init — schema creation
# ---------------------------------------------------------------------------

@test "init: creates database file" {
  [ -f "$FORGE_DB" ]
}

@test "init: creates issues table" {
  result=$(sqlite3 "$FORGE_DB" ".tables")
  [[ "$result" == *"issues"* ]]
}

@test "init: is idempotent" {
  run bash "$FORGE_DB_SH" init
  [ "$status" -eq 0 ]
  result=$(sqlite3 "$FORGE_DB" "SELECT COUNT(*) FROM issues;")
  [ "$result" = "0" ]
}

# ---------------------------------------------------------------------------
# queue / check — basic insert and lookup
# ---------------------------------------------------------------------------

@test "check: returns 'new' for unknown issue" {
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$status" -eq 0 ]
  [ "$output" = "new" ]
}

@test "queue: inserts issue" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "queued" ]
}

@test "queue: is idempotent" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  count=$(sqlite3 "$FORGE_DB" "SELECT COUNT(*) FROM issues WHERE repo='owner/repo' AND issue_number=1;")
  [ "$count" = "1" ]
}

@test "queue: handles special characters in title" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix: it's a <test> & stuff"
  result=$(sqlite3 "$FORGE_DB" "SELECT title FROM issues WHERE issue_number=1;")
  [ "$result" = "Fix: it's a <test> & stuff" ]
}

# ---------------------------------------------------------------------------
# State transitions: queue -> start -> done/fail/skip
# ---------------------------------------------------------------------------

@test "start: transitions to in_progress" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-123"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "in_progress" ]
}

@test "start: increments attempts" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-1"
  attempts=$(sqlite3 "$FORGE_DB" "SELECT attempts FROM issues WHERE issue_number=1;")
  [ "$attempts" = "1" ]
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-2"
  attempts=$(sqlite3 "$FORGE_DB" "SELECT attempts FROM issues WHERE issue_number=1;")
  [ "$attempts" = "2" ]
}

@test "start: stores session_id" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-abc"
  result=$(sqlite3 "$FORGE_DB" "SELECT session_id FROM issues WHERE issue_number=1;")
  [ "$result" = "session-abc" ]
}

@test "done: transitions to done with PR number" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-1"
  bash "$FORGE_DB_SH" done "owner/repo" "1" "42"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "done" ]
  pr=$(sqlite3 "$FORGE_DB" "SELECT pr_number FROM issues WHERE issue_number=1;")
  [ "$pr" = "42" ]
}

@test "fail: transitions to failed with error message" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "session-1"
  bash "$FORGE_DB_SH" fail "owner/repo" "1" "Compilation error"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "failed" ]
  error=$(sqlite3 "$FORGE_DB" "SELECT error FROM issues WHERE issue_number=1;")
  [ "$error" = "Compilation error" ]
}

@test "skip: transitions to skipped with reason" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Fix bug"
  bash "$FORGE_DB_SH" skip "owner/repo" "1" "Duplicate of #2"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "skipped" ]
}

# ---------------------------------------------------------------------------
# eligible — retry logic
# ---------------------------------------------------------------------------

@test "eligible: returns queued issues" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" queue "owner/repo" "2" "Bug B"
  run bash "$FORGE_DB_SH" eligible "owner/repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bug A"* ]]
  [[ "$output" == *"Bug B"* ]]
}

@test "eligible: excludes done issues" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" done "owner/repo" "1" "10"
  run bash "$FORGE_DB_SH" eligible "owner/repo"
  [[ "$output" != *"Bug A"* ]]
}

@test "eligible: includes failed below max_attempts" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" fail "owner/repo" "1" "error"
  run bash "$FORGE_DB_SH" eligible "owner/repo"
  [[ "$output" == *"Bug A"* ]]
}

@test "eligible: excludes failed at max_attempts" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  # Exhaust 3 attempts (default max_attempts)
  for i in 1 2 3; do
    bash "$FORGE_DB_SH" start "owner/repo" "1" "s$i"
    bash "$FORGE_DB_SH" fail "owner/repo" "1" "error $i"
  done
  run bash "$FORGE_DB_SH" eligible "owner/repo"
  [[ "$output" != *"Bug A"* ]]
}

# ---------------------------------------------------------------------------
# reset — manual retry
# ---------------------------------------------------------------------------

@test "reset: returns failed issue to queued" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" fail "owner/repo" "1" "error"
  bash "$FORGE_DB_SH" reset "owner/repo" "1"
  run bash "$FORGE_DB_SH" check "owner/repo" "1"
  [ "$output" = "queued" ]
}

@test "reset: clears error field" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" fail "owner/repo" "1" "error"
  bash "$FORGE_DB_SH" reset "owner/repo" "1"
  error=$(sqlite3 "$FORGE_DB" "SELECT error FROM issues WHERE issue_number=1;")
  [ -z "$error" ]
}

# ---------------------------------------------------------------------------
# list — filtering
# ---------------------------------------------------------------------------

@test "list: shows all issues by default" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" queue "owner/repo" "2" "Bug B"
  run bash "$FORGE_DB_SH" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bug A"* ]]
  [[ "$output" == *"Bug B"* ]]
}

@test "list: filters by status" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" queue "owner/repo" "2" "Bug B"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" done "owner/repo" "1" "10"
  run bash "$FORGE_DB_SH" list --status done
  [[ "$output" == *"Bug A"* ]]
  [[ "$output" != *"Bug B"* ]]
}

@test "list: filters by repo" {
  bash "$FORGE_DB_SH" queue "owner/repo-a" "1" "Bug A"
  bash "$FORGE_DB_SH" queue "owner/repo-b" "1" "Bug B"
  run bash "$FORGE_DB_SH" list --repo "owner/repo-a"
  [[ "$output" == *"Bug A"* ]]
  [[ "$output" != *"Bug B"* ]]
}

# ---------------------------------------------------------------------------
# stats
# ---------------------------------------------------------------------------

@test "stats: counts by status" {
  bash "$FORGE_DB_SH" queue "owner/repo" "1" "Bug A"
  bash "$FORGE_DB_SH" queue "owner/repo" "2" "Bug B"
  bash "$FORGE_DB_SH" start "owner/repo" "1" "s1"
  bash "$FORGE_DB_SH" done "owner/repo" "1" "10"
  run bash "$FORGE_DB_SH" stats
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
  [[ "$output" == *"queued"* ]]
}

# ---------------------------------------------------------------------------
# CLI argument validation
# ---------------------------------------------------------------------------

@test "cli: no args shows usage" {
  run bash "$FORGE_DB_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cli: unknown command shows usage" {
  run bash "$FORGE_DB_SH" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "cli: check with missing args shows usage" {
  run bash "$FORGE_DB_SH" check "owner/repo"
  [ "$status" -eq 1 ]
}

@test "cli: queue rejects non-integer issue number" {
  run bash "$FORGE_DB_SH" queue "owner/repo" "abc" "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected integer"* ]]
}
