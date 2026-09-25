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
  if grep -Eq 'Concurrent (LIST|STATUS|RESERVE|CANCEL) test finished' "$TEST_DIR/failure-$stage.log"; then
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

load_output="$(bash "$ROOT_DIR/scripts/load-test.sh" 1000 20 STATUS)"
[[ "$load_output" == *"Load test finished. Results:"* ]] ||
  fail "Bash load-test wrapper did not complete"
load_summary="$(sed -n 's/^Load test finished. Results: //p' <<<"$load_output" | tail -n 1)/summary.txt"
load_report="$(dirname "$load_summary")/report.txt"
load_seat_map="$(dirname "$load_summary")/seat-map.txt"
grep -q '^total_requests=1000$' "$load_summary" ||
  fail "Bash load-test summary is missing total requests"
grep -q '^concurrency=20$' "$load_summary" ||
  fail "Bash load-test summary is missing concurrency"
[ -f "$load_report" ] || fail "Bash load-test report was not saved"
for section in CONFIGURATION RESULTS ARTIFACTS; do
  grep -qx "$section" "$load_report" || fail "Load-test report is missing $section section"
done
grep -q '^Throughput: 12000 req/sec$' "$load_report" ||
  fail "Load-test report is missing the throughput result"
grep -q '^Seat 20 : AVAILABLE$' "$load_seat_map" ||
  fail "Load-test result is missing the final seat map"
echo "[PASS] Bash load-test wrapper saves output and summary"

find "$RESULTS_DIR/demos/concurrent" -name summary.txt -exec grep -H 'exit_code=' {} + >"$TEST_DIR/summaries.log"
grep -Eq 'exit_code=[1-9]' "$TEST_DIR/summaries.log" ||
  fail "failure evidence is missing"

concurrent_output="$(MOCK_RESERVE_FAIL_CLIENT=client-2 bash "$ROOT_DIR/scripts/concurrent-test.sh")"
concurrent_report="$(sed -n 's/^Report saved in: //p' <<<"$concurrent_output" | tail -n 1)"
[ -f "$concurrent_report" ] || fail "concurrent reservation report was not saved"
concurrent_seat_map="$(dirname "$concurrent_report")/seat-map.txt"
concurrent_conflicts="$(dirname "$concurrent_report")/seat-conflicts.txt"
grep -q '^Seat 20 : AVAILABLE$' "$concurrent_seat_map" ||
  fail "concurrent result is missing the final seat map"
for section in CONFIGURATION 'CLIENT RESULTS' SUMMARY ARTIFACTS; do
  grep -qx "$section" "$concurrent_report" || fail "Concurrent report is missing $section section"
done
grep -q 'client-1.*SUCCESS (Seat 10)' "$concurrent_report" ||
  fail "concurrent report is missing per-client reservation results"
grep -q 'client-2.*FAILED: Transaction cancelled because Seat 10 is already reserved' "$concurrent_report" ||
  fail "concurrent report is missing the losing client's failure reason"
grep -q 'Successful reservations: 4/5' "$concurrent_report" ||
  fail "concurrent report summary is incorrect for the simulated contention"
grep -q '^Workers: 5$' "$concurrent_report" ||
  fail "concurrent report did not record the running worker count"
grep -q '^Consistency check: FAILED (1 seat conflict detected)$' "$concurrent_report" ||
  fail "concurrent report did not flag multiple successful reservations"
grep -q '^10|Client-1, Client-3, Client-4, Client-5|unknown$' "$concurrent_conflicts" ||
  fail "concurrent conflict evidence did not preserve all successful clients"
[[ "$concurrent_output" == *"[10:RACE]"* && "$concurrent_output" == *"[FAIL] CONSISTENCY CHECK"* ]] ||
  fail "concurrent console output did not expose the race"
echo "[PASS] concurrent reservation report is saved with per-client results"

custom_output="$(CLIENT_COUNT=7 MOCK_RESERVE_FAIL_CLIENT=client-2 bash "$ROOT_DIR/scripts/concurrent-test.sh")"
custom_report="$(sed -n 's/^Report saved in: //p' <<<"$custom_output" | tail -n 1)"
grep -q 'Successful reservations: 6/7' "$custom_report" ||
  fail "custom concurrent client count was not used in the report"
grep -q 'client-7.*SUCCESS (Seat 10)' "$custom_report" ||
  fail "custom concurrent client was not launched"
echo "[PASS] concurrent test accepts a custom client count"

for command in STATUS LIST CANCEL; do
  command_output="$(COMMAND="$command" bash "$ROOT_DIR/scripts/concurrent-test.sh")"
  command_report="$(sed -n 's/^Report saved in: //p' <<<"$command_output" | tail -n 1)"
  grep -q "^Command: $command$" "$command_report" ||
    fail "$command report did not record the selected command"
  if [ "$command" = CANCEL ]; then
    grep -q '^Successful cancellations: 5/5$' "$command_report" ||
      fail "CANCEL report did not summarize client results"
  else
    grep -q '^Successful commands: 5/5$' "$command_report" ||
      fail "$command report did not summarize client results"
  fi
done
echo "[PASS] concurrent test supports STATUS, LIST, and CANCEL commands"

if COMMAND=DELETE bash "$ROOT_DIR/scripts/concurrent-test.sh" >"$TEST_DIR/invalid-command.log" 2>&1; then
  fail "unsupported concurrent command was accepted"
fi
grep -q 'COMMAND must be LIST, STATUS, RESERVE, or CANCEL' "$TEST_DIR/invalid-command.log" ||
  fail "unsupported command error was unclear"
echo "[PASS] concurrent test rejects unsupported commands"

demo_output="$(MOCK_DEMO_FINAL=1 bash "$ROOT_DIR/scripts/demo1.sh")"
demo_report="$(sed -n 's/^Report saved in: //p' <<<"$demo_output" | tail -n 1)"
[ -f "$demo_report" ] || fail "Demo 1 reservation report was not saved"
grep -q 'Successful seat reservations: 10/10' "$demo_report" ||
  fail "Demo 1 report is missing multi-seat reservation totals"
grep -q 'Successful cancellations: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing cancellation totals"
grep -q 'Seats remaining reserved: 5/5' "$demo_report" ||
  fail "Demo 1 report is missing final reserved-seat totals"
demo_seat_map="$(dirname "$demo_report")/seat-map.txt"
for expected in \
  'Seat 2 : RESERVED by Client-1' \
  'Seat 3 : RESERVED by Client-2' \
  'Seat 6 : RESERVED by Client-3' \
  'Seat 7 : RESERVED by Client-4' \
  'Seat 10 : RESERVED by Client-5'; do
  grep -Fqx "$expected" "$demo_seat_map" || fail "Demo 1 final seat map is missing: $expected"
done
grep -q '^Workers: 5$' "$demo_report" ||
  fail "Demo 1 report did not record the running worker count"
echo "[PASS] Demo 1 report includes reservation and cancellation totals"
echo "Script tests: 18 passed, 0 failed (mock Docker transport)"
