#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
verilator --binary --timing -Wno-fatal --top-module ui16_reliable_link_test \
  --Mdir obj_dir/reliable_link -I. \
  tests/ui16_reliable_link_test.sv \
  src/iosys/ui16/ui_reliable_link.sv src/iosys/ui16/ui16_transport.sv \
  src/iosys/ui16/ui_frame_decoder.sv src/iosys/ui16/ui_font_transport.sv \
  > obj_dir/reliable_link_build.log
obj_dir/reliable_link/Vui16_reliable_link_test
