#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POD_NAME="${POD_NAME:-airplane-reservation}"
PASS_COUNT=0

if [ -n "${KUBECTL:-}" ]; then
  if ! command -v "$KUBECTL" >/dev/null 2>&1 && [ ! -x "$KUBECTL" ]; then
    echo "KUBECTL does not point to an executable: $KUBECTL" >&2
    exit 1
  fi
elif command -v kubectl.exe >/dev/null 2>&1; then
  KUBECTL="kubectl.exe"
elif [ -x "/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" ]; then
  KUBECTL="/c/Program Files/Docker/Docker/resources/bin/kubectl.exe"
elif [ -x "/mnt/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" ]; then
  KUBECTL="/mnt/c/Program Files/Docker/Docker/resources/bin/kubectl.exe"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL="kubectl"
else
  echo "kubectl was not found. Add it to PATH or set KUBECTL." >&2
  exit 1
fi

fail() {
  echo "[FAIL] $*" >&2
  "$KUBECTL" logs "$POD_NAME" -c server --tail=80 >&2 || true
  exit 1
}

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  echo "[PASS] $1"
}

cleanup() {
  if [ "${KEEP_TEST_POD:-0}" != "1" ]; then
    "$KUBECTL" delete pod "$POD_NAME" \
      --ignore-not-found \
      --grace-period=1 >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

kubectl_file_path() {
  local file_path="$1"

  if [[ "$KUBECTL" == *.exe ]]; then
    if command -v wslpath >/dev/null 2>&1; then
      wslpath -w "$file_path"
      return
    fi

    if command -v cygpath >/dev/null 2>&1; then
      cygpath -w "$file_path"
      return
    fi
  fi

  printf '%s\n' "$file_path"
}

apply_manifest() {
  local manifest="$1"
  local manifest_path
  manifest_path="$(kubectl_file_path "$ROOT_DIR/$manifest")"

  "$KUBECTL" delete pod "$POD_NAME" \
    --ignore-not-found \
    --grace-period=1 >/dev/null
  "$KUBECTL" apply -f "$manifest_path" >/dev/null

  if ! "$KUBECTL" wait \
    --for=condition=Ready \
    "pod/$POD_NAME" \
    --timeout=60s >/dev/null; then
    fail "$manifest did not become ready"
  fi

  local ready
  ready="$($KUBECTL get pod "$POD_NAME" -o jsonpath='{.status.containerStatuses[*].ready}')"

  if [ "$ready" != "true true true true true true" ]; then
    fail "$manifest did not start all six containers"
  fi
}

count_client_successes() {
  awk '/\[CLIENT-[0-9]+\] SUCCESS:/{count++} END{print count+0}'
}

run_experiment() {
  local manifest="$1"
  local expected_successes="$2"
  local description="$3"

  apply_manifest "$manifest"

  local output
  output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"

  local successes
  successes="$(printf '%s\n' "$output" | count_client_successes)"

  if [ "$successes" != "$expected_successes" ]; then
    printf '%s\n' "$output" >&2
    fail "$description expected $expected_successes successful clients, got $successes"
  fi

  pass "$description"
}

echo "Running Kubernetes experiment smoke tests"

run_experiment \
  "k8s/pod-sequential.yaml" \
  "1" \
  "sequential manifest"

run_experiment \
  "k8s/pod-sync.yaml" \
  "1" \
  "synchronized manifest"

race_observed=false

for _ in 1 2 3; do
  apply_manifest "k8s/pod.yaml"
  race_output="$(bash "$ROOT_DIR/scripts/concurrent-test.sh")"
  race_successes="$(printf '%s\n' "$race_output" | count_client_successes)"

  if [ "$race_successes" -gt 1 ]; then
    race_observed=true
    break
  fi
done

if [ "$race_observed" != true ]; then
  fail "unsynchronized manifest did not expose a race after three attempts"
fi
pass "unsynchronized manifest race"

echo "Running Kubernetes command and load smoke tests"

apply_manifest "k8s/pod-sync.yaml"

command_output="$($KUBECTL exec "$POD_NAME" -c client-1 -- \
  sh -c "printf 'STATUS 1\nRESERVE 1 2\nSTATUS 1\nCANCEL 1 2\nSTATUS 1\nQUIT\n' | ./client 1")"

for expected in \
  "Seat 1 is AVAILABLE" \
  "SUCCESS: Seat 1 reserved" \
  "SUCCESS: Seat 2 reserved" \
  "Seat 1 is RESERVED by Client-1" \
  "SUCCESS: Seat 1 cancelled" \
  "SUCCESS: Seat 2 cancelled" \
  "GOODBYE"; do
  if [[ "$command_output" != *"$expected"* ]]; then
    fail "Kubernetes command flow is missing: $expected"
  fi
done
pass "Kubernetes command lifecycle"

load_output="$($KUBECTL exec "$POD_NAME" -c client-1 -- \
  ./load_test 1000 20 STATUS)"

for expected in \
  "Completed       : 1000" \
  "Transport Fail  : 0" \
  "Operation OK    : 1000"; do
  if [[ "$load_output" != *"$expected"* ]]; then
    fail "Kubernetes load test is missing: $expected"
  fi
done
pass "Kubernetes STATUS load"

echo "Kubernetes smoke tests: $PASS_COUNT passed, 0 failed"
