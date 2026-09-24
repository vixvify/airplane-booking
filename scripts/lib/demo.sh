#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT_DIR/scripts/lib/runtime.sh"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
source "$ROOT_DIR/scripts/lib/terminal_ui.sh"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
RUN_DIR="$(create_result_dir demos "$DEMO_NAME")"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
LOG_PID=""
READER_PID=""
CLIENT_PIDS=()
CONFLICT_COUNT=0

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
  if [ "$status" -ne 0 ]; then ui_error "Test failed. Evidence: $RUN_DIR"; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

init_runtime
if [ "$DEMO_NAME" = demo1 ]; then
  CLIENT_COUNT=5
  COMMAND=mixed
  SEAT_ID=various
else
  CLIENT_COUNT="${CLIENT_COUNT:-5}"
  [[ "$CLIENT_COUNT" =~ ^[0-9]+$ ]] && [ "$CLIENT_COUNT" -ge 5 ] && [ "$CLIENT_COUNT" -le 100 ] || {
    echo "CLIENT_COUNT must be between 5 and 100" >&2
    exit 1
  }
  COMMAND="${COMMAND:-RESERVE}"
  case "$COMMAND" in
    LIST|STATUS|RESERVE|CANCEL) ;;
    *) echo "COMMAND must be LIST, STATUS, RESERVE, or CANCEL" >&2; exit 1 ;;
  esac
  SEAT_ID="${SEAT_ID:-10}"
  [[ "$SEAT_ID" =~ ^([1-9]|1[0-9]|20)$ ]] || { echo "SEAT_ID must be 1-20" >&2; exit 1; }
fi
printf 'demo=%s\nstarted_at=%s\nruntime=%s\nexperiment=%s\nworkers=%s\nclients=%s\ncommand=%s\ntarget_seat=%s\ncontainer=%s\n' \
  "$DEMO_NAME" "$STARTED_AT" "$RUNTIME" "$EXPERIMENT" "${WORKER_COUNT:-unknown}" "$CLIENT_COUNT" "$COMMAND" "$SEAT_ID" \
  "${AIRPLANE_CONTAINER_NAME:-airplane-reservation}" >"$RUN_DIR/summary.txt"
git -C "$ROOT_DIR" rev-parse HEAD >>"$RUN_DIR/summary.txt" 2>/dev/null || true
if [ "$DEMO_NAME" = demo1 ]; then
  ui_banner "AIRPLANE RESERVATION - DEMO 1"
else
  ui_banner "AIRPLANE RESERVATION - CONCURRENT COMMAND TEST"
fi
ui_section "CONFIGURATION"
ui_kv "Experiment" "$EXPERIMENT"
ui_kv "Workers" "${WORKER_COUNT:-unknown}"
ui_kv "Clients" "$CLIENT_COUNT"
ui_kv "Command" "$COMMAND"
ui_kv "Target seat" "$SEAT_ID"
ui_kv "Results" "$RUN_DIR"
LOCAL_LOG_START=1
if [ "$RUNTIME" = local ]; then LOCAL_LOG_START=$(( $(wc -c <"$SERVER_LOG") + 1 )); fi
# Fail early if logging itself is unavailable, before issuing mutations.
  runtime_log_snapshot >"$RUN_DIR/server.log" 2>&1
: >"$RUN_DIR/server-live.log"
runtime_live_logs >"$RUN_DIR/server-live.log" 2>&1 &
LOG_PID=$!
# Poll a regular file rather than a FIFO (Git Bash on Windows has no mkfifo).
display_logs() {
  local line pending=""
  while true; do
    if IFS= read -r line; then
      ui_stream SERVER "$pending$line"
      pending=""
    else
      pending+="$line"
      if ! kill -0 "$LOG_PID" 2>/dev/null; then
        [ -z "$pending" ] || ui_stream SERVER "$pending"
        break
      fi
      sleep 0.05
    fi
  done
}
display_logs <"$RUN_DIR/server-live.log" &
READER_PID=$!

run_client() {
  local id="$1" commands="$2"
  mkdir -p "$RUN_DIR/clients/client-$id"
  printf '%s' "$commands" >"$RUN_DIR/clients/client-$id/commands.txt"
  printf '%s' "$commands" | runtime_client "$id" 2>&1 \
    | tee "$RUN_DIR/clients/client-$id/output.log" \
    | while IFS= read -r line; do ui_stream "CLIENT-$id" "$line"; done
}

write_report() {
  local report="$RUN_DIR/report.txt"
  local id seat file command_status cancel_status failure_reason response
  local success_count=0 failed_count=0 cancelled_count=0

  if [ "$DEMO_NAME" = demo1 ]; then
    printf '%s\n' '============================================================================' >"$report"
    printf '%s\n' 'AIRPLANE RESERVATION - DEMO 1 RESULT' >>"$report"
    printf '%s\n\n' '============================================================================' >>"$report"
    printf '%s\n' 'CONFIGURATION' '-------------' >>"$report"
    printf 'Experiment: %s\nWorkers: %s\nClients: %s\nCommand: mixed\nStarted at: %s\n\n' \
      "$EXPERIMENT" "${WORKER_COUNT:-unknown}" "$CLIENT_COUNT" "$STARTED_AT" >>"$report"
    printf '%s\n' 'CLIENT RESULTS' '--------------' >>"$report"
    printf '%-10s | %-34s | %s\n' 'Client' 'Reservation' 'Cancellation' >>"$report"
    printf '%s\n' '-----------|------------------------------------|-------------' >>"$report"
  else
    printf '%s\n' '============================================================================' >"$report"
    printf '%s\n' 'AIRPLANE RESERVATION - CONCURRENT COMMAND RESULT' >>"$report"
    printf '%s\n\n' '============================================================================' >>"$report"
    printf '%s\n' 'CONFIGURATION' '-------------' >>"$report"
    printf 'Experiment: %s\nWorkers: %s\nClients: %s\nCommand: %s\nTarget seat: %s\nStarted at: %s\n\n' \
      "$EXPERIMENT" "${WORKER_COUNT:-unknown}" "$CLIENT_COUNT" "$COMMAND" \
      "$([ "$COMMAND" = LIST ] && printf 'not applicable' || printf '%s' "$SEAT_ID")" "$STARTED_AT" >>"$report"
    printf '%s\n' 'CLIENT RESULTS' '--------------' >>"$report"
    printf '%-10s | %s\n' 'Client' 'Result' >>"$report"
    printf '%s\n' '-----------|----------------------------------------------' >>"$report"
  fi

  for ((id = 1; id <= CLIENT_COUNT; ++id)); do
    file="$RUN_DIR/clients/client-$id/output.log"
    if [ "$DEMO_NAME" = demo1 ]; then seat="$id"; else seat="$SEAT_ID"; fi

    if [ "$DEMO_NAME" = demo1 ]; then
      if grep -Fqx "SUCCESS: Seat $seat reserved" "$file"; then
        command_status="SUCCESS (Seat $seat)"
        success_count=$((success_count + 1))
      else
        failure_reason="$(grep -m1 '^FAILED:' "$file" | sed 's/^FAILED: //' || true)"
        command_status="FAILED${failure_reason:+: $failure_reason}"
        failed_count=$((failed_count + 1))
      fi
    else
      response=""
      case "$COMMAND" in
        RESERVE) response="$(grep -Fx "SUCCESS: Seat $seat reserved" "$file" || true)" ;;
        CANCEL) response="$(grep -Fx "SUCCESS: Seat $seat cancelled" "$file" || true)" ;;
        STATUS) response="$(grep -m1 -E "^Seat $seat is (AVAILABLE|RESERVED)" "$file" || true)" ;;
        LIST) response="$(grep -m1 -F '===== Airplane Seat Map =====' "$file" || true)" ;;
      esac
      if [ -n "$response" ]; then
        case "$COMMAND" in
          RESERVE|CANCEL) command_status="SUCCESS (Seat $seat)" ;;
          STATUS) command_status="SUCCESS ($response)" ;;
          LIST) command_status="SUCCESS (seat map received)" ;;
        esac
        success_count=$((success_count + 1))
      else
        failure_reason="$(grep -m1 -E '^(FAILED:|ERROR:|Usage:)' "$file" || true)"
        command_status="${failure_reason:-FAILED: no valid response}"
        failed_count=$((failed_count + 1))
      fi
    fi

    if [ "$DEMO_NAME" = demo1 ]; then
      if grep -Fqx "SUCCESS: Seat $seat cancelled" "$file"; then
        cancel_status="SUCCESS"
        cancelled_count=$((cancelled_count + 1))
      else
        cancel_status="FAILED"
      fi
      printf '%-10s | %-34s | %s\n' "client-$id" "$command_status" "$cancel_status" >>"$report"
    else
      printf '%-10s | %s\n' "client-$id" "$command_status" >>"$report"
    fi
  done

  printf '\n%s\n%s\n' 'SUMMARY' '-------' >>"$report"
  if [ "$DEMO_NAME" = demo1 ]; then
    printf 'Successful reservations: %s/%s\nFailed reservations: %s/%s\n' \
      "$success_count" "$CLIENT_COUNT" "$failed_count" "$CLIENT_COUNT" >>"$report"
    printf 'Successful cancellations: %s/%s\n' "$cancelled_count" "$CLIENT_COUNT" >>"$report"
  elif [ "$COMMAND" = RESERVE ]; then
    printf 'Successful reservations: %s/%s\nFailed reservations: %s/%s\n' \
      "$success_count" "$CLIENT_COUNT" "$failed_count" "$CLIENT_COUNT" >>"$report"
  elif [ "$COMMAND" = CANCEL ]; then
    printf 'Successful cancellations: %s/%s\nFailed cancellations: %s/%s\n' \
      "$success_count" "$CLIENT_COUNT" "$failed_count" "$CLIENT_COUNT" >>"$report"
  else
    printf 'Successful commands: %s/%s\nFailed commands: %s/%s\n' \
      "$success_count" "$CLIENT_COUNT" "$failed_count" "$CLIENT_COUNT" >>"$report"
  fi

  if [ "$CONFLICT_COUNT" -gt 0 ]; then
    printf 'Consistency check: FAILED (%s seat conflict detected)\n' "$CONFLICT_COUNT" >>"$report"
  else
    printf 'Consistency check: PASSED\n' >>"$report"
  fi

  printf '\n%s\n%s\n' 'ARTIFACTS' '---------' >>"$report"
  printf 'Seat map snapshot: seat-map.txt\nConflict evidence: seat-conflicts.txt\nClient outputs: clients/\nServer log: server.log\nLive server log: server-live.log\n' >>"$report"

  ui_render_report "$report"
  ui_success "Report saved in: $report"
  [ -t 1 ] || echo "Report saved in: $report"
}

if [ "$DEMO_NAME" = demo1 ]; then
  ui_note "Five clients run mixed commands on Seats 1-5."
  mkdir -p "$RUN_DIR/preflight"
  printf 'LIST\nQUIT\n' | runtime_client 1 >"$RUN_DIR/preflight/list.log"
  for id in 1 2 3 4 5; do
    # Check through STATUS so preconditions do not depend on LIST formatting.
    printf 'STATUS %s\nQUIT\n' "$id" | runtime_client "$id" >"$RUN_DIR/preflight/client-$id.log"
    grep -q "Seat $id is AVAILABLE" "$RUN_DIR/preflight/client-$id.log" || {
      echo "Seat $id is already reserved; restart the server before Demo 1." >&2; exit 1;
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
  if [ "$COMMAND" = CANCEL ]; then
    ui_note "Preparing Seat $SEAT_ID as a Client-1 reservation for the CANCEL test."
    mkdir -p "$RUN_DIR/preflight"
    printf 'STATUS %s\nQUIT\n' "$SEAT_ID" | runtime_client 1 >"$RUN_DIR/preflight/status.log"
    if grep -Fq "Seat $SEAT_ID is AVAILABLE" "$RUN_DIR/preflight/status.log"; then
      printf 'RESERVE %s\nQUIT\n' "$SEAT_ID" | runtime_client 1 >"$RUN_DIR/preflight/reserve.log"
      grep -Fqx "SUCCESS: Seat $SEAT_ID reserved" "$RUN_DIR/preflight/reserve.log" || {
        echo "Could not reserve Seat $SEAT_ID for Client-1 before CANCEL test." >&2; exit 1;
      }
    elif ! grep -Fq "Seat $SEAT_ID is RESERVED by Client-1" "$RUN_DIR/preflight/status.log"; then
      echo "Seat $SEAT_ID must be available or owned by Client-1 before CANCEL test." >&2
      exit 1
    fi
  fi
  commands=()
  for ((id = 1; id <= CLIENT_COUNT; ++id)); do
    if [ "$COMMAND" = LIST ]; then
      commands+=($'LIST\nQUIT\n')
    else
      commands+=("$COMMAND $SEAT_ID"$'\nQUIT\n')
    fi
  done
fi

ui_section "LIVE SERVER AND CLIENT OUTPUT"

for ((id = 1; id <= CLIENT_COUNT; ++id)); do
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
if ! runtime_log_snapshot >"$RUN_DIR/server.log" 2>&1; then failed=1; fi
seat_map_available=true
if ! printf 'LIST\nQUIT\n' | runtime_client 9999 >"$RUN_DIR/seat-map.txt" 2>&1; then
  seat_map_available=false
fi
if ! grep -q '^Seat 20 : ' "$RUN_DIR/seat-map.txt"; then
  seat_map_available=false
fi
: >"$RUN_DIR/seat-conflicts.txt"
if [ "$DEMO_NAME" != demo1 ] && [ "$COMMAND" = RESERVE ]; then
  successful_clients=""
  successful_count=0
  for ((id = 1; id <= CLIENT_COUNT; ++id)); do
    if grep -Fqx "SUCCESS: Seat $SEAT_ID reserved" "$RUN_DIR/clients/client-$id/output.log"; then
      successful_clients+="${successful_clients:+, }Client-$id"
      successful_count=$((successful_count + 1))
    fi
  done
  if [ "$successful_count" -gt 1 ]; then
    final_owner="$(sed -n "s/^Seat $SEAT_ID : RESERVED by //p" "$RUN_DIR/seat-map.txt" | head -n 1)"
    printf '%s|%s|%s\n' "$SEAT_ID" "$successful_clients" "${final_owner:-unknown}" \
      >"$RUN_DIR/seat-conflicts.txt"
    CONFLICT_COUNT=1
  fi
fi
write_report
if [ "$seat_map_available" = true ]; then
  ui_render_seat_map "$RUN_DIR/seat-map.txt" "$RUN_DIR/seat-conflicts.txt"
else
  ui_note "Seat map is unavailable; inspect $RUN_DIR/seat-map.txt for details."
fi

for ((id = 1; id <= CLIENT_COUNT; ++id)); do
  file="$RUN_DIR/clients/client-$id/output.log"
  grep -q '^GOODBYE$' "$file" || failed=1
  if [ "$DEMO_NAME" = demo1 ]; then
    grep -q "^SUCCESS: Seat $id reserved" "$file" || failed=1
    grep -q "^SUCCESS: Seat $id cancelled" "$file" || failed=1
    if grep -Eq '^(FAILED:|ERROR:|Usage:)' "$file"; then failed=1; fi
  fi
done
if [ "$failed" -ne 0 ]; then exit 1; fi

if [ "$DEMO_NAME" = demo1 ]; then
  ui_success "Demo 1 finished: all five clients reserved and cancelled their own seats."
else
  ui_success "Concurrent $COMMAND test finished."
  if [ "$COMMAND" = RESERVE ] || [ "$COMMAND" = CANCEL ]; then
    ui_note "Operation failures are expected under contention; compare client results."
  fi
fi
ui_kv "Saved results" "$RUN_DIR"
