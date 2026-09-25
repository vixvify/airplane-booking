#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER="${DOCKER:-docker}"
IMAGE="${AIRPLANE_IMAGE:-airplane-reservation:latest}"
CONTAINER="${AIRPLANE_CONTAINER_NAME:-airplane-reservation}"
MANAGED_LABEL="org.airplane-reservation.managed"

usage() {
  echo "Usage: bash scripts/container.sh {build|start [sequential|nosync|sync] [worker_count]|stop|status|mode|workers|exec [-i|-it] <command...>|logs [options]}" >&2
  exit 2
}

read_server_config() {
  local server_command pattern
  server_command="$("$DOCKER" inspect --format '{{json .Config.Cmd}}' "$CONTAINER")"
  pattern='^\["\./server","(sync|nosync)","([1-9][0-9]?)"\]$'
  if [[ ! "$server_command" =~ $pattern ]]; then
    echo "Unrecognized server command: $server_command" >&2
    return 1
  fi
  SERVER_MODE="${BASH_REMATCH[1]}"
  WORKER_COUNT="${BASH_REMATCH[2]}"
  if [ "$WORKER_COUNT" -gt 64 ]; then
    echo "Unrecognized worker count: $WORKER_COUNT (use 1-64)" >&2
    return 1
  fi
}

action="${1:-}"
[ "$#" -gt 0 ] || usage
shift

case "$action" in
  build)
    [ "$#" -eq 0 ] || usage
    exec "$DOCKER" build -t "$IMAGE" "$ROOT_DIR"
    ;;
  start)
    [ "$#" -le 2 ] || usage
    experiment="${1:-${AIRPLANE_EXPERIMENT:-nosync}}"
    case "$experiment" in
      sequential) mode=sync; workers=1 ;;
      nosync) mode=nosync; workers=3 ;;
      sync) mode=sync; workers=3 ;;
      *) echo "Unknown experiment: $experiment (use sequential, nosync, or sync)" >&2; exit 2 ;;
    esac
    if [ "$#" -eq 2 ]; then
      workers="$2"
      if [[ ! "$workers" =~ ^[1-9][0-9]?$ ]] || [ "$workers" -gt 64 ]; then
        echo "worker_count must be between 1 and 64" >&2
        exit 2
      fi
      if [ "$experiment" = sequential ] && [ "$workers" -ne 1 ]; then
        echo "sequential mode requires exactly 1 worker; use sync for multiple workers" >&2
        exit 2
      fi
    fi
    "$DOCKER" run -d --rm --name "$CONTAINER" \
      --label "$MANAGED_LABEL=true" \
      -e "AIRPLANE_LOG_MODE=${AIRPLANE_LOG_MODE:-verbose}" \
      "$IMAGE" ./server "$mode" "$workers"
    for _ in {1..100}; do
      if [ "$("$DOCKER" inspect --format '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)" != true ]; then
        "$DOCKER" logs "$CONTAINER" >&2 || true
        echo "Server container exited before becoming ready." >&2
        exit 1
      fi
      if "$DOCKER" logs "$CONTAINER" 2>&1 | grep -q 'Airplane Reservation Server started'; then
        echo "Server ready: $CONTAINER ($experiment, $workers worker(s))"
        exit 0
      fi
      sleep 0.1
    done
    "$DOCKER" logs "$CONTAINER" >&2 || true
    echo "Server container did not become ready." >&2
    exit 1
    ;;
  stop)
    [ "$#" -eq 0 ] || usage
    owner="$("$DOCKER" inspect --format "{{index .Config.Labels \"$MANAGED_LABEL\"}}" "$CONTAINER")"
    [ "$owner" = true ] || { echo "Refusing to stop unmanaged container: $CONTAINER" >&2; exit 1; }
    "$DOCKER" stop "$CONTAINER"
    # Containers started above use --rm. Docker may return from `stop` just
    # before the asynchronous removal releases the container name, causing an
    # immediate restart to fail with "name is already in use". Do not report a
    # completed stop until the daemon can no longer inspect the old container.
    for _ in {1..100}; do
      if ! "$DOCKER" inspect "$CONTAINER" >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.05
    done
    echo "Timed out waiting for container removal: $CONTAINER" >&2
    exit 1
    ;;
  status)
    [ "$#" -eq 0 ] || usage
    exec "$DOCKER" inspect --format '{{.State.Running}}' "$CONTAINER"
    ;;
  mode)
    [ "$#" -eq 0 ] || usage
    read_server_config
    if [ "$SERVER_MODE" = sync ] && [ "$WORKER_COUNT" -eq 1 ]; then
      echo sequential
    else
      echo "$SERVER_MODE"
    fi
    ;;
  workers)
    [ "$#" -eq 0 ] || usage
    read_server_config
    echo "$WORKER_COUNT"
    ;;
  exec)
    options=()
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -i|-it|-t) options+=("$1"); shift ;;
        *) break ;;
      esac
    done
    [ "$#" -gt 0 ] || usage
    exec "$DOCKER" exec "${options[@]}" "$CONTAINER" "$@"
    ;;
  logs)
    exec "$DOCKER" logs "$@" "$CONTAINER"
    ;;
  *) usage ;;
esac
