#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p obj_dir
if command -v cygpath >/dev/null 2>&1; then
  project_dir="$(cygpath -m "$PWD")"
  compiler_dir="$(cygpath -m /ucrt64/bin)"
  cflags="-B${compiler_dir}/ -std=c++17"
  ldflags="-B${compiler_dir}/ -mconsole"
  export MSYS2_ARG_CONV_EXCL='*'
else
  project_dir="$PWD";cflags="-std=c++17";ldflags=""
fi
linker_args=()
if [[ -n "$ldflags" ]]; then linker_args=(-LDFLAGS "$ldflags"); fi
verilator --cc --exe --build --top-module cdc_snapshot_top -I. \
  --Mdir obj_dir/cdc_snapshot -Wno-fatal \
  tests/cdc_snapshot_top.sv src/cdc_snapshot.sv \
  "$project_dir/tests/cdc_snapshot_test.cpp" \
  -CFLAGS "$cflags" "${linker_args[@]}"
./obj_dir/cdc_snapshot/Vcdc_snapshot_top
