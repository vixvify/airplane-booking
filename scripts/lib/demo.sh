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
  DEMO_COMMAND_NAMES='LIST, STATUS, RESERVE, CANCEL, QUIT'
  DEMO_WORKLOAD='Reserve 2 seats, cancel 1 seat, keep 1 reserved per client'
  DEMO_RESERVE_SEATS=("1 2" "3 4" "5 6" "7 8" "9 10")
  DEMO_CANCEL_SEATS=(1 4 5 8 9)
  DEMO_REMAINING_SEATS=(2 3 6 7 10)
  DEMO_COMMANDS=(
    $'LIST\nRESERVE 1 2\nSTATUS 1\nCANCEL 1\nSTATUS 2\nQUIT\n'
    $'STATUS 3\nRESERVE 3 4\nCANCEL 4\nSTATUS 3\nLIST\nQUIT\n'
    $'RESERVE 5 6\nLIST\nCANCEL 5\nSTATUS 6\nQUIT\n'
    $'RESERVE 7 8\nSTATUS 8\nCANCEL 8\nLIST\nSTATUS 7\nQUIT\n'
    $'LIST\nRESERVE 9 10\nCANCEL 9\nSTATUS 10\nQUIT\n'
  )
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

demo_command_sequence() {
  local sequence="${DEMO_COMMANDS[$1]%$'\n'}"
  printf '%s' "${sequence//$'\n'/ → }"
}

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
if [ "$DEMO_NAME" = demo1 ]; then
  ui_kv "Commands" "$DEMO_COMMAND_NAMES"
  ui_kv "Workload" "$DEMO_WORKLOAD"
  printf '\n%s%sClient command plans%s\n' "$UI_BOLD" "$UI_WHITE" "$UI_RESET"
  for ((id = 1; id <= CLIENT_COUNT; ++id)); do
    printf '  %s%-8s%s  %s\n' \
      "$UI_CYAN" "Client-$id" "$UI_RESET" "$(demo_command_sequence "$((id - 1))")"
  done
else
  ui_kv "Command" "$COMMAND"
  ui_kv "Target seat" "$SEAT_ID"
fi
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
  local id seat file command_status cancel_status final_status failure_reason response
  local reserve_seats reserve_display cancel_seat remaining_seat reservation_ok total_reservations sequence
  local success_count=0 failed_count=0 cancelled_count=0 remaining_count=0

  if [ "$DEMO_NAME" = demo1 ]; then
    printf '%s\n' '============================================================================' >"$report"
    printf '%s\n' 'AIRPLANE RESERVATION - DEMO 1 RESULT' >>"$report"
    printf '%s\n\n' '============================================================================' >>"$report"
    printf '%s\n' 'CONFIGURATION' '-------------' >>"$report"
    printf 'Experiment: %s\nWorkers: %s\nClients: %s\nCommand: mixed\nCommands: %s\nWorkload: %s\nStarted at: %s\n' \
      "$EXPERIMENT" "${WORKER_COUNT:-unknown}" "$CLIENT_COUNT" \
      "$DEMO_COMMAND_NAMES" "$DEMO_WORKLOAD" "$STARTED_AT" >>"$report"
    for ((id = 1; id <= CLIENT_COUNT; ++id)); do
      sequence="$(demo_command_sequence "$((id - 1))")"
      printf 'Client %s commands: %s\n' "$id" "$sequence" >>"$report"
    done
    printf '\n' >>"$report"
    printf '%s\n' 'CLIENT RESULTS' '--------------' >>"$report"
    printf '%-10s | %-28s | %-21s | %s\n' 'Client' 'Reserved seats' 'Cancelled seat' 'Remains reserved' >>"$report"
    printf '%s\n' '-----------|------------------------------|-----------------------|-----------------' >>"$report"
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

    if [ "$DEMO_NAME" = demo1 ]; then
      reserve_seats="${DEMO_RESERVE_SEATS[id-1]}"
      cancel_seat="${DEMO_CANCEL_SEATS[id-1]}"
      remaining_seat="${DEMO_REMAINING_SEATS[id-1]}"
      reserve_display="${reserve_seats// /, }"
      reservation_ok=true
      for seat in $reserve_seats; do
        if grep -Fqx "SUCCESS: Seat $seat reserved" "$file"; then
          success_count=$((success_count + 1))
        else
          failed_count=$((failed_count + 1))
          reservation_ok=false
        fi
      done
      if [ "$reservation_ok" = true ]; then
        command_status="SUCCESS (Seats $reserve_display)"
      else
        failure_reason="$(grep -m1 '^FAILED:' "$file" | sed 's/^FAILED: //' || true)"
        command_status="FAILED${failure_reason:+: $failure_reason}"
      fi
    else
      seat="$SEAT_ID"
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
      if grep -Fqx "SUCCESS: Seat $cancel_seat cancelled" "$file"; then
        cancel_status="SUCCESS (Seat $cancel_seat)"
        cancelled_count=$((cancelled_count + 1))
      else
        cancel_status="FAILED (Seat $cancel_seat)"
      fi
      if grep -Fqx "Seat $remaining_seat : RESERVED by Client-$id" "$RUN_DIR/seat-map.txt"; then
        final_status="SUCCESS (Seat $remaining_seat)"
        remaining_count=$((remaining_count + 1))
      else
        final_status="FAILED (Seat $remaining_seat)"
      fi
      printf '%-10s | %-28s | %-21s | %s\n' \
        "client-$id" "$command_status" "$cancel_status" "$final_status" >>"$report"
    else
      printf '%-10s | %s\n' "client-$id" "$command_status" >>"$report"
    fi
  done

  printf '\n%s\n%s\n' 'SUMMARY' '-------' >>"$report"
  if [ "$DEMO_NAME" = demo1 ]; then
    total_reservations=$((CLIENT_COUNT * 2))
    printf 'Successful seat reservations: %s/%s\nFailed seat reservations: %s/%s\n' \
      "$success_count" "$total_reservations" "$failed_count" "$total_reservations" >>"$report"
    printf 'Successful cancellations: %s/%s\n' "$cancelled_count" "$CLIENT_COUNT" >>"$report"
    printf 'Seats remaining reserved: %s/%s\n' "$remaining_count" "$CLIENT_COUNT" >>"$report"
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
  [ -t 1 ] || echo "Report saved in: $report"
}

if [ "$DEMO_NAME" = demo1 ]; then
  ui_note "Five clients reserve two seats each, cancel one, and keep one reserved on Seats 1-10."
  mkdir -p "$RUN_DIR/preflight"
  printf 'LIST\nQUIT\n' | runtime_client 1 >"$RUN_DIR/preflight/list.log"
  for preflight_seat in {1..10}; do
    # Check through STATUS so preconditions do not depend on LIST formatting.
    printf 'STATUS %s\nQUIT\n' "$preflight_seat" | runtime_client 1 >"$RUN_DIR/preflight/seat-$preflight_seat.log"
    grep -q "Seat $preflight_seat is AVAILABLE" "$RUN_DIR/preflight/seat-$preflight_seat.log" || {
      echo "Seat $preflight_seat is already reserved; restart the server before Demo 1." >&2; exit 1;
    }
  done
  commands=("${DEMO_COMMANDS[@]}")
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
    for seat in ${DEMO_RESERVE_SEATS[id-1]}; do
      grep -Fqx "SUCCESS: Seat $seat reserved" "$file" || failed=1
    done
    cancel_seat="${DEMO_CANCEL_SEATS[id-1]}"
    remaining_seat="${DEMO_REMAINING_SEATS[id-1]}"
    grep -Fqx "SUCCESS: Seat $cancel_seat cancelled" "$file" || failed=1
    grep -Fqx "Seat $cancel_seat : AVAILABLE" "$RUN_DIR/seat-map.txt" || failed=1
    grep -Fqx "Seat $remaining_seat : RESERVED by Client-$id" "$RUN_DIR/seat-map.txt" || failed=1
    if grep -Eq '^(FAILED:|ERROR:|Usage:)' "$file"; then failed=1; fi
  fi
done
if [ "$failed" -ne 0 ]; then exit 1; fi

if [ "$DEMO_NAME" = demo1 ]; then
  ui_success "Demo 1 finished: each client reserved two seats, cancelled one, and kept one reserved."
else
  ui_success "Concurrent $COMMAND test finished."
fi
