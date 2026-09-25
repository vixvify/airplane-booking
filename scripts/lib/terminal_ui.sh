#!/usr/bin/env bash

UI_WIDTH=76
UI_RESET=""
UI_BOLD=""
UI_CYAN=""
UI_BLUE=""
UI_GREEN=""
UI_RED=""
UI_YELLOW=""
UI_MAGENTA=""

if { [ -t 1 ] || [ "${FORCE_COLOR:-0}" = 1 ]; } && [ -z "${NO_COLOR:-}" ]; then
  UI_RESET=$'\033[0m'
  UI_BOLD=$'\033[1m'
  UI_CYAN=$'\033[36m'
  UI_BLUE=$'\033[34m'
  UI_GREEN=$'\033[32m'
  UI_RED=$'\033[31m'
  UI_YELLOW=$'\033[33m'
  UI_MAGENTA=$'\033[35m'
fi

ui_rule() {
  local character="${1:--}" rule
  printf -v rule '%*s' "$UI_WIDTH" ''
  printf '%s\n' "${rule// /$character}"
}

ui_banner() {
  printf '\n%s%s' "$UI_BOLD" "$UI_CYAN"
  ui_rule '='
  printf '  %s\n' "$1"
  ui_rule '='
  printf '%s' "$UI_RESET"
}

ui_section() {
  printf '\n%s%s%s%s\n' "$UI_BOLD" "$UI_BLUE" "$1" "$UI_RESET"
  ui_rule '-'
}

ui_kv() { printf '  %-18s : %s\n' "$1" "$2"; }
ui_success() { printf '%s%s[OK]%s %s\n' "$UI_BOLD" "$UI_GREEN" "$UI_RESET" "$1"; }
ui_error() { printf '%s%s[ERROR]%s %s\n' "$UI_BOLD" "$UI_RED" "$UI_RESET" "$1" >&2; }
ui_note() { printf '%s%s[NOTE]%s %s\n' "$UI_BOLD" "$UI_YELLOW" "$UI_RESET" "$1"; }

ui_stream() {
  local source="$1" message="$2" source_color="$UI_MAGENTA" message_color=""
  [ "$source" = SERVER ] && source_color="$UI_CYAN"
  case "$message" in
    SUCCESS:*|DONE:*|GOODBYE) message_color="$UI_GREEN" ;;
    FAILED:*|ERROR:*|Usage:*) message_color="$UI_RED" ;;
  esac
  printf '%s[%s]%s %s%s%s\n' \
    "$source_color" "$source" "$UI_RESET" "$message_color" "$message" "$UI_RESET"
}

ui_render_report() {
  local report="$1" line section="" label value

  # Keep redirected output stable for scripts and CI. The richer renderer is
  # only used when a person is looking at an interactive terminal.
  if [ ! -t 1 ] && [ "${FORCE_COLOR:-0}" != 1 ]; then
    cat "$report"
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      AIRPLANE\ RESERVATION\ -*RESULT)
        ui_banner "$line"
        ;;
      CONFIGURATION|"CLIENT RESULTS"|RESULTS|SUMMARY|ARTIFACTS)
        section="$line"
        printf '\n%s%s[ %s ]%s\n' "$UI_BOLD" "$UI_BLUE" "$line" "$UI_RESET"
        ui_rule '-'
        ;;
      ===*|---*)
        ;;
      Client*'|'*)
        printf '%s%s  %s%s\n' "$UI_BOLD" "$UI_CYAN" "$line" "$UI_RESET"
        ;;
      client-*'|'*SUCCESS*)
        printf '%s  %s%s%s\n' "$UI_GREEN" "$line" "$UI_RESET"
        ;;
      client-*'|'*FAILED*)
        printf '%s  %s%s%s\n' "$UI_RED" "$line" "$UI_RESET"
        ;;
      Successful*|Completed:*|"Operation succeeded:"*|"Completion rate:"*)
        printf '  %s%s[PASS] %s%s\n' "$UI_BOLD" "$UI_GREEN" "$line" "$UI_RESET"
        ;;
      "Consistency check: PASSED"*)
        printf '  %s%s[PASS] %s%s\n' "$UI_BOLD" "$UI_GREEN" "$line" "$UI_RESET"
        ;;
      "Consistency check: FAILED"*)
        printf '  %s%s[FAIL] %s%s\n' "$UI_BOLD" "$UI_RED" "$line" "$UI_RESET"
        ;;
      Failed:*|"Failed "*|"Transport failures:"*|"Operation failed:"*)
        value="${line#*:}"
        value="${value# }"
        if [[ "$value" =~ ^0($|/) ]]; then
          printf '  %s%s[ OK ] %s%s\n' "$UI_BOLD" "$UI_GREEN" "$line" "$UI_RESET"
        else
          printf '  %s%s[FAIL] %s%s\n' "$UI_BOLD" "$UI_RED" "$line" "$UI_RESET"
        fi
        ;;
      Throughput:*|"Average latency:"*|"Total time:"*)
        printf '  %s%s%s%s\n' "$UI_BOLD" "$UI_CYAN" "$line" "$UI_RESET"
        ;;
      *:*)
        label="${line%%:*}"
        value="${line#*:}"
        value="${value# }"
        ui_kv "$label" "$value"
        ;;
      '') printf '\n' ;;
      *) printf '  %s\n' "$line" ;;
    esac
  done <"$report"
}

ui_report_value() {
  local report="$1" label="$2" value
  value="$(sed -n "s/^${label}:[[:space:]]*//p" "$report" | tail -n 1)"
  printf '%s' "${value:-not available}"
}

ui_group_integer() {
  local digits="$1" grouped=""
  if [[ ! "$digits" =~ ^[0-9]+$ ]]; then
    printf '%s' "$digits"
    return
  fi
  while [ "${#digits}" -gt 3 ]; do
    grouped=",${digits: -3}$grouped"
    digits="${digits:0:${#digits}-3}"
  done
  printf '%s%s' "$digits" "$grouped"
}

ui_render_load_report() {
  local report="$1"
  local experiment workers total_requests concurrency operation target started_at
  local completed transport_fail operation_ok operation_fail completion_rate
  local total_time throughput average_latency consistency
  local raw_output seat_map conflicts server_log summary
  local rate_number rate_integer bar_width=28 filled empty filled_bar empty_bar

  if [ ! -t 1 ] && [ "${FORCE_COLOR:-0}" != 1 ]; then
    cat "$report"
    return
  fi

  experiment="$(ui_report_value "$report" 'Experiment')"
  workers="$(ui_report_value "$report" 'Workers')"
  total_requests="$(ui_report_value "$report" 'Total requests')"
  concurrency="$(ui_report_value "$report" 'Concurrency')"
  operation="$(ui_report_value "$report" 'Operation')"
  target="$(ui_report_value "$report" 'Target seat')"
  started_at="$(ui_report_value "$report" 'Started at')"
  completed="$(ui_report_value "$report" 'Completed')"
  transport_fail="$(ui_report_value "$report" 'Transport failures')"
  operation_ok="$(ui_report_value "$report" 'Operation succeeded')"
  operation_fail="$(ui_report_value "$report" 'Operation failed')"
  completion_rate="$(ui_report_value "$report" 'Completion rate')"
  total_time="$(ui_report_value "$report" 'Total time')"
  throughput="$(ui_report_value "$report" 'Throughput')"
  average_latency="$(ui_report_value "$report" 'Average latency')"
  consistency="$(ui_report_value "$report" 'Consistency check')"
  raw_output="$(ui_report_value "$report" 'Raw benchmark output')"
  seat_map="$(ui_report_value "$report" 'Seat map snapshot')"
  conflicts="$(ui_report_value "$report" 'Conflict evidence')"
  server_log="$(ui_report_value "$report" 'Server log')"
  summary="$(ui_report_value "$report" 'Machine-readable summary')"

  ui_banner "AIRPLANE RESERVATION - LOAD TEST RESULT"
  printf '\n%s%s[ RUN OVERVIEW ]%s\n' "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
  ui_rule '-'
  printf '  %-14s : %-20.20s  %-14s : %s\n' \
    'Experiment' "$experiment" 'Workers' "$workers"
  printf '  %-14s : %-20.20s  %-14s : %s\n' \
    'Operation' "$operation" 'Target seat' "$target"
  printf '  %-14s : %-20.20s  %-14s : %s\n' \
    'Total requests' "$(ui_group_integer "$total_requests")" \
    'Concurrency' "$(ui_group_integer "$concurrency")"

  printf '\n%s%s[ PERFORMANCE ]%s\n' "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
  ui_rule '-'
  printf '  %s┌──────────────────────┬──────────────────────┬──────────────────────┐%s\n' "$UI_CYAN" "$UI_RESET"
  printf '  %s│%s %-20s %s│%s %-20s %s│%s %-20s %s│%s\n' \
    "$UI_CYAN" "$UI_RESET" 'THROUGHPUT' "$UI_CYAN" "$UI_RESET" \
    'AVERAGE LATENCY' "$UI_CYAN" "$UI_RESET" 'TOTAL TIME' "$UI_CYAN" "$UI_RESET"
  printf '  %s├──────────────────────┼──────────────────────┼──────────────────────┤%s\n' "$UI_CYAN" "$UI_RESET"
  printf '  %s│%s %s%-20.20s%s %s│%s %s%-20.20s%s %s│%s %s%-20.20s%s %s│%s\n' \
    "$UI_CYAN" "$UI_RESET" "$UI_BOLD$UI_GREEN" "$throughput" "$UI_RESET" \
    "$UI_CYAN" "$UI_RESET" "$UI_BOLD$UI_MAGENTA" "$average_latency" "$UI_RESET" \
    "$UI_CYAN" "$UI_RESET" "$UI_BOLD$UI_CYAN" "$total_time" "$UI_RESET" \
    "$UI_CYAN" "$UI_RESET"
  printf '  %s└──────────────────────┴──────────────────────┴──────────────────────┘%s\n' "$UI_CYAN" "$UI_RESET"

  printf '\n%s%s[ REQUEST OUTCOME ]%s\n' "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
  ui_rule '-'
  rate_number="${completion_rate%%%}"
  rate_integer="${rate_number%%.*}"
  [[ "$rate_integer" =~ ^[0-9]+$ ]] || rate_integer=0
  [ "$rate_integer" -le 100 ] || rate_integer=100
  filled=$((rate_integer * bar_width / 100))
  empty=$((bar_width - filled))
  printf -v filled_bar '%*s' "$filled" ''
  printf -v empty_bar '%*s' "$empty" ''
  filled_bar="${filled_bar// /█}"
  empty_bar="${empty_bar// /░}"
  printf '  Completion  %s%s%s%s%s  %s%s%s\n' \
    "$UI_GREEN" "$filled_bar" "$UI_BLUE" "$empty_bar" "$UI_RESET" \
    "$UI_BOLD" "$completion_rate" "$UI_RESET"
  printf '  %-18s : %s%s / %s responses%s\n' 'Completed' \
    "$UI_GREEN" "$(ui_group_integer "$completed")" "$(ui_group_integer "$total_requests")" "$UI_RESET"
  if [ "$transport_fail" = 0 ]; then
    printf '  %-18s : %s%s[PASS] 0 failures%s\n' 'Transport' "$UI_BOLD" "$UI_GREEN" "$UI_RESET"
  else
    printf '  %-18s : %s%s[FAIL] %s failures%s\n' 'Transport' \
      "$UI_BOLD" "$UI_RED" "$(ui_group_integer "$transport_fail")" "$UI_RESET"
  fi
  printf '  %-18s : %s%s succeeded%s' 'Operation' \
    "$UI_GREEN" "$(ui_group_integer "$operation_ok")" "$UI_RESET"
  if [ "$operation_fail" = 0 ]; then
    printf '    %s0 rejected/failed%s\n' "$UI_GREEN" "$UI_RESET"
  else
    printf '    %s%s rejected/failed%s\n' \
      "$UI_YELLOW" "$(ui_group_integer "$operation_fail")" "$UI_RESET"
  fi
  case "$consistency" in
    PASSED*) printf '  %-18s : %s%s[PASS] %s%s\n' 'Consistency' "$UI_BOLD" "$UI_GREEN" "$consistency" "$UI_RESET" ;;
    *) printf '  %-18s : %s%s[FAIL] %s%s\n' 'Consistency' "$UI_BOLD" "$UI_RED" "$consistency" "$UI_RESET" ;;
  esac

  printf '\n%s%s[ SAVED ARTIFACTS ]%s\n' "$UI_BOLD" "$UI_BLUE" "$UI_RESET"
  ui_rule '-'
  printf '  %s•%s %-23s %s\n' "$UI_CYAN" "$UI_RESET" 'Raw benchmark' "$raw_output"
  printf '  %s•%s %-23s %s\n' "$UI_CYAN" "$UI_RESET" 'Seat map' "$seat_map"
  printf '  %s•%s %-23s %s\n' "$UI_CYAN" "$UI_RESET" 'Conflict evidence' "$conflicts"
  printf '  %s•%s %-23s %s\n' "$UI_CYAN" "$UI_RESET" 'Server log' "$server_log"
  printf '  %s•%s %-23s %s\n' "$UI_CYAN" "$UI_RESET" 'Machine summary' "$summary"
  printf '\n  %sStarted at%s %s\n' "$UI_YELLOW" "$UI_RESET" "$started_at"
}

ui_render_seat_map() {
  local map_file="$1" conflict_file="${2:-}" line seat owner row column label color
  local label_length left_pad right_pad clients final_owner
  local available_count=0 reserved_count=0 conflict_count=0
  local -a seat_state=() seat_owner=() conflict_clients=() conflict_owner=()

  for ((seat = 1; seat <= 20; seat++)); do
    seat_state[seat]=unknown
    seat_owner[seat]=""
  done

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^Seat[[:space:]]([0-9]+)[[:space:]]:[[:space:]]AVAILABLE$ ]]; then
      seat="${BASH_REMATCH[1]}"
      if [ "$seat" -ge 1 ] && [ "$seat" -le 20 ]; then
        seat_state[seat]=available
      fi
    elif [[ "$line" =~ ^Seat[[:space:]]([0-9]+)[[:space:]]:[[:space:]]RESERVED[[:space:]]by[[:space:]]Client-([0-9]+)$ ]]; then
      seat="${BASH_REMATCH[1]}"
      owner="${BASH_REMATCH[2]}"
      if [ "$seat" -ge 1 ] && [ "$seat" -le 20 ]; then
        seat_state[seat]=reserved
        seat_owner[seat]="$owner"
      fi
    fi
  done <"$map_file"

  if [ -n "$conflict_file" ] && [ -r "$conflict_file" ]; then
    while IFS='|' read -r seat clients final_owner; do
      if [[ "$seat" =~ ^([1-9]|1[0-9]|20)$ ]] && [ -n "$clients" ]; then
        conflict_clients[seat]="$clients"
        conflict_owner[seat]="$final_owner"
        conflict_count=$((conflict_count + 1))
      fi
    done <"$conflict_file"
  fi

  ui_section "AIRPLANE SEAT MAP"
  printf '                       %s%s▲ FRONT%s\n' "$UI_BOLD" "$UI_CYAN" "$UI_RESET"
  printf '              %s┌──────────────┬──────────────┐%s\n' "$UI_CYAN" "$UI_RESET"
  printf '              %s│%s%s     LEFT     %s%s│%s%s    RIGHT     %s%s│%s\n' \
    "$UI_CYAN" "$UI_RESET" "$UI_BOLD" "$UI_RESET" \
    "$UI_CYAN" "$UI_RESET" "$UI_BOLD" "$UI_RESET" "$UI_CYAN" "$UI_RESET"
  printf '              %s├──────────────┼──────────────┤%s\n' "$UI_CYAN" "$UI_RESET"
  for ((row = 1; row <= 10; row++)); do
    printf '      Row %02d  %s│%s' "$row" "$UI_CYAN" "$UI_RESET"
    for column in left right; do
      if [ "$column" = left ]; then seat="$row"; else seat=$((row + 10)); fi
      if [ -n "${conflict_clients[seat]-}" ]; then
        printf -v label '[%02d:RACE]' "$seat"
        color="$UI_RED"
        [ "${seat_state[seat]}" = reserved ] && reserved_count=$((reserved_count + 1))
        [ "${seat_state[seat]}" = available ] && available_count=$((available_count + 1))
      else case "${seat_state[seat]}" in
        available)
          printf -v label '[%02d]' "$seat"
          color="$UI_GREEN"
          available_count=$((available_count + 1))
          ;;
        reserved)
          printf -v label '[%02d:C-%s]' "$seat" "${seat_owner[seat]}"
          color="$UI_RED"
          reserved_count=$((reserved_count + 1))
          ;;
        *)
          printf -v label '[%02d:?]' "$seat"
          color="$UI_YELLOW"
          ;;
      esac; fi
      label_length=${#label}
      left_pad=$(((14 - label_length) / 2))
      right_pad=$((14 - label_length - left_pad))
      printf '%*s%s%s%s%*s' "$left_pad" '' "$color" "$label" "$UI_RESET" "$right_pad" ''
      printf '%s│%s' "$UI_CYAN" "$UI_RESET"
    done
    printf '\n'
  done
  printf '              %s└──────────────┴──────────────┘%s\n' "$UI_CYAN" "$UI_RESET"
  printf '                       %s%s▼ TAIL%s\n\n' "$UI_BOLD" "$UI_CYAN" "$UI_RESET"
  printf '              %s● %d available%s    %s● %d reserved%s' \
    "$UI_GREEN" "$available_count" "$UI_RESET" \
    "$UI_RED" "$reserved_count" "$UI_RESET"
  if [ "$conflict_count" -gt 0 ]; then
    printf '    %s⚠ %d conflict%s' "$UI_RED" "$conflict_count" "$UI_RESET"
  fi
  printf '    Total 20\n'
  if [ "$conflict_count" -gt 0 ]; then
    printf '              %s⚠ RACE = multiple clients received SUCCESS%s\n' \
      "$UI_RED" "$UI_RESET"
  fi
  if [ "$conflict_count" -gt 0 ]; then
    printf '\n  %s%s[FAIL] CONSISTENCY CHECK%s\n' "$UI_BOLD" "$UI_RED" "$UI_RESET"
    printf '  Multiple clients received SUCCESS for the same seat.\n'
    for ((seat = 1; seat <= 20; seat++)); do
      [ -n "${conflict_clients[seat]-}" ] || continue
      printf '  %sSeat %02d%s  SUCCESS clients: %s\n' \
        "$UI_RED" "$seat" "$UI_RESET" "${conflict_clients[seat]}"
      printf '           Final stored owner: %s (last write won)\n' \
        "${conflict_owner[seat]:-unknown}"
    done
  fi
}
