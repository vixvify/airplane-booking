#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_DIR="$(mktemp -d)"
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

  if [[ "$TEST_TMP_DIR" == /tmp/* ]] && [ -d "$TEST_TMP_DIR" ]; then
    rm -rf -- "$TEST_TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

run_client() {
  local client_id="$1"
  local commands="$2"

  printf '%s' "$commands" | "$ROOT_DIR/client" "$client_id"
}

start_server() {
  local mode="$1"
  local workers="$2"

  stop_server
  SERVER_START_COUNT=$((SERVER_START_COUNT + 1))
  SERVER_LOG="$TEST_TMP_DIR/server-$SERVER_START_COUNT.log"

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

  if "$@" >"$TEST_TMP_DIR/expected-failure.log" 2>&1; then
    fail "$description should return a non-zero status"
  fi

  pass "$description"
}

run_load_test() {
  local description="$1"
  shift
  local output_file="$TEST_TMP_DIR/load-test.out"

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
        >"$output_dir/client-$client_id.out" 2>&1
    ) &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      fail "concurrent client process failed"
    fi
  done

  cat "$output_dir"/*.out
}

count_successes() {
  awk '/^SUCCESS:/{count++} END{print count+0}'
}

echo "Running command-line validation tests"

expect_failure "server rejects an invalid mode" "$ROOT_DIR/server" invalid 3
expect_failure "server rejects zero workers" "$ROOT_DIR/server" sync 0
expect_failure "server rejects a non-numeric worker count" "$ROOT_DIR/server" sync abc
expect_failure "server rejects extra arguments" "$ROOT_DIR/server" sync 3 extra

expect_failure "client requires an id" "$ROOT_DIR/client"
expect_failure "client rejects zero id" "$ROOT_DIR/client" 0
expect_failure "client rejects a negative id" "$ROOT_DIR/client" -1
expect_failure "client rejects a non-numeric id" "$ROOT_DIR/client" abc

expect_failure "load test requires arguments" "$ROOT_DIR/load_test"
expect_failure "load test rejects zero requests" "$ROOT_DIR/load_test" 0 1 STATUS
expect_failure "load test rejects zero concurrency" "$ROOT_DIR/load_test" 1 0 STATUS
expect_failure "load test rejects an unknown operation" "$ROOT_DIR/load_test" 1 1 UNKNOWN
expect_failure "load test rejects an invalid seat" "$ROOT_DIR/load_test" 1 1 STATUS 21
expect_failure "load test rejects extra arguments" "$ROOT_DIR/load_test" 1 1 STATUS 1 extra

echo "Running command and state transition tests"

start_server sync 3

basic_output="$(run_client 1 $'STATUS 1\nRESERVE 1 2\nSTATUS 1\nLIST\nCANCEL 1 2\nSTATUS 1\nQUIT\n')"
assert_contains "$basic_output" "Seat 1 is AVAILABLE" "STATUS should report an available seat"
assert_contains "$basic_output" "SUCCESS: Seat 1 reserved" "RESERVE should reserve the first seat"
assert_contains "$basic_output" "SUCCESS: Seat 2 reserved" "RESERVE should reserve the second seat"
assert_contains "$basic_output" "Seat 1 is RESERVED by Client-1" "STATUS should report the owner"
assert_contains "$basic_output" "===== Airplane Seat Map =====" "LIST should return the seat map"
assert_contains "$basic_output" "SUCCESS: Seat 1 cancelled" "CANCEL should release the first seat"
assert_contains "$basic_output" "SUCCESS: Seat 2 cancelled" "CANCEL should release the second seat"
assert_contains "$basic_output" "GOODBYE" "QUIT should return GOODBYE"
pass "LIST, STATUS, RESERVE, CANCEL, and QUIT lifecycle"

validation_output="$(run_client 2 $'UNKNOWN\nSTATUS\nSTATUS 1 extra\nSTATUS x\nSTATUS 0\nSTATUS 21\nRESERVE\nRESERVE 1 x\nRESERVE 0\nCANCEL\nCANCEL 1 x\nCANCEL 21\nLIST extra\nQUIT extra\nQUIT\n')"
assert_contains "$validation_output" "ERROR: Unknown command" "unknown commands should fail"
assert_contains "$validation_output" "Usage: STATUS <seat_id>" "malformed STATUS should show usage"
assert_contains "$validation_output" "ERROR: Invalid seat number" "out-of-range STATUS should fail"
assert_contains "$validation_output" "Usage: RESERVE <seat_id> [seat_id...]" "malformed RESERVE should show usage"
assert_contains "$validation_output" "ERROR: Invalid seat 0" "out-of-range RESERVE should fail"
assert_contains "$validation_output" "Usage: CANCEL <seat_id> [seat_id...]" "malformed CANCEL should show usage"
assert_contains "$validation_output" "ERROR: Invalid seat 21" "out-of-range CANCEL should fail"
assert_contains "$validation_output" "Usage: LIST" "LIST should reject extra arguments"
assert_contains "$validation_output" "Usage: QUIT" "QUIT should reject extra arguments"
pass "command parsing and validation"

echo "Running transaction tests through the message queue"

for mode in sync nosync; do
  start_server "$mode" 1

  run_client 20 $'RESERVE 2\n' >/dev/null
  reserve_output="$(run_client 10 $'RESERVE 1 2 3\nSTATUS 1\nSTATUS 2\nSTATUS 3\n')"
  assert_contains "$reserve_output" "FAILED: Transaction cancelled" "$mode multi-seat reserve should fail atomically"
  assert_contains "$reserve_output" "Seat 1 is AVAILABLE" "$mode reserve rollback should leave Seat 1 available"
  assert_contains "$reserve_output" "Seat 2 is RESERVED by Client-20" "$mode reserve rollback should preserve Seat 2"
  assert_contains "$reserve_output" "Seat 3 is AVAILABLE" "$mode reserve rollback should leave Seat 3 available"

  run_client 10 $'RESERVE 4 5\n' >/dev/null
  cancel_output="$(run_client 10 $'CANCEL 4 6\nSTATUS 4\nSTATUS 5\n')"
  assert_contains "$cancel_output" "FAILED: Transaction cancelled" "$mode multi-seat cancel should fail atomically"
  assert_contains "$cancel_output" "Seat 4 is RESERVED by Client-10" "$mode cancel rollback should preserve Seat 4"
  assert_contains "$cancel_output" "Seat 5 is RESERVED by Client-10" "$mode cancel rollback should preserve Seat 5"

  owner_output="$(run_client 10 $'CANCEL 2\nSTATUS 2\n')"
  assert_contains "$owner_output" "FAILED: Transaction cancelled" "$mode should reject cancellation by another client"
  assert_contains "$owner_output" "Seat 2 is RESERVED by Client-20" "$mode should preserve the original owner"

  pass "$mode all-or-nothing reserve/cancel transactions"
done

echo "Running sequential and concurrent behavior tests"

start_server sync 1
sequential_output="$(run_concurrent_reserve 10)"
sequential_successes="$(printf '%s\n' "$sequential_output" | count_successes)"
assert_equals "$sequential_successes" "1" "sequential baseline should have exactly one winner"
pass "sequential baseline with five concurrent clients"

start_server sync 3
sync_output="$(run_concurrent_reserve 10)"
sync_successes="$(printf '%s\n' "$sync_output" | count_successes)"
assert_equals "$sync_successes" "1" "synchronized workers should have exactly one winner"
pass "synchronized concurrent reservation"

race_observed=false

for _ in 1 2 3; do
  start_server nosync 3
  nosync_output="$(run_concurrent_reserve 10)"
  nosync_successes="$(printf '%s\n' "$nosync_output" | count_successes)"

  if [ "$nosync_successes" -gt 1 ]; then
    race_observed=true
    break
  fi
done

if [ "$race_observed" != true ]; then
  fail "nosync mode did not expose multiple reported winners after three attempts"
fi
pass "unsynchronized race demonstration"

echo "Running load and queue lifecycle tests"

start_server sync 3
status_load="$(run_load_test "STATUS load test" 1000 50 STATUS)"
assert_contains "$status_load" "Completed       : 1000" "STATUS load should complete every request"
assert_contains "$status_load" "Transport Fail  : 0" "STATUS load should have no transport failures"
assert_contains "$status_load" "Operation OK    : 1000" "STATUS load should succeed"
pass "high-volume STATUS load"

reserve_load="$(run_load_test "fixed-seat RESERVE load test" 100 20 RESERVE 10)"
assert_contains "$reserve_load" "Completed       : 100" "RESERVE load should complete every request"
assert_contains "$reserve_load" "Transport Fail  : 0" "RESERVE load should have no transport failures"
assert_contains "$reserve_load" "Operation OK    : 1" "fixed-seat RESERVE should have one winner"
assert_contains "$reserve_load" "Operation Fail  : 99" "fixed-seat RESERVE should reject the other requests"
pass "fixed-seat RESERVE contention load"

cancel_load="$(run_load_test "fixed-seat CANCEL load test" 100 20 CANCEL 10)"
assert_contains "$cancel_load" "Completed       : 100" "CANCEL load should complete every request"
assert_contains "$cancel_load" "Transport Fail  : 0" "CANCEL load should have no transport failures"
assert_contains "$cancel_load" "Operation OK    : 1" "the owning client should cancel the seat"
assert_contains "$cancel_load" "Operation Fail  : 99" "non-owners should fail to cancel the seat"
pass "fixed-seat CANCEL contention load"

start_server sync 3
round_robin_reserve="$(run_load_test "round-robin RESERVE load test" 20 20 RESERVE)"
assert_contains "$round_robin_reserve" "Operation OK    : 20" "round-robin RESERVE should reserve all seats"

round_robin_cancel="$(run_load_test "round-robin CANCEL load test" 20 20 CANCEL)"
assert_contains "$round_robin_cancel" "Operation OK    : 20" "round-robin CANCEL should release all seats"
pass "round-robin RESERVE and CANCEL load lifecycle"

stop_server
expect_failure "client fails cleanly when the server queue is absent" "$ROOT_DIR/client" 1

start_server sync 1
kill -KILL "$SERVER_PID"
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

start_server sync 1
recovery_output="$(run_client 1 $'STATUS 1\nQUIT\n')"
assert_contains "$recovery_output" "Seat 1 is AVAILABLE" "server should replace a stale queue on startup"
pass "stale queue recovery after an unclean shutdown"

stop_server

echo "Integration tests: $PASS_COUNT passed, 0 failed"
