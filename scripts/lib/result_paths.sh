#!/usr/bin/env bash

create_result_dir() {
  local category="$1"
  local kind="$2"
  local results_root="${RESULTS_DIR:-$ROOT_DIR/results}"
  local parent="$results_root/$category/$kind"
  local stamp run_dir suffix

  mkdir -p "$parent"
  stamp="$(date -u +%Y-%m-%d_%H-%M-%S)"
  run_dir="$parent/$stamp"
  suffix=2

  while ! mkdir "$run_dir" 2>/dev/null; do
    run_dir="$parent/$stamp-$suffix"
    suffix=$((suffix + 1))
  done

  printf '%s\n' "$run_dir"
}
