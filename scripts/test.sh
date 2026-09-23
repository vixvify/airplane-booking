#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
source "$ROOT_DIR/scripts/lib/result_paths.sh"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
RUN_DIR="$(create_result_dir tests suite)"
export RESULTS_DIR
echo "Test artifacts: $RUN_DIR"
make -C "$ROOT_DIR" test 2>&1 | tee "$RUN_DIR/test-output.log"
