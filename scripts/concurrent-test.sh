#!/bin/bash

POD_NAME="airplane-reservation"
SEAT_ID=10

echo "===================================="
echo " Airplane Reservation Race Test"
echo "===================================="
echo "Target seat: $SEAT_ID"
echo

kubectl exec "$POD_NAME" -c client-1 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 1" &

kubectl exec "$POD_NAME" -c client-2 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 2" &

kubectl exec "$POD_NAME" -c client-3 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 3" &

kubectl exec "$POD_NAME" -c client-4 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 4" &

kubectl exec "$POD_NAME" -c client-5 -- \
  sh -c "echo 'RESERVE $SEAT_ID' | ./client 5" &

wait

echo
echo "Race test finished."