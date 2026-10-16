#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p obj_dir
linker_args=()
if command -v cygpath >/dev/null 2>&1; then
  project_dir="$(cygpath -m "$PWD")"
  compiler_dir="$(cygpath -m /ucrt64/bin)"
  cflags="-B${compiler_dir}/ -std=c++17"
  linker_args=(-LDFLAGS "-B${compiler_dir}/ -mconsole")
  export MSYS2_ARG_CONV_EXCL='*'
else
  project_dir="$PWD";cflags="-std=c++17"
fi
verilator --cc --exe --build --top-module ui16_monitor_top -I. --Mdir obj_dir/ui16_monitor \
  -DUI16_ENABLE -Wno-fatal -Wno-ASSIGNIN tests/ui16_monitor_top.sv \
  tests/legacy_textdisp_stub.sv tests/assertion_error_stub.sv src/iosys/iosys_bl616.v \
  src/iosys/uart_fixed.v src/iosys/ui16/ui_textdisp.sv \
  src/iosys/ui16/ui16_transport.sv src/iosys/ui16/ui_frame_decoder.sv \
  "$project_dir/tests/ui16_monitor_test.cpp" -CFLAGS "$cflags" "${linker_args[@]}"
./obj_dir/ui16_monitor/Vui16_monitor_top
