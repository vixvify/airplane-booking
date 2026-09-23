#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_TRACE"
[ "${1:-}" = compose ] || { echo "Expected docker compose" >&2; exit 45; }
shift
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-directory|--project-name|-f) shift 2 ;;
    *) break ;;
  esac
done
command="${1:-}"
shift || true
case "$command" in
  version) echo "Docker Compose mock" ;;
  ps)
    [ "${MOCK_FAIL:-}" != ps ] || exit 41
    printf 'server\nclient-1\nclient-2\nclient-3\nclient-4\nclient-5\n'
    ;;
  logs)
    if [[ " $* " == *" -f "* ]]; then
      [ "${MOCK_FAIL:-}" != stream ] || exit 43
      exec tail -f /dev/null
    fi
    [ "${MOCK_FAIL:-}" != logs ] || exit 42
    echo "[SEQ 1] [Worker-1] [Client-1] mock log"
    ;;
  exec)
    while [[ "${1:-}" == -i || "${1:-}" == -T ]]; do shift; done
    service="${1:-}"
    [ "${MOCK_FAIL:-}" != "$service" ] || { echo "mock client failure" >&2; exit 44; }
    shift
    case "${1:-}" in
      ./client)
        while read -r operation seat; do
          case "$operation" in
            LIST) echo "===== Airplane Seat Map =====" ;;
            STATUS) echo "Seat $seat is AVAILABLE" ;;
            RESERVE)
              if [ "${MOCK_RESERVE_FAIL_CLIENT:-}" = "$service" ]; then
                echo "FAILED: Transaction cancelled because Seat $seat is already reserved"
              else
                echo "SUCCESS: Seat $seat reserved"
              fi
              ;;
            CANCEL) echo "SUCCESS: Seat $seat cancelled" ;;
            QUIT) echo GOODBYE ;;
          esac
        done
        ;;
      ./load_test)
        echo "Completed       : 1000"
        echo "Transport Fail  : 0"
        echo "Operation OK    : 1000"
        echo "Throughput      : 12000 req/sec"
        ;;
      *) echo "Unexpected Compose exec: $*" >&2; exit 46 ;;
    esac
    ;;
  *) echo "Unexpected Compose command: $command $*" >&2; exit 45 ;;
esac
