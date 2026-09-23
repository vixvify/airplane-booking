#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
RUN_DIR="$(create_result_dir tests compose-smoke)"
exec > >(tee "$RUN_DIR/test-output.log") 2>&1
PROJECT_SUFFIX="${GITHUB_RUN_ID:-$$}"
export COMPOSE_PROJECT_NAME="airplane-compose-smoke-$PROJECT_SUFFIX"
export RUNTIME=compose
PASS_COUNT=0

cleanup() {
  bash "$ROOT_DIR/scripts/compose.sh" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

fail() {
  echo "[FAIL] $*" >&2
  bash "$ROOT_DIR/scripts/compose.sh" logs --tail=80 server >&2 || true
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

start_experiment() {
  local experiment="$1"
  export COMPOSE_EXPERIMENT="$experiment"
  cleanup
  bash "$ROOT_DIR/scripts/compose.sh" up -d --build --force-recreate

  for _ in $(seq 1 60); do
    if bash "$ROOT_DIR/scripts/compose.sh" logs server 2>/dev/null |
      grep -q "Airplane Reservation Server started"; then
      return
    fi
    sleep 1
  done
  fail "$experiment server did not become ready"
}

count_winners() {
  grep -Ec '^\[CLIENT-[0-9]+\] SUCCESS: Seat 10 reserved$' || true
}

start_experiment sequential
output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
[ "$(printf '%s\n' "$output" | count_winners)" = 1 ] ||
  fail "sequential mode should have exactly one winner"
[[ "$output" == *"Successful reservations: 1/5"* ]] ||
  fail "concurrent report should identify the single sequential winner"
[[ "$output" == *"Report saved in:"* ]] ||
  fail "concurrent report path was not printed"
pass "sequential Compose configuration"

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
pass "unsynchronized Compose configuration exposes concurrent winners"

start_experiment sync
output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
[ "$(printf '%s\n' "$output" | count_winners)" = 1 ] ||
  fail "synchronized mode should have exactly one winner"
pass "synchronized Compose configuration"

command_output="$(
  printf 'STATUS 1\nRESERVE 1 2\nSTATUS 1\nCANCEL 1 2\nSTATUS 1\nQUIT\n' |
    bash "$ROOT_DIR/scripts/compose.sh" exec -T client-1 ./client 1
)"
for expected in \
  "Seat 1 is AVAILABLE" \
  "SUCCESS: Seat 1 reserved" \
  "SUCCESS: Seat 2 reserved" \
  "Seat 1 is RESERVED by Client-1" \
  "SUCCESS: Seat 1 cancelled" \
  "SUCCESS: Seat 2 cancelled" \
  "GOODBYE"; do
  [[ "$command_output" == *"$expected"* ]] || fail "Compose client flow missed: $expected"
done
pass "Compose command lifecycle"

load_output="$(bash "$ROOT_DIR/scripts/compose.sh" exec -T client-1 ./load_test 1000 20 STATUS)"
for expected in "Completed       : 1000" "Transport Fail  : 0" "Throughput"; do
  [[ "$load_output" == *"$expected"* ]] || fail "Compose load test missed: $expected"
done
pass "Compose load test and throughput"

demo_output="$(bash "$ROOT_DIR/scripts/demo1.sh")"
[[ "$demo_output" == *"all five clients reserved and cancelled"* ]] ||
  fail "Demo 1 did not complete successfully"
[[ "$demo_output" == *"Successful reservations: 5/5"* ]] ||
  fail "Demo 1 report should show five successful reservations"
[[ "$demo_output" == *"Successful cancellations: 5/5"* ]] ||
  fail "Demo 1 report should show five successful cancellations"
pass "Compose Demo 1 mixed commands"

echo "Compose smoke tests: $PASS_COUNT passed, 0 failed"
