#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_TRACE"
command="${1:-}"
shift || true

case "$command" in
  build) echo "Mock image built" ;;
  run) echo "mock-container-id" ;;
  stop) echo "airplane-reservation" ;;
  inspect)
    if [ "${1:-}" = --format ]; then
      format="$2"
      case "$format" in
        *'.State.Running'*)
          [ "${MOCK_FAIL:-}" != status ] || exit 41
          echo true ;;
        *'.Config.Cmd'*)
          if [ -n "${MOCK_SERVER_COMMAND:-}" ]; then
            printf '%s\n' "$MOCK_SERVER_COMMAND"
          else
            echo '["./server","sync","3"]'
          fi
          ;;
        *'org.airplane-reservation.managed'*) echo true ;;
        *) echo "Unexpected inspect format: $format" >&2; exit 45 ;;
      esac
    else
      echo "Unexpected inspect call: $*" >&2
      exit 45
    fi
    ;;
  logs)
    if [[ " $* " == *" -f "* ]]; then
      [ "${MOCK_FAIL:-}" != stream ] || exit 43
      exec tail -f /dev/null
    fi
    [ "${MOCK_FAIL:-}" != logs ] || exit 42
    echo "Airplane Reservation Server started"
    echo "[SEQ 1] [Worker-1] [Client-1] mock log"
    ;;
  exec)
    while [[ "${1:-}" == -i || "${1:-}" == -it || "${1:-}" == -t ]]; do shift; done
    container="${1:-}"
    [ -n "$container" ] || exit 45
    shift
    case "${1:-}" in
      ./client)
        id="${2:-}"
        [ "${MOCK_FAIL:-}" != "client-$id" ] || { echo "mock client failure" >&2; exit 44; }
        while read -r operation seat; do
          case "$operation" in
            LIST)
              echo "===== Airplane Seat Map ====="
              for seat_id in {1..20}; do
                if [ "${MOCK_DEMO_FINAL:-}" = 1 ]; then
                  case "$seat_id" in
                    2) echo "Seat 2 : RESERVED by Client-1"; continue ;;
                    3) echo "Seat 3 : RESERVED by Client-2"; continue ;;
                    6) echo "Seat 6 : RESERVED by Client-3"; continue ;;
                    7) echo "Seat 7 : RESERVED by Client-4"; continue ;;
                    10) echo "Seat 10 : RESERVED by Client-5"; continue ;;
                  esac
                fi
                echo "Seat $seat_id : AVAILABLE"
              done
              echo "============================="
              ;;
            STATUS) echo "Seat $seat is AVAILABLE" ;;
            RESERVE)
              if [ "${MOCK_RESERVE_FAIL_CLIENT:-}" = "client-$id" ]; then
                echo "FAILED: Transaction cancelled because Seat $seat is already reserved"
              else
                for seat_id in $seat; do echo "SUCCESS: Seat $seat_id reserved"; done
              fi
              ;;
            CANCEL) for seat_id in $seat; do echo "SUCCESS: Seat $seat_id cancelled"; done ;;
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
      *) echo "Unexpected docker exec: $*" >&2; exit 46 ;;
    esac
    ;;
  *) echo "Unexpected docker command: $command $*" >&2; exit 45 ;;
esac
