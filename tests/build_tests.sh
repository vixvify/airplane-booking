#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
TEST_DIR="$(mktemp -d "$RESULTS_DIR/build-XXXXXXXX")"
mkdir "$TEST_DIR/project"
cp "$ROOT_DIR/Makefile" "$TEST_DIR/project/"
cp -R "$ROOT_DIR/src" "$TEST_DIR/project/"
cd "$TEST_DIR/project"
make -j2 all >"$TEST_DIR/initial-build.txt" 2>&1
make -q all
echo "[PASS] unchanged sources do not rebuild"

sleep 1
touch src/client/client.cpp
make -n client >"$TEST_DIR/source-plan.txt"
grep -q -- '-c src/client/client.cpp' "$TEST_DIR/source-plan.txt"
grep -q -- '-o client' "$TEST_DIR/source-plan.txt"
make client >"$TEST_DIR/source-build.txt" 2>&1
make -q all
echo "[PASS] editing a source recompiles and relinks its executable"

sleep 1
touch src/models/message.h
make -n all >"$TEST_DIR/header-plan.txt"
for binary in server client load_test; do
  grep -q -- "-o $binary" "$TEST_DIR/header-plan.txt"
done
make -j2 all >"$TEST_DIR/header-build.txt" 2>&1
make -q all
echo "[PASS] editing a shared header rebuilds all affected executables"
