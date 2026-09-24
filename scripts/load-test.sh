#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/runtime.sh"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
source "$ROOT_DIR/scripts/lib/terminal_ui.sh"

usage() {
  echo "Usage: bash scripts/load-test.sh <total_requests> <concurrency> <STATUS|RESERVE|CANCEL> [seat_id]" >&2
  exit 2
}

[ "$#" -eq 3 ] || [ "$#" -eq 4 ] || usage
TOTAL_REQUESTS="$1"
CONCURRENCY="$2"
OPERATION="${3^^}"
SEAT_ID="${4:-}"
[[ "$TOTAL_REQUESTS" =~ ^[1-9][0-9]*$ ]] || usage
[[ "$CONCURRENCY" =~ ^[1-9][0-9]*$ ]] || usage
case "$OPERATION" in STATUS|RESERVE|CANCEL) ;; *) usage ;; esac
if [ -n "$SEAT_ID" ]; then
  [[ "$SEAT_ID" =~ ^([1-9]|1[0-9]|20)$ ]] || usage
fi

RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
RUN_DIR="$(create_result_dir load-tests "")"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%S.%NZ)"
init_runtime

ui_banner "AIRPLANE RESERVATION - LOAD TEST"
ui_section "CONFIGURATION"
ui_kv "Experiment" "$EXPERIMENT"
ui_kv "Workers" "${WORKER_COUNT:-unknown}"
ui_kv "Total requests" "$TOTAL_REQUESTS"
ui_kv "Concurrency" "$CONCURRENCY"
ui_kv "Operation" "$OPERATION"
ui_kv "Target seat" "${SEAT_ID:-round-robin 1-20}"
ui_kv "Results" "$RUN_DIR"
ui_section "BENCHMARK OUTPUT"

arguments=(./load_test "$TOTAL_REQUESTS" "$CONCURRENCY" "$OPERATION")
[ -z "$SEAT_ID" ] || arguments+=("$SEAT_ID")
set +e
container exec "${arguments[@]}" 2>&1 | tee "$RUN_DIR/output.log"
load_status="${PIPESTATUS[0]}"
set -e
log_status=0
container logs --since "$STARTED_AT" --timestamps >"$RUN_DIR/server.log" 2>&1 || log_status=$?

extract_metric() {
  local label="$1" value
  value="$(sed -n "s/^${label}[[:space:]]*:[[:space:]]*//p" "$RUN_DIR/output.log" | tail -n 1)"
  printf '%s' "${value:-not available}"
}

cat >"$RUN_DIR/report.txt" <<REPORT
============================================================================
AIRPLANE RESERVATION - LOAD TEST RESULT
============================================================================

CONFIGURATION
-------------
Experiment: $EXPERIMENT
Workers: ${WORKER_COUNT:-unknown}
Total requests: $TOTAL_REQUESTS
Concurrency: $CONCURRENCY
Operation: $OPERATION
Target seat: ${SEAT_ID:-round-robin 1-20}
Started at: $STARTED_AT

RESULTS
-------
Completed: $(extract_metric 'Completed')
Transport failures: $(extract_metric 'Transport Fail')
Operation succeeded: $(extract_metric 'Operation OK')
Operation failed: $(extract_metric 'Operation Fail')
Completion rate: $(extract_metric 'Completion Rate')
Total time: $(extract_metric 'Total Time')
Throughput: $(extract_metric 'Throughput')
Average latency: $(extract_metric 'Average Latency')

ARTIFACTS
---------
Raw benchmark output: output.log
Server log: server.log
Machine-readable summary: summary.txt
REPORT

cat >"$RUN_DIR/summary.txt" <<SUMMARY
started_at=$STARTED_AT
finished_at=$(date -u +%FT%TZ)
experiment=$EXPERIMENT
workers=${WORKER_COUNT:-unknown}
container_name=${AIRPLANE_CONTAINER_NAME:-airplane-reservation}
total_requests=$TOTAL_REQUESTS
concurrency=$CONCURRENCY
operation=$OPERATION
seat_id=${SEAT_ID:-round-robin 1-20}
load_output=output.log
server_log=server.log
report_file=report.txt
load_exit_code=$load_status
server_log_exit_code=$log_status
SUMMARY

if [ "$load_status" -ne 0 ]; then
  ui_error "Load test failed. Evidence: $RUN_DIR"
  exit "$load_status"
fi
if [ "$log_status" -ne 0 ]; then
  ui_error "Load test passed, but server logs could not be saved. Evidence: $RUN_DIR"
  exit "$log_status"
fi
ui_render_report "$RUN_DIR/report.txt"
ui_success "Load test finished. Results: $RUN_DIR"
[ -t 1 ] || echo "Load test finished. Results: $RUN_DIR"
