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
  printf '              %s[01]%s available    %s[10:C-1]%s reserved' \
    "$UI_GREEN" "$UI_RESET" "$UI_RED" "$UI_RESET"
  if [ "$conflict_count" -gt 0 ]; then
    printf '    %s[10:RACE]%s conflicting successes' "$UI_RED" "$UI_RESET"
  fi
  printf '\n'
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
