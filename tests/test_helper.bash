#!/usr/bin/env bash
# Shared test helpers for bats tests

PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Create a temp directory for each test
setup_tmpdir() {
  TEST_TMPDIR=$(mktemp -d)
}

teardown_tmpdir() {
  rm -rf "$TEST_TMPDIR"
}
