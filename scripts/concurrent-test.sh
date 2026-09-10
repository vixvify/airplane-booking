#!/bin/bash

POD_NAME="airplane-reservation"
SEAT_ID=10
KUBECTL="${KUBECTL:-kubectl}"

if ! command -v "$KUBECTL" >/dev/null 2>&1; then
  if command -v kubectl.exe >/dev/null 2>&1; then
    KUBECTL="kubectl.exe"
  elif [ -x "/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" ]; then
    KUBECTL="/c/Program Files/Docker/Docker/resources/bin/kubectl.exe"
  else
    echo "kubectl was not found. Add kubectl to PATH or set KUBECTL." >&2
    exit 1
  fi
fi

echo "===================================="
echo " Airplane Reservation Concurrent Test"
echo "===================================="
echo "Target seat: $SEAT_ID"
echo

echo "Live server logs:"
echo "------------------------------------"
"$KUBECTL" logs -f "$POD_NAME" -c server --tail=0 --prefix &
LOG_PID=$!

cleanup() {
  kill "$LOG_PID" 2>/dev/null || true
  wait "$LOG_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

run_client() {
  local client_id="$1"
  "$KUBECTL" exec "$POD_NAME" -c "client-$client_id" -- \
    sh -c "echo 'RESERVE $SEAT_ID' | ./client $client_id 2>&1 | sed 's/^/[CLIENT-$client_id] /'"
}

run_client 1 &
CLIENT_1_PID=$!

run_client 2 &
CLIENT_2_PID=$!

run_client 3 &
CLIENT_3_PID=$!

run_client 4 &
CLIENT_4_PID=$!

run_client 5 &
CLIENT_5_PID=$!

wait "$CLIENT_1_PID" "$CLIENT_2_PID" "$CLIENT_3_PID" "$CLIENT_4_PID" "$CLIENT_5_PID"

echo
echo "Concurrent reservation test finished."
