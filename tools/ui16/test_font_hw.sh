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
verilator --cc --exe --build --top-module ui16_hw_top -I. --Mdir obj_dir/ui16_font_hw \
  -Wno-fatal tests/ui16_hw_top.sv tests/assertion_error_stub.sv \
  src/iosys/ui16/ui_textdisp.sv src/iosys/ui16/ui_font_transport.sv \
  src/iosys/ui16/ui16_transport.sv src/iosys/ui16/ui_frame_decoder.sv \
  src/iosys/uart_fixed.v "$project_dir/tests/ui16_font_hw_test.cpp" \
  -CFLAGS "$cflags" "${linker_args[@]}"
wire_file="../firmware-bl616/build-ui16-host/sd_font_wire.bin"
if [[ ! -f "$wire_file" ]]; then
  echo "missing BL616 boundary evidence: $wire_file" >&2
  exit 1
fi
./obj_dir/ui16_font_hw/Vui16_hw_top "$(cygpath -m "$wire_file" 2>/dev/null || printf '%s' "$wire_file")"
