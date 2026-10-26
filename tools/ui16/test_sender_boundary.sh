#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
bash ../firmware-bl616/tools/ui16/test_reliable_link.sh
verilator --binary --timing -Wno-fatal --top-module ui16_sender_boundary_test \
  --Mdir obj_dir/sender_boundary -I. tests/ui16_sender_boundary_test.sv \
  src/iosys/ui16/ui_reliable_link.sv src/iosys/ui16/ui16_transport.sv \
  src/iosys/ui16/ui_frame_decoder.sv src/iosys/ui16/ui_font_transport.sv \
  > obj_dir/sender_boundary_build.log
obj_dir/sender_boundary/Vui16_sender_boundary_test
