#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/lib/runtime.sh"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
RUN_DIR="$(mktemp -d "$RESULTS_DIR/$DEMO_NAME-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
LOG_PID=""
READER_PID=""
CLIENT_PIDS=()

stop_logs() {
  if [ -n "$LOG_PID" ]; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    LOG_PID=""
  fi
  if [ -n "$READER_PID" ]; then
    wait "$READER_PID" 2>/dev/null || true
    READER_PID=""
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  stop_logs
  for pid in "${CLIENT_PIDS[@]}"; do wait "$pid" 2>/dev/null || true; done
  printf 'exit_code=%s\nfinished_at=%s\n' "$status" "$(date -u +%FT%TZ)" >>"$RUN_DIR/summary.txt"
  if [ "$status" -ne 0 ]; then echo "Test failed; evidence: $RUN_DIR" >&2; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "Evidence: $RUN_DIR"
printf 'demo=%s\nstarted_at=%s\nruntime=%s\npod=%s\ncontainer=%s\n' \
  "$DEMO_NAME" "$STARTED_AT" "${RUNTIME:-k8s}" "${POD_NAME:-airplane-reservation}" \
  "${CONTAINER_NAME:-}" >"$RUN_DIR/summary.txt"
git -C "$ROOT_DIR" rev-parse HEAD >>"$RUN_DIR/summary.txt" 2>/dev/null || true
init_runtime
LOCAL_LOG_START=1
if [ "$RUNTIME" = local ]; then LOCAL_LOG_START=$(( $(wc -c <"$SERVER_LOG") + 1 )); fi
# Fail early if logging itself is unavailable, before issuing mutations.
runtime_log_snapshot >"$RUN_DIR/server.txt" 2>&1
: >"$RUN_DIR/server-live.txt"
runtime_live_logs >"$RUN_DIR/server-live.txt" 2>&1 &
LOG_PID=$!
# Poll a regular file rather than a FIFO (Git Bash on Windows has no mkfifo).
display_logs() {
  local line pending=""
  while true; do
    if IFS= read -r line; then
      printf '[SERVER] %s%s\n' "$pending" "$line"
      pending=""
    else
      pending+="$line"
      if ! kill -0 "$LOG_PID" 2>/dev/null; then
        [ -z "$pending" ] || printf '[SERVER] %s\n' "$pending"
        break
      fi
      sleep 0.05
    fi
  done
}
display_logs <"$RUN_DIR/server-live.txt" &
READER_PID=$!

run_client() {
  local id="$1" commands="$2"
  printf '%s' "$commands" >"$RUN_DIR/client-$id-commands.txt"
  printf '%s' "$commands" | runtime_client "$id" 2>&1 \
    | tee "$RUN_DIR/client-$id.txt" \
    | while IFS= read -r line; do printf '[CLIENT-%s] %s\n' "$id" "$line"; done
}

if [ "$DEMO_NAME" = demo1 ]; then
  echo "Demo 1: five clients, mixed commands (seats 1-5 must be available)."
  printf 'LIST\nQUIT\n' | runtime_client 1 >"$RUN_DIR/preflight.txt"
  for id in 1 2 3 4 5; do
    # Check through STATUS so preconditions do not depend on LIST formatting.
    printf 'STATUS %s\nQUIT\n' "$id" | runtime_client "$id" >"$RUN_DIR/preflight-$id.txt"
    grep -q "Seat $id is AVAILABLE" "$RUN_DIR/preflight-$id.txt" || {
      echo "Seat $id is already reserved; start a fresh server/pod for Demo 1." >&2; exit 1;
    }
  done
  commands=(
    $'LIST\nRESERVE 1\nSTATUS 1\nCANCEL 1\nQUIT\n'
    $'STATUS 2\nRESERVE 2\nCANCEL 2\nSTATUS 2\nQUIT\n'
    $'RESERVE 3\nLIST\nCANCEL 3\nSTATUS 3\nQUIT\n'
    $'RESERVE 4\nSTATUS 4\nCANCEL 4\nLIST\nQUIT\n'
    $'LIST\nRESERVE 5\nCANCEL 5\nSTATUS 5\nQUIT\n'
  )
else
  SEAT_ID="${SEAT_ID:-10}"
  [[ "$SEAT_ID" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo "SEAT_ID must be 1-20" >&2; exit 1; }
  echo "Concurrent reservation test: target seat $SEAT_ID"
  commands=()
  for id in 1 2 3 4 5; do commands+=("RESERVE $SEAT_ID"$'\nQUIT\n'); done
fi

for id in 1 2 3 4 5; do
  run_client "$id" "${commands[id-1]}" &
  CLIENT_PIDS+=("$!")
done
failed=0
for pid in "${CLIENT_PIDS[@]}"; do
  if ! wait "$pid"; then failed=1; fi
done
CLIENT_PIDS=()
if ! kill -0 "$LOG_PID" 2>/dev/null; then
  echo "Live server log stream stopped unexpectedly." >&2
  failed=1
fi
stop_logs
# A final bounded snapshot also captures the last lines if the live stream lagged.
if ! runtime_log_snapshot >"$RUN_DIR/server.txt" 2>&1; then failed=1; fi

for id in 1 2 3 4 5; do
  file="$RUN_DIR/client-$id.txt"
  grep -q '^GOODBYE$' "$file" || failed=1
  if [ "$DEMO_NAME" = demo1 ]; then
    grep -q "^SUCCESS: Seat $id reserved" "$file" || failed=1
    grep -q "^SUCCESS: Seat $id cancelled" "$file" || failed=1
    if grep -Eq '^(FAILED:|ERROR:|Usage:)' "$file"; then failed=1; fi
  fi
done
if [ "$failed" -ne 0 ]; then exit 1; fi

if [ "$DEMO_NAME" = demo1 ]; then
  echo "Demo 1 finished: all five clients reserved and cancelled their own seats."
else
  echo "Concurrent reservation test finished."
  echo "Operation failures are expected under contention; compare winners in client logs."
fi
echo "Saved commands, client output, server logs and summary: $RUN_DIR"
