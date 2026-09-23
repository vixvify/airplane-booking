#!/usr/bin/env bash
set -euo pipefail
TEST_SUITE=regression
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

start_server sync 3
run_client 11 $'RESERVE 1\n' >/dev/null
expect_failure "second server is rejected" "$ROOT_DIR/server" nosync 3
output="$(run_client 11 $'STATUS 1\nCANCEL 1\n')"
assert_contains "$output" "Seat 1 is RESERVED by Client-11" "duplicate server must preserve state"
pass "original server remains responsive with its reservations intact"

for mode in sync nosync; do
  start_server "$mode" 1
  output="$(run_client 1 $'RESERVE 1 99999999999999999999999999999\nSTATUS 1\n')"
  assert_contains "$output" "Usage: RESERVE" "$mode overflow must reject whole command"
  assert_contains "$output" "Seat 1 is AVAILABLE" "$mode overflow must not reserve prefix"
  run_client 1 $'RESERVE 1\n' >/dev/null
  output="$(run_client 1 $'CANCEL 1 99999999999999999999999999999\nSTATUS 1\n')"
  assert_contains "$output" "Usage: CANCEL" "$mode overflow must reject whole cancellation"
  assert_contains "$output" "Seat 1 is RESERVED by Client-1" "$mode overflow must preserve owner"
  pass "$mode integer overflow is rejected atomically"

  printf -v padding '%118s' ''
  output="$(run_client 2 "RESERVE 2${padding}21"$'\nSTATUS 2\nQUIT\n')"
  assert_contains "$output" "ERROR: command must contain at most 127 bytes" "long input must fail locally"
  assert_contains "$output" "Seat 2 is AVAILABLE" "truncated prefix must not execute"
  assert_contains "$output" "GOODBYE" "session must survive invalid input"
  printf -v padding '%119s' ''
  output="$(run_client 2 "STATUS 2${padding}"$'\nQUIT extra\nSTATUS 2\nQUIT\nSTATUS 3\n')"
  assert_equals "$(printf '%s\n' "$output" | grep -c 'Seat 2 is AVAILABLE')" "2" "127-byte input and STATUS after invalid QUIT"
  assert_contains "$output" "Usage: QUIT" "invalid QUIT must be rejected"
  [[ "$output" != *"Seat 3 is"* ]] || fail "valid QUIT must end the session"
  pass "$mode command length boundary and invalid QUIT session continuation"
done

start_server sync 3
output="$(run_load_test "queue saturation regression" 200 200 RESERVE 10)"
assert_contains "$output" "Completed       : 200" "saturated request queue must drain"
assert_contains "$output" "Transport Fail  : 0" "separate request/response queues must prevent deadlock"
assert_contains "$output" "Operation OK    : 1" "sync load still has exactly one winner"
pass "200 concurrent reservations finish without IPC deadlock"

# Same logical owner in overlapping processes must not consume each other's replies.
run_client 42 $'RESERVE 5\n' >/dev/null
run_client 42 $'STATUS 5\n' >"$TEST_TMP_DIR/same-id-owner.txt" &
first=$!
run_client 42 $'STATUS 6\n' >"$TEST_TMP_DIR/same-id-free.txt" &
second=$!
wait "$first"
wait "$second"
assert_contains "$(cat "$TEST_TMP_DIR/same-id-owner.txt")" "Seat 5 is RESERVED by Client-42" "reply routing for owner"
assert_contains "$(cat "$TEST_TMP_DIR/same-id-free.txt")" "Seat 6 is AVAILABLE" "reply routing for available seat"
pass "request IDs isolate concurrent sessions with the same client ID"

start_server sync 3
demo_output="$(RUNTIME=local SERVER_LOG="$SERVER_LOG" RESULTS_DIR="$RESULTS_DIR" bash "$ROOT_DIR/scripts/demo1.sh")"
assert_contains "$demo_output" "Successful reservations: 5/5" "Demo 1 report should identify all reserved seats"
assert_contains "$demo_output" "Successful cancellations: 5/5" "Demo 1 report should identify all cancellations"
pass "Demo 1 runs five mixed-command clients and validates results"
start_server sync 1
concurrent_output="$(RUNTIME=local SERVER_LOG="$SERVER_LOG" RESULTS_DIR="$RESULTS_DIR" bash "$ROOT_DIR/scripts/concurrent-test.sh")"
assert_contains "$concurrent_output" "Successful reservations: 1/5" "concurrent report should identify its winner"
assert_contains "$concurrent_output" "client-" "concurrent report should list clients"
pass "concurrent test works with local runtime"
stop_server
echo "Regression tests: $PASS_COUNT passed, 0 failed"
