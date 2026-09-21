#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
TEST_TMP_DIR="$(mktemp -d "$RESULTS_DIR/tests-XXXXXXXX")"
echo "Test evidence: $TEST_TMP_DIR"
SERVER_PID=""
SERVER_LOG=""
SERVER_START_COUNT=0
PASS_COUNT=0

fail() {
  echo "[FAIL] $*" >&2

  if [ -n "$SERVER_LOG" ] && [ -f "$SERVER_LOG" ]; then
    echo "--- server log ---" >&2
    tail -n 80 "$SERVER_LOG" >&2 || true
  fi

  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

assert_contains() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  if [[ "$actual" != *"$expected"* ]]; then
    fail "$description (missing: $expected)"
  fi
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local description="$3"

  if [ "$actual" != "$expected" ]; then
    fail "$description (expected $expected, got $actual)"
  fi
}

stop_server() {
  if [ -z "$SERVER_PID" ]; then
    return
  fi

  if kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true

    for _ in $(seq 1 50); do
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        break
      fi
      sleep 0.02
    done

    if kill -0 "$SERVER_PID" 2>/dev/null; then
      kill -KILL "$SERVER_PID" 2>/dev/null || true
    fi
  fi

  wait "$SERVER_PID" 2>/dev/null || true
  SERVER_PID=""
}

cleanup() {
  stop_server
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_client() {
  local client_id="$1"
  local commands="$2"

  local record
  record="$(mktemp "$TEST_TMP_DIR/client-$client_id-XXXXXXXX.txt")"
  printf '%s' "$commands" >"$record.commands.txt"
  printf '%s' "$commands" | "$ROOT_DIR/client" "$client_id" 2>&1 | tee "$record"
}

start_server() {
  local mode="$1"
  local workers="$2"

  stop_server
  SERVER_START_COUNT=$((SERVER_START_COUNT + 1))
  SERVER_LOG="$TEST_TMP_DIR/server-$SERVER_START_COUNT.txt"

  "$ROOT_DIR/server" "$mode" "$workers" >"$SERVER_LOG" 2>&1 &
  SERVER_PID=$!

  for _ in $(seq 1 100); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      fail "server exited before becoming ready"
    fi

    if run_client 90000 $'STATUS 20\nQUIT\n' >/dev/null 2>&1; then
      return
    fi

    sleep 0.02
  done

  fail "server did not become ready"
}

expect_failure() {
  local description="$1"
  shift
  local record
  record="$(mktemp "$TEST_TMP_DIR/expected-failure-XXXXXXXX.txt")"
  printf '%s\n' "$description" >"$record"
  if "$@" >>"$record" 2>&1; then
    fail "$description should return a non-zero status"
  fi

  pass "$description"
}

run_load_test() {
  local description="$1"
  shift
  local output_file
  output_file="$(mktemp "$TEST_TMP_DIR/load-XXXXXXXX.txt")"

  if ! timeout 30s "$ROOT_DIR/load_test" "$@" >"$output_file" 2>&1; then
    cat "$output_file" >&2 || true
    fail "$description did not complete successfully within 30 seconds"
  fi

  cat "$output_file"
}

run_concurrent_reserve() {
  local seat_id="$1"
  local output_dir="$TEST_TMP_DIR/concurrent-$SERVER_START_COUNT"
  local pids=()

  mkdir -p "$output_dir"

  for client_id in 1 2 3 4 5; do
    (
      run_client "$client_id" "RESERVE $seat_id"$'\n' \
        >"$output_dir/client-$client_id.txt" 2>&1
    ) &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      fail "concurrent client process failed"
    fi
  done

  cat "$output_dir"/*.txt
}

count_successes() {
  awk '/^SUCCESS:/{count++} END{print count+0}'
}
