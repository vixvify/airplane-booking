#!/usr/bin/env bash
set -euo pipefail
echo "$*" >>"$MOCK_TRACE"
case "$1" in
  get)
    if [ "${MOCK_FAIL:-}" = get ]; then exit 41; fi
    if [[ "$*" == *jsonpath* ]]; then echo "true true true true true true"; fi ;;
  delete|wait) : ;;
  apply)
    printf '%s\n' "$*" >"$MOCK_STATE" ;;
  logs)
    if [ "${MOCK_FAIL:-}" = logs ]; then exit 42; fi
    if [[ " $* " == *" -f "* ]]; then
      if [ "${MOCK_FAIL:-}" = stream ]; then exit 43; fi
      exec tail -f /dev/null
    fi
    echo "[SEQ 1] [Worker-1] [Client-1] mock log" ;;
  exec)
    if [[ "$*" == *"./load_test"* ]]; then
      printf 'Completed       : 1000\nTransport Fail  : 0\nOperation OK    : 1000\n'
    elif [[ "$*" == *"sh -c"* ]]; then
      printf 'Seat 1 is AVAILABLE\nSUCCESS: Seat 1 reserved\nSUCCESS: Seat 2 reserved\nSeat 1 is RESERVED by Client-1\nSUCCESS: Seat 1 cancelled\nSUCCESS: Seat 2 cancelled\nGOODBYE\n'
    else
      id="${!#}"
      if [ "${MOCK_FAIL:-}" = "client-$id" ]; then echo "mock transport failure" >&2; exit 44; fi
      # Allow a short delay so premature log-stream exits are deterministic.
      sleep 0.05
      while read -r operation seat; do
        case "$operation" in
          RESERVE)
            if [ "$id" = 1 ] || { grep -q 'k8s/pod.yaml' "$MOCK_STATE" && [ "$id" -le 3 ]; }; then
              echo "SUCCESS: Seat $seat reserved"
            else echo "FAILED: Transaction cancelled"; fi ;;
          STATUS) echo "Seat $seat is AVAILABLE" ;;
          LIST) echo "===== Airplane Seat Map =====" ;;
          CANCEL) echo "SUCCESS: Seat $seat cancelled" ;;
          QUIT) echo GOODBYE ;;
        esac
      done
    fi ;;
  *) echo "Unexpected kubectl call: $*" >&2; exit 45 ;;
esac
