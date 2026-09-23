#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
TEST_DIR="$(create_result_dir tests scripts)"
export MOCK_TRACE="$TEST_DIR/compose-calls.log"
export MOCK_FAIL=""
export RUNTIME=compose
mkdir -p "$TEST_DIR/Program Files"
export DOCKER="$TEST_DIR/Program Files/docker"
cp "$ROOT_DIR/tests/fixtures/docker-mock.sh" "$DOCKER"
chmod +x "$DOCKER"
fail() { echo "[FAIL] $*" >&2; exit 1; }

for stage in ps logs stream client-1 client-2 client-3 client-4 client-5; do
  if MOCK_FAIL="$stage" COMPOSE_EXPERIMENT=sync timeout 15s \
    bash "$ROOT_DIR/scripts/concurrent-test.sh" >"$TEST_DIR/failure-$stage.log" 2>&1; then
    fail "script falsely succeeded after $stage failed"
  else
    status=$?
    [ "$status" -ne 124 ] || fail "$stage error cleanup hung"
  fi
  if grep -q 'Concurrent reservation test finished' "$TEST_DIR/failure-$stage.log"; then
    fail "script printed success after $stage failed"
  fi
  echo "[PASS] script propagates Compose $stage failures"
done

grep -q -- '-f .*compose/compose.yaml' "$MOCK_TRACE" ||
  fail "Compose wrapper did not select the base configuration"
grep -q -- '-f .*compose/compose.sync.yaml' "$MOCK_TRACE" ||
  fail "Compose wrapper did not select the synchronized overlay"
echo "[PASS] Compose arguments survive an executable path containing spaces"

if COMPOSE_EXPERIMENT=unknown bash "$ROOT_DIR/scripts/compose.sh" version \
  >"$TEST_DIR/invalid-experiment.log" 2>&1; then
  fail "unknown experiment was accepted"
fi
grep -q 'Unknown COMPOSE_EXPERIMENT' "$TEST_DIR/invalid-experiment.log" ||
  fail "unknown experiment error was unclear"
echo "[PASS] unknown experiment is rejected"

find "$RESULTS_DIR/demos/concurrent" -name summary.txt -exec grep -H 'exit_code=' {} + >"$TEST_DIR/summaries.log"
grep -Eq 'exit_code=[1-9]' "$TEST_DIR/summaries.log" ||
  fail "failure evidence is missing"

concurrent_output="$(COMPOSE_EXPERIMENT=sync MOCK_RESERVE_FAIL_CLIENT=client-2 bash "$ROOT_DIR/scripts/concurrent-test.sh")"
concurrent_report="$(sed -n 's/^Report saved in: //p' <<<"$concurrent_output" | tail -n 1)"
[ -f "$concurrent_report" ] || fail "concurrent reservation report was not saved"
grep -q 'client-1.*SUCCESS (Seat 10)' "$concurrent_report" ||
  fail "concurrent report is missing per-client reservation results"
grep -q 'client-2.*FAILED: Transaction cancelled because Seat 10 is already reserved' "$concurrent_report" ||
  fail "concurrent report is missing the losing client's failure reason"
grep -q 'Successful reservations: 4/5' "$concurrent_report" ||
  fail "concurrent report summary is incorrect for the simulated contention"
echo "[PASS] concurrent reservation report is saved with per-client results"

demo_output="$(bash "$ROOT_DIR/scripts/demo1.sh")"
demo_report="$(sed -n 's/^Report saved in: //p' <<<"$demo_output" | tail -n 1)"
[ -f "$demo_report" ] || fail "Demo 1 reservation report was not saved"
grep -q 'Successful reservations: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing reservation totals"
grep -q 'Successful cancellations: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing cancellation totals"
echo "[PASS] Demo 1 report includes reservation and cancellation totals"
echo "Script tests: 12 passed, 0 failed (mock Docker Compose transport)"
