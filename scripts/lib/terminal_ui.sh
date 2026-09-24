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
        printf '  %s%s[PASS]%s %s\n' "$UI_BOLD" "$UI_GREEN" "$UI_RESET" "$line"
        ;;
      Failed:*|"Failed "*|"Transport failures:"*|"Operation failed:"*)
        value="${line#*:}"
        value="${value# }"
        if [[ "$value" =~ ^0($|/) ]]; then
          printf '  %s%s[ OK ]%s %s\n' "$UI_BOLD" "$UI_GREEN" "$UI_RESET" "$line"
        else
          printf '  %s%s[FAIL]%s %s\n' "$UI_BOLD" "$UI_RED" "$UI_RESET" "$line"
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
