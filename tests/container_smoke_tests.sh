#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
RUN_DIR="$(create_result_dir tests container-smoke)"
exec > >(tee "$RUN_DIR/test-output.log") 2>&1
SUFFIX="${GITHUB_RUN_ID:-$$}"
export AIRPLANE_CONTAINER_NAME="airplane-container-smoke-$SUFFIX"
export AIRPLANE_IMAGE="airplane-reservation:smoke-$SUFFIX"
export RUNTIME=container
PASS_COUNT=0

container() { bash "$ROOT_DIR/scripts/container.sh" "$@"; }
cleanup() { container stop >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

fail() {
  echo "[FAIL] $*" >&2
  container logs --tail=80 >&2 || true
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

start_experiment() {
  local experiment="$1" workers="${2:-}"
  cleanup
  if [ -n "$workers" ]; then
    container start "$experiment" "$workers" || fail "$experiment $workers server did not become ready"
  else
    container start "$experiment" || fail "$experiment server did not become ready"
  fi
  [ "$(container status)" = true ] || fail "$experiment server is not running"
  [ "$(container mode)" = "$experiment" ] || fail "$experiment label is incorrect"
  if [ -n "$workers" ]; then
    [ "$(container workers)" = "$workers" ] || fail "$experiment worker count is incorrect"
  fi
}

count_winners() {
  grep -Ec '^\[CLIENT-[0-9]+\] SUCCESS: Seat 10 reserved$' || true
}

container build
start_experiment sequential
output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
[ "$(printf '%s\n' "$output" | count_winners)" = 1 ] ||
  fail "sequential mode should have exactly one winner"
[[ "$output" == *"Successful reservations: 1/5"* ]] ||
  fail "concurrent report should identify the single sequential winner"
[[ "$output" == *"Report saved in:"* ]] ||
  fail "concurrent report path was not printed"
pass "sequential single-container configuration"

race_observed=false
for _ in 1 2 3; do
  start_experiment nosync
  output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
  if [ "$(printf '%s\n' "$output" | count_winners)" -gt 1 ]; then
    race_observed=true
    break
  fi
done
[ "$race_observed" = true ] || fail "nosync mode did not expose a race after three attempts"
pass "unsynchronized workers expose concurrent winners"

start_experiment sync
output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
[ "$(printf '%s\n' "$output" | count_winners)" = 1 ] ||
  fail "synchronized mode should have exactly one winner"
pass "synchronized single-container configuration"

start_experiment sync 5
output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
[ "$(printf '%s\n' "$output" | count_winners)" = 1 ] ||
  fail "custom synchronized worker count should have exactly one winner"
[[ "$output" == *"Workers: 5"* ]] ||
  fail "concurrent report should record custom worker count"
demo_output="$(bash "$ROOT_DIR/scripts/demo1.sh")"
[[ "$demo_output" == *"Successful cancellations: 5/5"* ]] ||
  fail "Demo 1 should work with a custom worker count"
pass "custom worker count works with both demo scripts"

command_output="$(
  printf 'STATUS 1\nRESERVE 1 2\nSTATUS 1\nCANCEL 1 2\nSTATUS 1\nQUIT\n' |
    container exec -i ./client 1
)"
for expected in \
  "Seat 1 is AVAILABLE" \
  "SUCCESS: Seat 1 reserved" \
  "SUCCESS: Seat 2 reserved" \
  "Seat 1 is RESERVED by Client-1" \
  "SUCCESS: Seat 1 cancelled" \
  "SUCCESS: Seat 2 cancelled" \
  "GOODBYE"; do
  [[ "$command_output" == *"$expected"* ]] || fail "client flow missed: $expected"
done
pass "client command lifecycle"

load_output="$(container exec ./load_test 1000 20 STATUS)"
for expected in "Completed       : 1000" "Transport Fail  : 0" "Throughput"; do
  [[ "$load_output" == *"$expected"* ]] || fail "load test missed: $expected"
done
pass "load test and throughput"

demo_output="$(bash "$ROOT_DIR/scripts/demo1.sh")"
[[ "$demo_output" == *"all five clients reserved and cancelled"* ]] ||
  fail "Demo 1 did not complete successfully"
[[ "$demo_output" == *"Successful reservations: 5/5"* ]] ||
  fail "Demo 1 report should show five successful reservations"
[[ "$demo_output" == *"Successful cancellations: 5/5"* ]] ||
  fail "Demo 1 report should show five successful cancellations"
pass "Demo 1 mixed commands"

export AIRPLANE_LOG_MODE=quiet
start_experiment sync
quiet_output="$(container exec ./load_test 1000 20 STATUS)"
[[ "$quiet_output" == *"Operation OK    : 1000"* ]] ||
  fail "quiet benchmark mode should still process requests"
quiet_logs="$(container logs)"
[[ "$quiet_logs" != *"[SEQ "* ]] ||
  fail "quiet benchmark mode should suppress per-request logs"
unset AIRPLANE_LOG_MODE
pass "quiet benchmark mode preserves requests without per-request logs"

echo "Container smoke tests: $PASS_COUNT passed, 0 failed"
