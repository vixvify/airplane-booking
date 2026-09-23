#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
TEST_DIR_ROOT="$RESULTS_DIR/tests/build"
mkdir -p "$TEST_DIR_ROOT"
RUN_STAMP="$(date -u +%Y-%m-%d_%H-%M-%S)"
TEST_DIR="$TEST_DIR_ROOT/$RUN_STAMP"
suffix=2
while ! mkdir "$TEST_DIR" 2>/dev/null; do
  TEST_DIR="$TEST_DIR_ROOT/$RUN_STAMP-$suffix"
  suffix=$((suffix + 1))
done
mkdir "$TEST_DIR/project"
cp "$ROOT_DIR/Makefile" "$TEST_DIR/project/"
cp -R "$ROOT_DIR/src" "$TEST_DIR/project/"
cd "$TEST_DIR/project"
make -j2 all >"$TEST_DIR/initial-build.log" 2>&1
make -q all
echo "[PASS] unchanged sources do not rebuild"

sleep 1
touch src/client/client.cpp
make -n client >"$TEST_DIR/source-plan.log"
grep -q -- '-c src/client/client.cpp' "$TEST_DIR/source-plan.log"
grep -q -- '-o client' "$TEST_DIR/source-plan.log"
make client >"$TEST_DIR/source-build.log" 2>&1
make -q all
echo "[PASS] editing a source recompiles and relinks its executable"

sleep 1
touch src/models/message.h
make -n all >"$TEST_DIR/header-plan.log"
for binary in server client load_test; do
  grep -q -- "-o $binary" "$TEST_DIR/header-plan.log"
done
make -j2 all >"$TEST_DIR/header-build.log" 2>&1
make -q all
echo "[PASS] editing a shared header rebuilds all affected executables"
