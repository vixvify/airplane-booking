#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
RESULTS_DIR="$(mktemp -d "$RESULTS_DIR/suite-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXXXX")"
export RESULTS_DIR
echo "Test artifacts: $RESULTS_DIR"
make -C "$ROOT_DIR" test 2>&1 | tee "$RESULTS_DIR/test-output.txt"
