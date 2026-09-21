#!/usr/bin/env bash
# Shared transport for demos. No server/pod is created or deleted here.
resolve_kubectl() {
  if [ -n "${KUBECTL:-}" ]; then
    command -v "$KUBECTL" >/dev/null 2>&1 || [ -x "$KUBECTL" ] || {
      echo "KUBECTL is not executable: $KUBECTL" >&2; return 1;
    }
    return
  fi
  local candidate
  for candidate in kubectl.exe \
    "/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" \
    "/mnt/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" kubectl; do
    if command -v "$candidate" >/dev/null 2>&1; then
      KUBECTL="$candidate"
      return
    fi
  done
  echo "kubectl not found. Set KUBECTL or choose RUNTIME=local/docker." >&2
  return 1
}

init_runtime() {
  RUNTIME="${RUNTIME:-k8s}"
  POD_NAME="${POD_NAME:-airplane-reservation}"
  case "$RUNTIME" in
    k8s) resolve_kubectl
         "$KUBECTL" get pod "$POD_NAME" >/dev/null ;;
    docker) DOCKER="${DOCKER:-docker}"
            : "${CONTAINER_NAME:?Set CONTAINER_NAME to the running server container}"
            "$DOCKER" inspect "$CONTAINER_NAME" >/dev/null ;;
    local) : "${SERVER_LOG:?Set SERVER_LOG to the running server log file}"
           [ -r "$SERVER_LOG" ] || { echo "Cannot read SERVER_LOG" >&2; return 1; } ;;
    *) echo "Unknown RUNTIME: $RUNTIME (use k8s, docker, or local)" >&2; return 1 ;;
  esac
}

runtime_client() {
  local id="$1"
  case "$RUNTIME" in
    k8s) "$KUBECTL" exec -i "$POD_NAME" -c "client-$id" -- ./client "$id" ;;
    docker) "$DOCKER" exec -i "$CONTAINER_NAME" ./client "$id" ;;
    local) "$ROOT_DIR/client" "$id" ;;
  esac
}

# exec makes the background PID the actual log process, so cleanup stops it.
runtime_live_logs() {
  case "$RUNTIME" in
    k8s) exec "$KUBECTL" logs -f "$POD_NAME" -c server --since-time="$STARTED_AT" --timestamps ;;
    docker) exec "$DOCKER" logs -f --since "$STARTED_AT" --timestamps "$CONTAINER_NAME" ;;
    local) exec tail -s 0.05 -c "+$LOCAL_LOG_START" -f "$SERVER_LOG" ;;
  esac
}

runtime_log_snapshot() {
  case "$RUNTIME" in
    k8s) "$KUBECTL" logs "$POD_NAME" -c server --since-time="$STARTED_AT" --timestamps ;;
    docker) "$DOCKER" logs --since "$STARTED_AT" --timestamps "$CONTAINER_NAME" ;;
    local) tail -c "+$LOCAL_LOG_START" "$SERVER_LOG" ;;
  esac
}
