#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
TEST_DIR="$(create_result_dir tests scripts)"
export MOCK_TRACE="$TEST_DIR/docker-calls.log"
export MOCK_FAIL=""
export RUNTIME=container
mkdir -p "$TEST_DIR/Program Files"
export DOCKER="$TEST_DIR/Program Files/docker"
cp "$ROOT_DIR/tests/fixtures/docker-mock.sh" "$DOCKER"
chmod +x "$DOCKER"
fail() { echo "[FAIL] $*" >&2; exit 1; }

for stage in status logs stream client-1 client-2 client-3 client-4 client-5; do
  if MOCK_FAIL="$stage" timeout 15s \
    bash "$ROOT_DIR/scripts/concurrent-test.sh" >"$TEST_DIR/failure-$stage.log" 2>&1; then
    fail "script falsely succeeded after $stage failed"
  else
    status=$?
    [ "$status" -ne 124 ] || fail "$stage error cleanup hung"
  fi
  if grep -q 'Concurrent reservation test finished' "$TEST_DIR/failure-$stage.log"; then
    fail "script printed success after $stage failed"
  fi
  echo "[PASS] script propagates Docker $stage failures"
done

bash "$ROOT_DIR/scripts/container.sh" build >/dev/null
bash "$ROOT_DIR/scripts/container.sh" start sync >/dev/null
grep -q '^build -t airplane-reservation:latest ' "$MOCK_TRACE" ||
  fail "Docker image build did not preserve arguments"
grep -q -- 'airplane-reservation:latest ./server sync 3' "$MOCK_TRACE" ||
  fail "Docker run did not select the synchronized experiment"
if grep -q '^compose ' "$MOCK_TRACE"; then
  fail "obsolete Compose command was called"
fi
echo "[PASS] Docker commands survive an executable path containing spaces"

if bash "$ROOT_DIR/scripts/container.sh" start unknown \
  >"$TEST_DIR/invalid-experiment.log" 2>&1; then
  fail "unknown experiment was accepted"
fi
grep -q 'Unknown experiment' "$TEST_DIR/invalid-experiment.log" ||
  fail "unknown experiment error was unclear"
echo "[PASS] unknown experiment is rejected"

bash "$ROOT_DIR/scripts/container.sh" start sync 5 >/dev/null
bash "$ROOT_DIR/scripts/container.sh" start nosync 64 >/dev/null
grep -q -- 'airplane-reservation:latest ./server sync 5' "$MOCK_TRACE" ||
  fail "custom synchronized worker count was not passed to Docker"
grep -q -- 'airplane-reservation:latest ./server nosync 64' "$MOCK_TRACE" ||
  fail "custom unsynchronized worker count was not passed to Docker"
for args in 'sync 0' 'sync 65' 'sync abc' 'sequential 5'; do
  if bash "$ROOT_DIR/scripts/container.sh" start $args >"$TEST_DIR/invalid-workers.log" 2>&1; then
    fail "invalid worker configuration was accepted: $args"
  fi
done
echo "[PASS] custom worker counts are validated and passed to Docker"

for configuration in \
  'sync 1 sequential 1' \
  'sync 5 sync 5' \
  'nosync 64 nosync 64'; do
  read -r server_mode count expected_mode expected_count <<<"$configuration"
  export MOCK_SERVER_COMMAND="[\"./server\",\"$server_mode\",\"$count\"]"
  [ "$(bash "$ROOT_DIR/scripts/container.sh" mode)" = "$expected_mode" ] ||
    fail "incorrect experiment for $server_mode $count"
  [ "$(bash "$ROOT_DIR/scripts/container.sh" workers)" = "$expected_count" ] ||
    fail "incorrect worker count for $server_mode $count"
done
export MOCK_SERVER_COMMAND='["./server","sync","5"]'
echo "[PASS] running server configuration accepts arbitrary worker counts"

find "$RESULTS_DIR/demos/concurrent" -name summary.txt -exec grep -H 'exit_code=' {} + >"$TEST_DIR/summaries.log"
grep -Eq 'exit_code=[1-9]' "$TEST_DIR/summaries.log" ||
  fail "failure evidence is missing"

concurrent_output="$(MOCK_RESERVE_FAIL_CLIENT=client-2 bash "$ROOT_DIR/scripts/concurrent-test.sh")"
concurrent_report="$(sed -n 's/^Report saved in: //p' <<<"$concurrent_output" | tail -n 1)"
[ -f "$concurrent_report" ] || fail "concurrent reservation report was not saved"
grep -q 'client-1.*SUCCESS (Seat 10)' "$concurrent_report" ||
  fail "concurrent report is missing per-client reservation results"
grep -q 'client-2.*FAILED: Transaction cancelled because Seat 10 is already reserved' "$concurrent_report" ||
  fail "concurrent report is missing the losing client's failure reason"
grep -q 'Successful reservations: 4/5' "$concurrent_report" ||
  fail "concurrent report summary is incorrect for the simulated contention"
grep -q '^Workers: 5$' "$concurrent_report" ||
  fail "concurrent report did not record the running worker count"
echo "[PASS] concurrent reservation report is saved with per-client results"

demo_output="$(bash "$ROOT_DIR/scripts/demo1.sh")"
demo_report="$(sed -n 's/^Report saved in: //p' <<<"$demo_output" | tail -n 1)"
[ -f "$demo_report" ] || fail "Demo 1 reservation report was not saved"
grep -q 'Successful reservations: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing reservation totals"
grep -q 'Successful cancellations: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing cancellation totals"
grep -q '^Workers: 5$' "$demo_report" ||
  fail "Demo 1 report did not record the running worker count"
echo "[PASS] Demo 1 report includes reservation and cancellation totals"
echo "Script tests: 14 passed, 0 failed (mock Docker transport)"
