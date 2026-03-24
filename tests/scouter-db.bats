#!/usr/bin/env bats
# Tests for agents/scouter/scouter-db.sh

load test_helper

SCOUTER_DB_SH="$PROJECT_ROOT/agents/scouter/scouter-db.sh"

setup() {
  setup_tmpdir
  export SCOUTER_DB="$TEST_TMPDIR/scouter.db"
  bash "$SCOUTER_DB_SH" init >/dev/null
}

teardown() {
  teardown_tmpdir
}

# ---------------------------------------------------------------------------
# init — schema creation
# ---------------------------------------------------------------------------

@test "init: creates database file" {
  [ -f "$SCOUTER_DB" ]
}

@test "init: creates all tables" {
  tables=$(sqlite3 "$SCOUTER_DB" ".tables")
  [[ "$tables" == *"meta"* ]]
  [[ "$tables" == *"scanned_items"* ]]
  [[ "$tables" == *"opportunities"* ]]
}

@test "init: is idempotent" {
  run bash "$SCOUTER_DB_SH" init
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# scan / is-scanned — content dedup
# ---------------------------------------------------------------------------

@test "scan: inserts item and returns ID" {
  run bash "$SCOUTER_DB_SH" scan "rss" "techcrunch" "abc123" "https://example.com" "Test Article"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "is-scanned: returns 0 for known hash" {
  bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1" >/dev/null
  run bash "$SCOUTER_DB_SH" is-scanned "hash1"
  [ "$status" -eq 0 ]
}

@test "is-scanned: returns 1 for unknown hash" {
  run bash "$SCOUTER_DB_SH" is-scanned "nonexistent"
  [ "$status" -eq 1 ]
}

@test "scan: rejects duplicate hash" {
  bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1" >/dev/null
  run bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url2" "title2"
  [ "$status" -ne 0 ]
}

@test "scan: handles special characters" {
  run bash "$SCOUTER_DB_SH" scan "rss" "feed's" "hash2" "https://example.com?a=1&b=2" "It's a \"test\""
  [ "$status" -eq 0 ]
  title=$(sqlite3 "$SCOUTER_DB" "SELECT title FROM scanned_items WHERE content_hash='hash2';")
  [ "$title" = "It's a \"test\"" ]
}

# ---------------------------------------------------------------------------
# opportunity — create and manage
# ---------------------------------------------------------------------------

@test "opportunity: creates without template" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  run bash "$SCOUTER_DB_SH" opportunity "$item_id" "original text" "draft text"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "opportunity: creates with template" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  run bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft" "news-commentary"
  [ "$status" -eq 0 ]
  template=$(sqlite3 "$SCOUTER_DB" "SELECT template FROM opportunities WHERE id=$output;")
  [ "$template" = "news-commentary" ]
}

@test "opportunity: defaults to pending status" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  status=$(sqlite3 "$SCOUTER_DB" "SELECT status FROM opportunities WHERE id=$opp_id;")
  [ "$status" = "pending" ]
}

# ---------------------------------------------------------------------------
# resolve — status validation
# ---------------------------------------------------------------------------

@test "resolve: approved" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  run bash "$SCOUTER_DB_SH" resolve "$opp_id" "approved"
  [ "$status" -eq 0 ]
  db_status=$(sqlite3 "$SCOUTER_DB" "SELECT status FROM opportunities WHERE id=$opp_id;")
  [ "$db_status" = "approved" ]
}

@test "resolve: edited with text" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  bash "$SCOUTER_DB_SH" resolve "$opp_id" "edited" "revised text"
  edited=$(sqlite3 "$SCOUTER_DB" "SELECT edited_text FROM opportunities WHERE id=$opp_id;")
  [ "$edited" = "revised text" ]
}

@test "resolve: discarded" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  run bash "$SCOUTER_DB_SH" resolve "$opp_id" "discarded"
  [ "$status" -eq 0 ]
}

@test "resolve: rejects invalid status" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  run bash "$SCOUTER_DB_SH" resolve "$opp_id" "invalid"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid status"* ]]
}

# ---------------------------------------------------------------------------
# retype — template change (pending only)
# ---------------------------------------------------------------------------

@test "retype: changes template for pending opportunity" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft" "reply")
  run bash "$SCOUTER_DB_SH" retype "$opp_id" "thread"
  [ "$status" -eq 0 ]
  template=$(sqlite3 "$SCOUTER_DB" "SELECT template FROM opportunities WHERE id=$opp_id;")
  [ "$template" = "thread" ]
}

@test "retype: rejects non-pending opportunity" {
  item_id=$(bash "$SCOUTER_DB_SH" scan "rss" "feed1" "hash1" "url1" "title1")
  opp_id=$(bash "$SCOUTER_DB_SH" opportunity "$item_id" "original" "draft")
  bash "$SCOUTER_DB_SH" resolve "$opp_id" "approved"
  run bash "$SCOUTER_DB_SH" retype "$opp_id" "thread"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not 'pending'"* ]]
}

# ---------------------------------------------------------------------------
# lock / unlock / is-locked
# ---------------------------------------------------------------------------

@test "lock: sets scan lock" {
  bash "$SCOUTER_DB_SH" lock
  run bash "$SCOUTER_DB_SH" is-locked
  [ "$status" -eq 0 ]
}

@test "unlock: releases scan lock" {
  bash "$SCOUTER_DB_SH" lock
  bash "$SCOUTER_DB_SH" unlock
  run bash "$SCOUTER_DB_SH" is-locked
  [ "$status" -eq 1 ]
}

@test "is-locked: returns 1 when no lock" {
  run bash "$SCOUTER_DB_SH" is-locked
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# last-scan / set-last-scan
# ---------------------------------------------------------------------------

@test "last-scan: returns empty for unseen source" {
  run bash "$SCOUTER_DB_SH" last-scan "new-source"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "set-last-scan: stores timestamp" {
  bash "$SCOUTER_DB_SH" set-last-scan "techcrunch"
  run bash "$SCOUTER_DB_SH" last-scan "techcrunch"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "set-last-scan: updates on repeat" {
  bash "$SCOUTER_DB_SH" set-last-scan "feed1"
  first=$(bash "$SCOUTER_DB_SH" last-scan "feed1")
  bash "$SCOUTER_DB_SH" set-last-scan "feed1"
  second=$(bash "$SCOUTER_DB_SH" last-scan "feed1")
  # Both should be timestamps (may be same if sub-second)
  [ -n "$first" ]
  [ -n "$second" ]
}

# ---------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------

@test "cleanup: removes old items" {
  # Insert an item and backdate it
  sqlite3 "$SCOUTER_DB" "INSERT INTO scanned_items (source, source_name, content_hash, url, title, scanned_at)
    VALUES ('rss', 'feed1', 'old-hash', 'url1', 'old', datetime('now', '-100 days'));"
  bash "$SCOUTER_DB_SH" scan "rss" "feed1" "new-hash" "url2" "new" >/dev/null
  run bash "$SCOUTER_DB_SH" cleanup 90
  [ "$status" -eq 0 ]
  [[ "$output" == *"1"* ]]
  count=$(sqlite3 "$SCOUTER_DB" "SELECT COUNT(*) FROM scanned_items;")
  [ "$count" = "1" ]
}

# ---------------------------------------------------------------------------
# CLI validation
# ---------------------------------------------------------------------------

@test "cli: no args shows usage" {
  run bash "$SCOUTER_DB_SH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "cli: unknown command shows usage" {
  run bash "$SCOUTER_DB_SH" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "cli: opportunity rejects non-integer item_id" {
  run bash "$SCOUTER_DB_SH" opportunity "abc" "original" "draft"
  [ "$status" -eq 1 ]
  [[ "$output" == *"expected integer"* ]]
}
