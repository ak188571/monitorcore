#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if command -v cygpath >/dev/null 2>&1; then
  compiler_dir="$(cygpath -m /ucrt64/bin)"
  export MSYS2_ARG_CONV_EXCL='*'
  build_flags=(-CFLAGS "-B${compiler_dir}/ -std=c++17" -LDFLAGS "-B${compiler_dir}/ -mconsole")
else
  build_flags=(-CFLAGS "-std=c++17")
fi
verilator --binary --timing --top-module usb_recovery_test \
  --Mdir obj_dir/usb_recovery -Wno-fatal \
  tests/usb_recovery_test.sv src/usb_hid_host.v "${build_flags[@]}"
(cd src && ../obj_dir/usb_recovery/Vusb_recovery_test)
