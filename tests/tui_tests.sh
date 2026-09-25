#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PASS_COUNT=0
FAIL_COUNT=0
TEST_DIR="${TMPDIR:-/tmp}/airplane-reservation-tui-tests-$$"
mkdir -p "$TEST_DIR"
trap 'rm -rf "$TEST_DIR"' EXIT
MOCK_DOCKER="$TEST_DIR/docker-mock"
cp "$ROOT_DIR/tests/fixtures/docker-mock.sh" "$MOCK_DOCKER"
chmod +x "$MOCK_DOCKER"

ALT_ENTER=$'\033[?1049h'
ALT_LEAVE=$'\033[?1049l'
CLEAR_FRAME=$'\033[H\033[2J'
CLEAR_SCROLLBACK=$'\033[3J\033[H\033[2J'
DOWN=$'\033[B'
RIGHT=$'\033[C'

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local name="$3"

  if grep -Fq "$expected" "$file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_not_contains() {
  local file="$1"
  local unexpected="$2"
  local name="$3"

  if grep -Fq "$unexpected" "$file"; then
    fail "$name"
  else
    pass "$name"
  fi
}

assert_count() {
  local file="$1"
  local expected="$2"
  local value="$3"
  local name="$4"
  local actual

  actual="$(grep -Fao "$value" "$file" | wc -l | tr -d '[:space:]')"
  if [ "$actual" = "$expected" ]; then
    pass "$name"
  else
    fail "$name (expected $expected, got $actual)"
  fi
}

run_menu() {
  local keys="$1"
  local output="$2"
  printf '%b' "$keys" | timeout 5s bash scripts/menu.sh >"$output" 2>&1
}

run_menu_with_mock_docker() {
  local keys="$1"
  local output="$2"
  printf '%b' "$keys" | \
    MOCK_TRACE="$TEST_DIR/docker-calls.log" \
    MOCK_FAIL= \
    MOCK_SERVER_COMMAND='["./server","sync","3"]' \
    DOCKER="$MOCK_DOCKER" \
    RUNTIME=container \
    timeout 5s bash scripts/menu.sh >"$output" 2>&1
}

render_server_status_with_mock_docker() {
  local output="$1"
  printf '\n' | \
    MOCK_TRACE="$TEST_DIR/docker-calls.log" \
    MOCK_FAIL= \
    MOCK_SERVER_COMMAND='["./server","sync","3"]' \
    DOCKER="$MOCK_DOCKER" \
    RUNTIME=container \
    MENU_LIBRARY_ONLY=yes \
    timeout 5s bash -c 'source scripts/menu.sh; show_status' >"$output" 2>&1
}

printf 'Running terminal UI tests...\n\n'

OUTPUT="$TEST_DIR/quit.raw"
if run_menu 'q' "$OUTPUT"; then
  pass 'TUI exits with Q'
else
  fail 'TUI exits with Q'
fi
assert_count "$OUTPUT" 1 "$ALT_ENTER" 'TUI enters alternate screen once'
assert_count "$OUTPUT" 1 "$ALT_LEAVE" 'TUI restores normal screen once'
assert_count "$OUTPUT" 1 "$CLEAR_FRAME" 'TUI clears the screen only at startup'

OUTPUT="$TEST_DIR/load-navigation.raw"
if run_menu "${DOWN}${DOWN}${DOWN}${DOWN}\nq" "$OUTPUT"; then
  pass 'Arrow keys and Enter open Load Test form'
else
  fail 'Arrow keys and Enter open Load Test form'
fi
assert_contains "$OUTPUT" 'Load Test - Logical clients and performance metrics' 'Load Test form is rendered'
assert_contains "$OUTPUT" 'Total requests: 50000' 'Load Test defaults are rendered'
assert_count "$OUTPUT" 1 "$CLEAR_FRAME" 'Navigation does not clear the full screen'
assert_count "$OUTPUT" 1 'AIRPLANE RESERVATION - TERMINAL CONTROL PANEL' 'Navigation does not redraw the unchanged header'

OUTPUT="$TEST_DIR/exp2-settings.raw"
if run_menu "${DOWN}\n${RIGHT}${DOWN}${RIGHT}q" "$OUTPUT"; then
  pass 'Exp2 settings accept navigation input'
else
  fail 'Exp2 settings accept navigation input'
fi
assert_contains "$OUTPUT" 'Workers: 4' 'Exp2 worker count can be changed'
assert_contains "$OUTPUT" 'Clients: 6' 'Exp2 client count can be changed'
assert_count "$OUTPUT" 1 'AIRPLANE RESERVATION - TERMINAL CONTROL PANEL' 'Editing values does not redraw the unchanged header'

OUTPUT="$TEST_DIR/command-selection.raw"
if run_menu "${DOWN}\n${DOWN}${DOWN}${RIGHT}${RIGHT}${RIGHT}${DOWN}q" "$OUTPUT"; then
  pass 'Experiment command selector accepts navigation input'
else
  fail 'Experiment command selector accepts navigation input'
fi
assert_contains "$OUTPUT" 'Command: RESERVE' 'Experiment command defaults to RESERVE'
assert_contains "$OUTPUT" 'Command: CANCEL' 'Experiment command can select CANCEL'
assert_contains "$OUTPUT" 'Command: STATUS' 'Experiment command can select STATUS'
assert_contains "$OUTPUT" 'Command: LIST' 'Experiment command can select LIST'
assert_contains "$OUTPUT" 'Target seat: disabled' 'LIST disables the unused target seat'
assert_count "$OUTPUT" 1 "$CLEAR_FRAME" 'Command selection uses incremental rendering'

OUTPUT="$TEST_DIR/load-request-step.raw"
if run_menu "${DOWN}${DOWN}${DOWN}${DOWN}\n${DOWN}${DOWN}${RIGHT}q" "$OUTPUT"; then
  pass 'Load Test total requests accepts arrow input'
else
  fail 'Load Test total requests accepts arrow input'
fi
assert_contains "$OUTPUT" 'Total requests: 150000' 'Load Test total requests increases by 100,000'

OUTPUT="$TEST_DIR/output-screen.raw"
if run_menu_with_mock_docker "${DOWN}${DOWN}${DOWN}${DOWN}${DOWN}${DOWN}\n\nq" "$OUTPUT"; then
  pass 'Output screen returns to the menu after Enter'
else
  fail 'Output screen returns to the menu after Enter'
fi
assert_contains "$OUTPUT" 'AIRPLANE RESERVATION - STOP SERVER' 'Action output is rendered outside the menu screen'
assert_count "$OUTPUT" 2 "$ALT_LEAVE" 'Action output uses the normal scrollback screen'
assert_count "$OUTPUT" 2 "$ALT_ENTER" 'Menu resumes in the alternate screen after Enter'

OUTPUT="$TEST_DIR/server-status.raw"
if render_server_status_with_mock_docker "$OUTPUT"; then
  pass 'Server Status renders and accepts Enter'
else
  fail 'Server Status renders and accepts Enter'
fi
assert_contains "$OUTPUT" 'AIRPLANE RESERVATION - SERVER STATUS' 'Server Status has a clear title'
assert_contains "$OUTPUT" 'Server is running and ready.' 'Server Status highlights the running state'
assert_contains "$OUTPUT" 'Experiment 3 - Concurrent with synchronization' 'Server Status explains the experiment'
assert_contains "$OUTPUT" 'Enabled (per-seat mutex)' 'Server Status explains synchronization'
assert_contains "$OUTPUT" 'Workers            : 3' 'Server Status displays the worker count'
assert_contains "$OUTPUT" 'Container          : airplane-reservation' 'Server Status displays the container name'
assert_contains "$OUTPUT" 'Image              : airplane-reservation:latest' 'Server Status displays the image name'
assert_count "$OUTPUT" 1 "$CLEAR_SCROLLBACK" 'Server Status clears logs from the previous command'

OUTPUT="$TEST_DIR/stop-server.raw"
if printf '\n' | \
  MOCK_TRACE="$TEST_DIR/docker-calls.log" \
  MOCK_FAIL= \
  DOCKER="$MOCK_DOCKER" \
  RUNTIME=container \
  MENU_LIBRARY_ONLY=yes \
  timeout 5s bash -c 'source scripts/menu.sh; stop_server_menu' >"$OUTPUT" 2>&1; then
  pass 'Stop Server renders and accepts Enter'
else
  fail 'Stop Server renders and accepts Enter'
fi
assert_contains "$OUTPUT" 'AIRPLANE RESERVATION - STOP SERVER' 'Stop Server has a clear title'
assert_count "$OUTPUT" 1 "$CLEAR_SCROLLBACK" 'Stop Server clears logs from the previous command'

OUTPUT="$TEST_DIR/output-reset.raw"
if MENU_LIBRARY_ONLY=yes bash -c 'source scripts/menu.sh; begin_output_screen' >"$OUTPUT" 2>&1; then
  pass 'A new run initializes a clean output screen'
else
  fail 'A new run initializes a clean output screen'
fi
assert_count "$OUTPUT" 1 "$CLEAR_SCROLLBACK" 'A new run clears previous terminal logs once'

REPORT_SAMPLE="$TEST_DIR/report-sample.txt"
printf '%s\n' \
  'AIRPLANE RESERVATION - CONCURRENT COMMAND RESULT' \
  'CONFIGURATION' \
  'Experiment: sync' \
  'CLIENT RESULTS' \
  'Client     | Result' \
  'client-1   | SUCCESS (Seat 10)' \
  'client-2   | FAILED: already reserved' \
  'SUMMARY' \
  'Successful reservations: 1/5' \
  'Failed reservations: 4/5' >"$REPORT_SAMPLE"
OUTPUT="$TEST_DIR/report-renderer.raw"
if FORCE_COLOR=1 bash -c 'source scripts/lib/terminal_ui.sh; ui_render_report "$1"' _ "$REPORT_SAMPLE" >"$OUTPUT" 2>&1; then
  pass 'Interactive result renderer formats a report'
else
  fail 'Interactive result renderer formats a report'
fi
assert_contains "$OUTPUT" '[ CONFIGURATION ]' 'Result renderer emphasizes sections'
assert_contains "$OUTPUT" '[PASS] Successful reservations: 1/5' 'Result renderer highlights successful totals'
assert_contains "$OUTPUT" '[FAIL] Failed reservations: 4/5' 'Result renderer highlights failed totals'
assert_contains "$OUTPUT" 'client-1   | SUCCESS (Seat 10)' 'Result renderer preserves per-client success details'
assert_contains "$OUTPUT" 'client-2   | FAILED: already reserved' 'Result renderer preserves per-client failure details'

LOAD_REPORT_SAMPLE="$TEST_DIR/load-report-sample.txt"
printf '%s\n' \
  'AIRPLANE RESERVATION - LOAD TEST RESULT' \
  'CONFIGURATION' \
  'Experiment: sync' \
  'Workers: 3' \
  'Total requests: 50000' \
  'Concurrency: 100' \
  'Operation: RESERVE' \
  'Target seat: 10' \
  'Started at: 2026-09-25T00:00:00Z' \
  'RESULTS' \
  'Completed: 50000' \
  'Transport failures: 0' \
  'Operation succeeded: 1' \
  'Operation failed: 49999' \
  'Completion rate: 100%' \
  'Total time: 9.35645 sec' \
  'Throughput: 5343.91 req/sec' \
  'Average latency: 18.6777 ms' \
  'Consistency check: PASSED' \
  'ARTIFACTS' \
  'Raw benchmark output: output.log' \
  'Seat map snapshot: seat-map.txt' \
  'Conflict evidence: seat-conflicts.txt' \
  'Server log: server.log' \
  'Machine-readable summary: summary.txt' >"$LOAD_REPORT_SAMPLE"
OUTPUT="$TEST_DIR/load-report-renderer.raw"
if NO_COLOR=1 FORCE_COLOR=1 bash -c \
  'source scripts/lib/terminal_ui.sh; ui_render_load_report "$1"' \
  _ "$LOAD_REPORT_SAMPLE" >"$OUTPUT" 2>&1; then
  pass 'Load-test renderer formats a performance dashboard'
else
  fail 'Load-test renderer formats a performance dashboard'
fi
assert_contains "$OUTPUT" '[ RUN OVERVIEW ]' 'Load dashboard separates run configuration'
assert_contains "$OUTPUT" '[ PERFORMANCE ]' 'Load dashboard has a performance section'
assert_contains "$OUTPUT" 'THROUGHPUT' 'Load dashboard highlights throughput'
assert_contains "$OUTPUT" '5343.91 req/sec' 'Load dashboard preserves throughput value'
assert_contains "$OUTPUT" '18.6777 ms' 'Load dashboard preserves average latency value'
assert_contains "$OUTPUT" '9.35645 sec' 'Load dashboard preserves total time value'
assert_contains "$OUTPUT" '████████████████████████████' 'Load dashboard renders a full completion bar'
assert_contains "$OUTPUT" '50,000 / 50,000 responses' 'Load dashboard groups large request counts'
assert_contains "$OUTPUT" '49,999 rejected/failed' 'Load dashboard distinguishes operation rejection from transport failure'
assert_contains "$OUTPUT" '[PASS] PASSED' 'Load dashboard highlights consistency status'
assert_contains "$OUTPUT" '[ SAVED ARTIFACTS ]' 'Load dashboard groups saved evidence'

SEAT_MAP_SAMPLE="$TEST_DIR/seat-map-sample.txt"
for seat in {1..20}; do
  if [ "$seat" -eq 2 ]; then
    printf 'Seat %s : RESERVED by Client-42\n' "$seat"
  else
    printf 'Seat %s : AVAILABLE\n' "$seat"
  fi
done >"$SEAT_MAP_SAMPLE"
OUTPUT="$TEST_DIR/seat-map-renderer.raw"
if FORCE_COLOR=1 bash -c 'source scripts/lib/terminal_ui.sh; ui_render_seat_map "$1"' _ "$SEAT_MAP_SAMPLE" >"$OUTPUT" 2>&1; then
  pass 'Seat-map renderer formats all 20 seats'
else
  fail 'Seat-map renderer formats all 20 seats'
fi
assert_contains "$OUTPUT" 'AIRPLANE SEAT MAP' 'Seat map has a clear title'
assert_contains "$OUTPUT" '[01]' 'Seat map displays an available seat without extra text'
assert_contains "$OUTPUT" '[02:C-42]' 'Seat map displays a compact reservation owner'
assert_not_contains "$OUTPUT" 'FREE' 'Seat map does not repeat FREE in every available seat'
assert_contains "$OUTPUT" 'Row 01' 'Seat map displays ten numbered rows'
assert_contains "$OUTPUT" '[01]' 'Seat map places Seat 1 in the left column'
assert_contains "$OUTPUT" '[11]' 'Seat map places Seat 11 in the right column'
assert_contains "$OUTPUT" 'Row 10' 'Seat map includes the tenth row'
assert_contains "$OUTPUT" '[10]' 'Seat map ends the left column at Seat 10'
assert_contains "$OUTPUT" '[20]' 'Seat map ends the right column at Seat 20'
assert_contains "$OUTPUT" 'LEFT' 'Seat map labels the left seat column'
assert_contains "$OUTPUT" 'RIGHT' 'Seat map labels the right seat column'
assert_contains "$OUTPUT" '┼' 'Seat map displays a single center aisle divider'
assert_contains "$OUTPUT" '▲ FRONT' 'Seat map marks the front clearly'
assert_contains "$OUTPUT" '▼ TAIL' 'Seat map marks the tail clearly'
assert_contains "$OUTPUT" '● 19 available' 'Seat map totals available seats'
assert_contains "$OUTPUT" '● 1 reserved' 'Seat map totals reserved seats'
assert_not_contains "$OUTPUT" '[10:C-1] reserved' 'Seat map does not show a hard-coded owner legend'
assert_not_contains "$OUTPUT" 'Client-n' 'Seat map does not show a placeholder as data'

CONFLICT_SAMPLE="$TEST_DIR/seat-conflicts-sample.txt"
printf '2|Client-2, Client-7, Client-9|Client-42\n' >"$CONFLICT_SAMPLE"
OUTPUT="$TEST_DIR/seat-map-conflict-renderer.raw"
if FORCE_COLOR=1 bash -c 'source scripts/lib/terminal_ui.sh; ui_render_seat_map "$1" "$2"' \
  _ "$SEAT_MAP_SAMPLE" "$CONFLICT_SAMPLE" >"$OUTPUT" 2>&1; then
  pass 'Seat-map renderer exposes conflicting successes'
else
  fail 'Seat-map renderer exposes conflicting successes'
fi
assert_contains "$OUTPUT" '[02:RACE]' 'Conflicted seat is marked as RACE instead of one apparent winner'
assert_contains "$OUTPUT" '⚠ 1 conflict' 'Seat map totals detected conflicts'
assert_contains "$OUTPUT" '⚠ RACE = multiple clients received SUCCESS' 'Conflict legend explains the race marker without a fake owner'
assert_not_contains "$OUTPUT" '[10:C-1] reserved' 'Conflict map does not show a hard-coded owner legend'
assert_contains "$OUTPUT" '[FAIL] CONSISTENCY CHECK' 'Seat map fails its consistency check'
assert_contains "$OUTPUT" 'SUCCESS clients: Client-2, Client-7, Client-9' 'Conflict evidence lists every successful client'
assert_contains "$OUTPUT" 'Final stored owner: Client-42 (last write won)' 'Conflict evidence distinguishes final memory from successful replies'

printf '\nTUI tests: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
