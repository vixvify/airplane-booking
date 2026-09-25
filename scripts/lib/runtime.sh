#!/usr/bin/env bash
# Shared transport for demos. The server container must already be running.
container() {
  bash "$ROOT_DIR/scripts/container.sh" "$@"
}

init_runtime() {
  RUNTIME="${RUNTIME:-container}"
  case "$RUNTIME" in
    container)
      if [ "$(container status 2>/dev/null || true)" != true ]; then
        echo "Server container is not running. Run: bash scripts/container.sh build && bash scripts/container.sh start <experiment>" >&2
        return 1
      fi
      EXPERIMENT="$(container mode)"
      WORKER_COUNT="$(container workers)"
      case "$EXPERIMENT" in
        sequential|nosync|sync) ;;
        *) echo "Unrecognized running experiment: $EXPERIMENT" >&2; return 1 ;;
      esac
      ;;
    local) : "${SERVER_LOG:?Set SERVER_LOG to the running server log file}"
           [ -r "$SERVER_LOG" ] || { echo "Cannot read SERVER_LOG" >&2; return 1; } ;;
    *) echo "Unknown RUNTIME: $RUNTIME (use container or local)" >&2; return 1 ;;
  esac
  EXPERIMENT="${EXPERIMENT:-${AIRPLANE_EXPERIMENT:-local}}"
}

runtime_client() {
  local id="$1"
  case "$RUNTIME" in
    container) container exec -i ./client "$id" ;;
    local) "$ROOT_DIR/client" "$id" ;;
  esac
}

# exec makes the background PID the actual log process, so cleanup stops it.
runtime_live_logs() {
  case "$RUNTIME" in
    container) exec bash "$ROOT_DIR/scripts/container.sh" logs -f --since "$STARTED_AT" --timestamps ;;
    local) exec tail -s 0.05 -c "+$LOCAL_LOG_START" -f "$SERVER_LOG" ;;
  esac
}

runtime_log_snapshot() {
  case "$RUNTIME" in
    container) container logs --since "$STARTED_AT" --timestamps ;;
    local) tail -c "+$LOCAL_LOG_START" "$SERVER_LOG" ;;
  esac
}
