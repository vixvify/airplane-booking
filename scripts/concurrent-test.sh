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

"$KUBECTL" exec "$POD_NAME" -c client-1 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 1" &

"$KUBECTL" exec "$POD_NAME" -c client-2 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 2" &

"$KUBECTL" exec "$POD_NAME" -c client-3 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 3" &

"$KUBECTL" exec "$POD_NAME" -c client-4 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 4" &

"$KUBECTL" exec "$POD_NAME" -c client-5 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 5" &

wait

echo
echo "Concurrent reservation test finished."
