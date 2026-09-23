#!/usr/bin/env bash
# Shared transport for demos. The Compose stack must already be running.
compose() {
  bash "$ROOT_DIR/scripts/compose.sh" "$@"
}

init_runtime() {
  RUNTIME="${RUNTIME:-compose}"
  case "$RUNTIME" in
    compose)
      local services
      services="$(compose ps --status running --services)"
      if ! grep -qx server <<<"$services"; then
        echo "Compose server is not running. Start the stack with: bash scripts/compose.sh up -d --build" >&2
        return 1
      fi
      ;;
    local) : "${SERVER_LOG:?Set SERVER_LOG to the running server log file}"
           [ -r "$SERVER_LOG" ] || { echo "Cannot read SERVER_LOG" >&2; return 1; } ;;
    *) echo "Unknown RUNTIME: $RUNTIME (use compose or local)" >&2; return 1 ;;
  esac
}

runtime_client() {
  local id="$1"
  case "$RUNTIME" in
    compose) compose exec -i "client-$id" ./client "$id" ;;
    local) "$ROOT_DIR/client" "$id" ;;
  esac
}

# exec makes the background PID the actual log process, so cleanup stops it.
runtime_live_logs() {
  case "$RUNTIME" in
    compose) exec bash "$ROOT_DIR/scripts/compose.sh" logs -f --since "$STARTED_AT" --timestamps server ;;
    local) exec tail -s 0.05 -c "+$LOCAL_LOG_START" -f "$SERVER_LOG" ;;
  esac
}

runtime_log_snapshot() {
  case "$RUNTIME" in
    compose) compose logs --since "$STARTED_AT" --timestamps server ;;
    local) tail -c "+$LOCAL_LOG_START" "$SERVER_LOG" ;;
  esac
}
