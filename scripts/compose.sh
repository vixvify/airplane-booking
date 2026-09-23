#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="${SCRIPT_PATH%/*}"
[[ "$SCRIPT_DIR" != "$SCRIPT_PATH" ]] || SCRIPT_DIR="."
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER="${DOCKER:-docker}"
EXPERIMENT="${COMPOSE_EXPERIMENT:-nosync}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${ROOT_DIR##*/}}"
COMPOSE_ARGS=(
  --project-directory "$ROOT_DIR/compose"
  --project-name "$PROJECT_NAME"
  -f "$ROOT_DIR/compose/compose.yaml"
)

case "$EXPERIMENT" in
  sequential) COMPOSE_ARGS+=(-f "$ROOT_DIR/compose/compose.sequential.yaml") ;;
  sync) COMPOSE_ARGS+=(-f "$ROOT_DIR/compose/compose.sync.yaml") ;;
  nosync) ;;
  *) echo "Unknown COMPOSE_EXPERIMENT: $EXPERIMENT (use sequential, nosync, or sync)" >&2; exit 2 ;;
esac

exec "$DOCKER" compose "${COMPOSE_ARGS[@]}" "$@"
