#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER_SCRIPT="$ROOT_DIR/scripts/container.sh"
source "$ROOT_DIR/scripts/lib/terminal_ui.sh"
WIDTH=76
SELECTED=0
KEY=""

SCREEN_ACTIVE=false
FRAME=()
PREVIOUS_FRAME=()
CYAN=$'\033[1;36m'
SELECTED_STYLE=$'\033[30;46m'
RESET_STYLE=$'\033[0m'

enter_screen() {
  # Keep redraws out of the normal scrollback buffer. Without this, some
  # Windows Terminal/Git Bash combinations append every frame to the screen.
  printf '\033[?1049h\033[H\033[2J'
  SCREEN_ACTIVE=true
}

leave_screen() {
  show_cursor
  printf '\033[0m'
  if [ "$SCREEN_ACTIVE" = true ]; then
    printf '\033[?1049l'
    SCREEN_ACTIVE=false
  fi
}

begin_output_screen() {
  leave_screen
  # Start every run with a clean normal buffer. The previous run remains in
  # results/, while the current run gets an uncluttered, scrollable terminal.
  printf '\033[3J\033[H\033[2J'
}

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
clear_screen() { printf '\033[H\033[2J'; }
cleanup_terminal() {
  leave_screen
}
trap cleanup_terminal EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

begin_frame() { FRAME=(); }
frame_add() { FRAME+=("$1"); }

line_text() {
  printf -v LINE_BUFFER '+%*s+' "$((WIDTH - 2))" ''
  LINE_BUFFER="${LINE_BUFFER// /-}"
}

row_text() { printf -v LINE_BUFFER '| %-*s |' "$((WIDTH - 4))" "$1"; }
line() { line_text; frame_add "$LINE_BUFFER"; }
row() { row_text "$1"; frame_add "$LINE_BUFFER"; }

invalidate_frame() { PREVIOUS_FRAME=(); }

render_frame() {
  local index max_count old_line new_line
  max_count=${#FRAME[@]}
  [ "${#PREVIOUS_FRAME[@]}" -gt "$max_count" ] && max_count=${#PREVIOUS_FRAME[@]}

  for ((index = 0; index < max_count; index++)); do
    old_line="${PREVIOUS_FRAME[index]-}"
    new_line="${FRAME[index]-}"
    if [ "$old_line" != "$new_line" ]; then
      printf '\033[%d;1H\033[2K%s' "$((index + 1))" "$new_line"
    fi
  done

  PREVIOUS_FRAME=("${FRAME[@]}")
  printf '\033[%d;1H' "$(( ${#FRAME[@]} + 1 ))"
}

title() {
  begin_frame
  line_text; frame_add "${CYAN}${LINE_BUFFER}${RESET_STYLE}"
  row_text "AIRPLANE RESERVATION - TERMINAL CONTROL PANEL"; frame_add "${CYAN}${LINE_BUFFER}${RESET_STYLE}"
  line_text; frame_add "${CYAN}${LINE_BUFFER}${RESET_STYLE}"
}

read_key() {
  local first rest=""
  IFS= read -rsn1 first || first=q
  if [ "$first" = $'\033' ]; then
    IFS= read -rsn2 -t 0.08 rest || true
    case "$rest" in
      '[A') KEY=up ;; '[B') KEY=down ;; '[C') KEY=right ;; '[D') KEY=left ;;
      *) KEY=back ;;
    esac
  else
    case "$first" in
      '') KEY=enter ;; q|Q) KEY=quit ;; *) KEY="$first" ;;
    esac
  fi
}

option() {
  local index="$1" text="$2"
  if [ "$index" -eq "$SELECTED" ]; then
    printf -v LINE_BUFFER '  > %-*s' "$((WIDTH - 6))" "$text"
    frame_add "${SELECTED_STYLE}${LINE_BUFFER}${RESET_STYLE}"
  else
    printf -v LINE_BUFFER '    %-*s' "$((WIDTH - 6))" "$text"
    frame_add "$LINE_BUFFER"
  fi
}

pause_screen() {
  printf '\n%s%sPress Enter to return to the menu...%s' "$UI_BOLD" "$UI_YELLOW" "$UI_RESET"
  while true; do read_key; [ "$KEY" = enter ] && break; done
}

prompt_number() {
  local label="$1" current="$2" minimum="$3" maximum="$4" entered prompt_row
  prompt_row=$(( ${#FRAME[@]} + 1 ))
  show_cursor
  printf '\033[%d;1H\033[J%s [%s]: ' "$prompt_row" "$label" "$current"
  IFS= read -r entered
  printf '\033[%d;1H\033[J' "$prompt_row"
  hide_cursor
  if [ -z "$entered" ]; then
    PROMPT_RESULT="$current"
  elif [[ "$entered" =~ ^[0-9]+$ ]] && [ "$entered" -ge "$minimum" ] && [ "$entered" -le "$maximum" ]; then
    PROMPT_RESULT="$entered"
  else
    PROMPT_RESULT="$current"
  fi
}

adjust_number() {
  local current="$1" delta="$2" minimum="$3" maximum="$4" next
  next=$((current + delta))
  [ "$next" -lt "$minimum" ] && next="$minimum"
  [ "$next" -gt "$maximum" ] && next="$maximum"
  ADJUSTED="$next"
}

toggle() {
  if [ "$1" = yes ]; then TOGGLED=no; else TOGGLED=yes; fi
}

cycle_value() {
  local current="$1" direction="$2"
  shift 2
  local values=("$@") index=0
  for index in "${!values[@]}"; do
    [ "${values[index]}" = "$current" ] && break
  done
  index=$((index + direction))
  [ "$index" -lt 0 ] && index=$((${#values[@]} - 1))
  [ "$index" -ge "${#values[@]}" ] && index=0
  CYCLED="${values[index]}"
}

prepare_server() {
  local experiment="$1" workers="$2" log_mode="$3" rebuild="$4"
  if [ "$rebuild" = yes ]; then
    bash "$CONTAINER_SCRIPT" build || return 1
  fi
  if bash "$CONTAINER_SCRIPT" status >/dev/null 2>&1; then
    bash "$CONTAINER_SCRIPT" stop || return 1
  fi
  AIRPLANE_LOG_MODE="$log_mode" bash "$CONTAINER_SCRIPT" start "$experiment" "$workers"
}

run_task() {
  local task="$1" workers="$2" clients="$3" command="$4" seat="$5" log_mode="$6" rebuild="$7"
  local experiment
  case "$task" in
    exp1) experiment=sequential; workers=1 ;;
    exp2) experiment=nosync ;;
    exp3|demo1) experiment=sync ;;
  esac
  invalidate_frame
  begin_output_screen
  echo "============================================================"
  echo "Starting $task..."
  echo "============================================================"
  echo
  if prepare_server "$experiment" "$workers" "$log_mode" "$rebuild"; then
    if [ "$task" = demo1 ]; then
      bash "$ROOT_DIR/scripts/demo1.sh"
    else
      CLIENT_COUNT="$clients" COMMAND="$command" SEAT_ID="$seat" \
        bash "$ROOT_DIR/scripts/concurrent-test.sh"
    fi
    status=$?
  else
    status=$?
  fi
  echo
  if [ "$status" -eq 0 ]; then echo "DONE: task completed successfully."; else echo "FAILED: exit code $status"; fi
  pause_screen
  enter_screen
  invalidate_frame
  hide_cursor
}

run_load() {
  local experiment="$1" workers="$2" requests="$3" concurrency="$4"
  local operation="$5" seat_mode="$6" seat="$7" log_mode="$8" rebuild="$9"
  invalidate_frame
  begin_output_screen
  echo "============================================================"
  echo "Starting load test..."
  echo "============================================================"
  echo
  if prepare_server "$experiment" "$workers" "$log_mode" "$rebuild"; then
    if [ "$seat_mode" = round-robin ]; then
      bash "$ROOT_DIR/scripts/load-test.sh" "$requests" "$concurrency" "$operation"
    else
      bash "$ROOT_DIR/scripts/load-test.sh" "$requests" "$concurrency" "$operation" "$seat"
    fi
    status=$?
  else
    status=$?
  fi
  echo
  if [ "$status" -eq 0 ]; then echo "DONE: load test completed successfully."; else echo "FAILED: exit code $status"; fi
  pause_screen
  enter_screen
  invalidate_frame
  hide_cursor
}

task_form() {
  local task="$1" workers=3 clients=5 command=RESERVE seat=10 log_mode=verbose rebuild=yes
  [ "$task" = exp1 ] && workers=1
  SELECTED=0
  while true; do
    title
    case "$task" in
      exp1) row "Experiment 1 - Sequential baseline" ;;
      exp2) row "Experiment 2 - Concurrent without synchronization" ;;
      exp3) row "Experiment 3 - Concurrent with synchronization" ;;
      demo1) row "Demo 1 - Five clients with mixed commands" ;;
    esac
    line
    local labels=() values=() kinds=()
    if [ "$task" != exp1 ]; then labels+=("Workers"); values+=("$workers"); kinds+=(workers); fi
    if [ "$task" != demo1 ]; then
      labels+=("Clients" "Command" "Target seat")
      values+=("$clients" "$command" "$seat")
      kinds+=(clients command seat)
    else
      labels+=("Clients"); values+=("5 (fixed by Demo 1)"); kinds+=(fixed)
    fi
    labels+=("Server logs" "Build image first" "RUN")
    values+=("$log_mode" "$rebuild" "Start server and execute")
    kinds+=(logs build run)
    for index in "${!labels[@]}"; do
      if [ "${kinds[index]}" = seat ] && [ "$command" = LIST ]; then
        option "$index" "${labels[index]}: disabled"
      else
        option "$index" "${labels[index]}: ${values[index]}"
      fi
    done
    line
    row "Arrow keys: navigate/change | Enter: edit/run | Esc: back | Q: quit"
    line
    render_frame
    read_key
    case "$KEY" in
      up) SELECTED=$((SELECTED - 1)); [ "$SELECTED" -lt 0 ] && SELECTED=$((${#labels[@]} - 1)) ;;
      down) SELECTED=$((SELECTED + 1)); [ "$SELECTED" -ge "${#labels[@]}" ] && SELECTED=0 ;;
      left|right|enter)
        direction=1; [ "$KEY" = left ] && direction=-1
        kind="${kinds[SELECTED]}"
        case "$kind" in
          workers)
            if [ "$KEY" = enter ]; then prompt_number "Workers (1-64)" "$workers" 1 64; workers="$PROMPT_RESULT"
            else adjust_number "$workers" "$direction" 1 64; workers="$ADJUSTED"; fi ;;
          clients)
            if [ "$KEY" = enter ]; then prompt_number "Clients (5-100)" "$clients" 5 100; clients="$PROMPT_RESULT"
            else adjust_number "$clients" "$direction" 5 100; clients="$ADJUSTED"; fi ;;
          command) cycle_value "$command" "$direction" RESERVE CANCEL STATUS LIST; command="$CYCLED" ;;
          seat)
            if [ "$command" != LIST ]; then
              if [ "$KEY" = enter ]; then prompt_number "Seat (1-20)" "$seat" 1 20; seat="$PROMPT_RESULT"
              else adjust_number "$seat" "$direction" 1 20; seat="$ADJUSTED"; fi
            fi ;;
          logs) cycle_value "$log_mode" "$direction" verbose quiet; log_mode="$CYCLED" ;;
          build) toggle "$rebuild"; rebuild="$TOGGLED" ;;
          run) [ "$KEY" = enter ] && run_task "$task" "$workers" "$clients" "$command" "$seat" "$log_mode" "$rebuild" ;;
        esac ;;
      back) return ;;
      quit) exit 0 ;;
    esac
  done
}

load_form() {
  local experiment=sync workers=3 requests=50000 concurrency=100
  local operation=STATUS seat_mode=round-robin seat=10 log_mode=quiet rebuild=yes
  SELECTED=0
  while true; do
    title
    row "Load Test - Logical clients and performance metrics"
    line
    labels=("Server mode" "Workers" "Total requests" "Concurrency / logical clients" "Operation" "Seat selection" "Target seat" "Server logs" "Build image first" "RUN")
    values=("$experiment" "$workers" "$requests" "$concurrency" "$operation" "$seat_mode" "$seat" "$log_mode" "$rebuild" "Start server and execute")
    kinds=(experiment workers requests concurrency operation seat_mode seat logs build run)
    for index in "${!labels[@]}"; do
      if [ "${kinds[index]}" = seat ] && [ "$seat_mode" = round-robin ]; then
        option "$index" "${labels[index]}: disabled"
      else
        option "$index" "${labels[index]}: ${values[index]}"
      fi
    done
    line
    row "Arrow keys: navigate/change | Enter: edit/run | Esc: back | Q: quit"
    line
    render_frame
    read_key
    case "$KEY" in
      up) SELECTED=$((SELECTED - 1)); [ "$SELECTED" -lt 0 ] && SELECTED=$((${#labels[@]} - 1)) ;;
      down) SELECTED=$((SELECTED + 1)); [ "$SELECTED" -ge "${#labels[@]}" ] && SELECTED=0 ;;
      left|right|enter)
        direction=1; [ "$KEY" = left ] && direction=-1
        kind="${kinds[SELECTED]}"
        case "$kind" in
          experiment)
            cycle_value "$experiment" "$direction" sequential nosync sync; experiment="$CYCLED"
            if [ "$experiment" = sequential ]; then workers=1; elif [ "$workers" -eq 1 ]; then workers=3; fi ;;
          workers)
            if [ "$experiment" = sequential ]; then workers=1
            elif [ "$KEY" = enter ]; then prompt_number "Workers (1-64)" "$workers" 1 64; workers="$PROMPT_RESULT"
            else adjust_number "$workers" "$direction" 1 64; workers="$ADJUSTED"; fi ;;
          requests)
            if [ "$KEY" = enter ]; then prompt_number "Total requests" "$requests" 1 2147473647; requests="$PROMPT_RESULT"
            else adjust_number "$requests" "$((direction * 100000))" 1 2147473647; requests="$ADJUSTED"; fi
            [ "$concurrency" -gt "$requests" ] && concurrency="$requests" ;;
          concurrency)
            if [ "$KEY" = enter ]; then prompt_number "Concurrency / logical clients" "$concurrency" 1 "$requests"; concurrency="$PROMPT_RESULT"
            else adjust_number "$concurrency" "$((direction * 10))" 1 "$requests"; concurrency="$ADJUSTED"; fi ;;
          operation) cycle_value "$operation" "$direction" STATUS RESERVE CANCEL; operation="$CYCLED" ;;
          seat_mode) cycle_value "$seat_mode" "$direction" round-robin fixed; seat_mode="$CYCLED" ;;
          seat)
            if [ "$seat_mode" = fixed ]; then
              if [ "$KEY" = enter ]; then prompt_number "Seat (1-20)" "$seat" 1 20; seat="$PROMPT_RESULT"
              else adjust_number "$seat" "$direction" 1 20; seat="$ADJUSTED"; fi
            fi ;;
          logs) cycle_value "$log_mode" "$direction" verbose quiet; log_mode="$CYCLED" ;;
          build) toggle "$rebuild"; rebuild="$TOGGLED" ;;
          run) [ "$KEY" = enter ] && run_load "$experiment" "$workers" "$requests" "$concurrency" "$operation" "$seat_mode" "$seat" "$log_mode" "$rebuild" ;;
        esac ;;
      back) return ;;
      quit) exit 0 ;;
    esac
  done
}

show_status() {
  local mode workers experiment sync_description
  invalidate_frame
  begin_output_screen
  ui_banner "AIRPLANE RESERVATION - SERVER STATUS"
  if bash "$CONTAINER_SCRIPT" status >/dev/null 2>&1; then
    mode="$(bash "$CONTAINER_SCRIPT" mode)"
    workers="$(bash "$CONTAINER_SCRIPT" workers)"
    case "$mode" in
      sequential)
        experiment="Experiment 1 - Sequential baseline"
        sync_description="Enabled (single worker)"
        ;;
      nosync)
        experiment="Experiment 2 - Concurrent without synchronization"
        sync_description="Disabled"
        ;;
      sync)
        experiment="Experiment 3 - Concurrent with synchronization"
        sync_description="Enabled (per-seat mutex)"
        ;;
    esac
    ui_success "Server is running and ready."
    ui_section "SERVER CONFIGURATION"
    ui_kv "Experiment" "$experiment"
    ui_kv "Mode" "$mode"
    ui_kv "Synchronization" "$sync_description"
    ui_kv "Workers" "$workers"
    ui_kv "Container" "${AIRPLANE_CONTAINER_NAME:-airplane-reservation}"
    ui_kv "Image" "${AIRPLANE_IMAGE:-airplane-reservation:latest}"
    ui_section "AVAILABLE ACTIONS"
    ui_note "Choose an experiment, Demo 1, or Load Test from the main menu."
    ui_note "Choose Stop Server when you are finished."
  else
    ui_note "Server is stopped."
    ui_section "EXPECTED RUNTIME"
    ui_kv "Container" "${AIRPLANE_CONTAINER_NAME:-airplane-reservation}"
    ui_kv "Image" "${AIRPLANE_IMAGE:-airplane-reservation:latest}"
    ui_note "Running any experiment will start the server automatically."
  fi
  pause_screen
  enter_screen
  invalidate_frame
  hide_cursor
}

stop_server_menu() {
  invalidate_frame
  leave_screen
  ui_banner "AIRPLANE RESERVATION - STOP SERVER"
  if bash "$CONTAINER_SCRIPT" status >/dev/null 2>&1; then
    bash "$CONTAINER_SCRIPT" stop
    ui_success "Server stopped successfully."
  else
    ui_note "Server is already stopped."
  fi
  pause_screen
  enter_screen
  invalidate_frame
  hide_cursor
}

main_menu() {
  local items=(
    "Experiment 1 - Sequential baseline"
    "Experiment 2 - Concurrent without synchronization"
    "Experiment 3 - Concurrent with synchronization"
    "Demo 1 - Five clients, mixed commands"
    "Load Test"
    "Server Status"
    "Stop Server"
    "Quit"
  )
  SELECTED=0
  hide_cursor
  while true; do
    title
    row "Choose a task. The launcher builds, starts, and runs it for you."
    line
    for index in "${!items[@]}"; do option "$index" "${items[index]}"; done
    line
    row "Use Up/Down and Enter. Press Q to quit."
    line
    render_frame
    read_key
    case "$KEY" in
      up) SELECTED=$((SELECTED - 1)); [ "$SELECTED" -lt 0 ] && SELECTED=$((${#items[@]} - 1)) ;;
      down) SELECTED=$((SELECTED + 1)); [ "$SELECTED" -ge "${#items[@]}" ] && SELECTED=0 ;;
      enter)
        case "$SELECTED" in
          0) task_form exp1 ;; 1) task_form exp2 ;; 2) task_form exp3 ;;
          3) task_form demo1 ;; 4) load_form ;; 5) show_status ;;
          6) stop_server_menu ;; 7) exit 0 ;;
        esac
        SELECTED=0 ;;
      quit) exit 0 ;;
    esac
  done
}

if [ "${MENU_LIBRARY_ONLY:-no}" != yes ]; then
  enter_screen
  main_menu
fi
