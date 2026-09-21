#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
TEST_DIR="$(mktemp -d "$RESULTS_DIR/scripts-XXXXXXXX")"
export RESULTS_DIR="$TEST_DIR/results"
export MOCK_TRACE="$TEST_DIR/kubectl-calls.txt"
export MOCK_STATE="$TEST_DIR/manifest.txt"
mkdir -p "$TEST_DIR/Program Files"
export KUBECTL="$TEST_DIR/Program Files/kubectl"
cp "$ROOT_DIR/tests/fixtures/kubectl-mock.sh" "$KUBECTL"
chmod +x "$KUBECTL"
echo "k8s/pod-sync.yaml" >"$MOCK_STATE"
fail() { echo "[FAIL] $*" >&2; exit 1; }

for stage in get logs stream client-1 client-2 client-3 client-4 client-5; do
  if MOCK_FAIL="$stage" timeout 15s bash "$ROOT_DIR/scripts/concurrent-test.sh" >"$TEST_DIR/failure-$stage.txt" 2>&1; then
    fail "script falsely succeeded after $stage failed"
  else
    status=$?
    [ "$status" -ne 124 ] || fail "$stage error cleanup hung"
  fi
  if grep -q 'Concurrent reservation test finished' "$TEST_DIR/failure-$stage.txt"; then
    fail "script printed success after $stage failed"
  fi
  echo "[PASS] script propagates $stage failures"
done

# Run the entire smoke script via an executable whose path contains spaces.
timeout 30s bash "$ROOT_DIR/tests/k8s_smoke_tests.sh" >"$TEST_DIR/smoke.txt" 2>&1 || {
  cat "$TEST_DIR/smoke.txt"; fail "Kubernetes smoke quoting regression";
}
grep -q '5 passed, 0 failed' "$TEST_DIR/smoke.txt" || fail "smoke script missed scenarios"
grep -q 'get pod .*jsonpath' "$MOCK_TRACE" || fail "ready check not exercised"
grep -q './load_test' "$MOCK_TRACE" || fail "load command not exercised"
echo "[PASS] all smoke invocations quote executable paths with spaces"

# Runtime failure must also survive the printf/client/tee/prefix pipeline.
if KUBECTL=/bin/false timeout 10s bash "$ROOT_DIR/scripts/concurrent-test.sh" >"$TEST_DIR/false.txt" 2>&1; then
  fail "/bin/false must not produce success"
fi
echo "[PASS] unavailable Kubernetes does not report a successful experiment"

find "$RESULTS_DIR" -name summary.txt -exec grep -H 'exit_code=' {} + >"$TEST_DIR/summaries.txt"
grep -q 'exit_code=0' "$TEST_DIR/summaries.txt" || fail "successful evidence missing"
grep -Eq 'exit_code=[1-9]' "$TEST_DIR/summaries.txt" || fail "failure evidence missing"
echo "[PASS] evidence records both successful and failed runs"
echo "Script tests: 11 passed, 0 failed (mock transport; not a real Kubernetes deployment)"
