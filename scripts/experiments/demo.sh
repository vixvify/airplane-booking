#!/usr/bin/env bash
set -euo pipefail

# Start the experiment server separately. This script only runs five clients.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEAT_ID="${SEAT_ID:-10}"
if [[ ! "$SEAT_ID" =~ ^([1-9]|1[0-9]|20)$ ]]; then
  printf 'SEAT_ID must be between 1 and 20\n' >&2
  exit 2
fi

printf 'Five clients concurrently reserve Seat %s (server must already be running).\n' "$SEAT_ID"
run_dir="$(mktemp -d)"
cleanup() {
  local id
  for id in {1..5}; do
    rm -f -- "$run_dir/client-$id.log"
  done
  rmdir -- "$run_dir"
}
trap cleanup EXIT

client_pids=()
for id in {1..5}; do
  (
    printf 'RESERVE %s\nQUIT\n' "$SEAT_ID" |
      bash "$ROOT_DIR/scripts/container.sh" exec -i ./client "$id" 2>&1 |
      tee "$run_dir/client-$id.log" |
      sed -u "s/^/Client-$id | /"
  ) &
  client_pids+=("$!")
done

client_failed=()
for index in "${!client_pids[@]}"; do
  if wait "${client_pids[index]}"; then
    client_failed[index]=0
  else
    client_failed[index]=1
  fi
done

success_count=0
rejected_count=0
error_count=0
printf '\nEXPERIMENT RESULT — SEAT %s\n' "$SEAT_ID"
for id in {1..5}; do
  file="$run_dir/client-$id.log"
  if [ "${client_failed[id-1]}" -ne 0 ]; then
    printf 'Client-%s : ERROR (client process failed)\n' "$id"
    error_count=$((error_count + 1))
  elif grep -Fqx "SUCCESS: Seat $SEAT_ID reserved" "$file"; then
    printf 'Client-%s : SUCCESS\n' "$id"
    success_count=$((success_count + 1))
  elif grep -q '^FAILED:' "$file"; then
    printf 'Client-%s : REJECTED\n' "$id"
    rejected_count=$((rejected_count + 1))
  else
    printf 'Client-%s : ERROR (no reservation result)\n' "$id"
    error_count=$((error_count + 1))
  fi
done
printf 'Summary  : %s successful, %s rejected, %s errors\n' \
  "$success_count" "$rejected_count" "$error_count"
if [ "$success_count" -gt 1 ]; then
  printf 'Observation: multiple clients received SUCCESS for the same seat (race observed).\n'
elif [ "$error_count" -eq 0 ] && [ "$success_count" -eq 1 ]; then
  printf 'Observation: one client received SUCCESS; no duplicate success observed.\n'
elif [ "$error_count" -eq 0 ]; then
  printf 'Observation: no client succeeded; check whether the seat was already reserved.\n'
fi
if [ "$error_count" -gt 0 ]; then
  printf 'Observation: incomplete result because one or more clients failed.\n'
  exit 1
fi
