#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p obj_dir
compiler_args=()
if command -v cygpath >/dev/null 2>&1; then
  compiler_dir="$(cygpath -m /ucrt64/bin)"
  compiler_args=(-CFLAGS "-B${compiler_dir}/ -std=c++17" -LDFLAGS "-B${compiler_dir}/ -mconsole")
  export MSYS2_ARG_CONV_EXCL='*'
fi
verilator --binary --timing -Wno-fatal --top-module ui16_reliable_link_test \
  "${compiler_args[@]}" \
  --Mdir obj_dir/reliable_link -I. \
  tests/ui16_reliable_link_test.sv \
  src/iosys/ui16/ui_reliable_link.sv src/iosys/ui16/ui16_transport.sv \
  src/iosys/ui16/ui_frame_decoder.sv src/iosys/ui16/ui_font_transport.sv \
  > obj_dir/reliable_link_build.log
obj_dir/reliable_link/Vui16_reliable_link_test
