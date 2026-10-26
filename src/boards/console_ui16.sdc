# UI16 has three single-bit status signals crossing from the 50 MHz system
# clock to the 74.25 MHz pixel clock. Only the first synchronizer stage is an
# asynchronous endpoint; all subsequent stages remain fully timed by hclk.
set_false_path -to [get_regs {
    sys/ui16_reset_sync_0_s0
    sys/ui16_mode_sync_0_s0
    sys/ui16_font_enabled_sync_0_s0
    sys/ui16_disp/reset_pipe_0_s0
    sys/ui16_disp/font_gate_sync_0_s0
}]

# USB controller state is transferred by a toggle handshake. The toggle's
# first synchronizer stage is asynchronous. The held 12-bit snapshot is stable
# for multiple destination clocks before dst_data captures it, so only that
# handshake-controlled capture path is excepted.
set_false_path -to [get_regs {
    joy_usb1_cdc/toggle_sync_0_s0
    joy_usb2_cdc/toggle_sync_0_s0
    joy_usb1_cdc/dst_data_0_s0 joy_usb1_cdc/dst_data_1_s0
    joy_usb1_cdc/dst_data_2_s0 joy_usb1_cdc/dst_data_3_s0
    joy_usb1_cdc/dst_data_4_s0 joy_usb1_cdc/dst_data_5_s0
    joy_usb1_cdc/dst_data_6_s0 joy_usb1_cdc/dst_data_7_s0
    joy_usb1_cdc/dst_data_8_s0 joy_usb1_cdc/dst_data_9_s0
    joy_usb1_cdc/dst_data_10_s0 joy_usb1_cdc/dst_data_11_s0
    joy_usb2_cdc/dst_data_0_s0 joy_usb2_cdc/dst_data_1_s0
    joy_usb2_cdc/dst_data_2_s0 joy_usb2_cdc/dst_data_3_s0
    joy_usb2_cdc/dst_data_4_s0 joy_usb2_cdc/dst_data_5_s0
    joy_usb2_cdc/dst_data_6_s0 joy_usb2_cdc/dst_data_7_s0
    joy_usb2_cdc/dst_data_8_s0 joy_usb2_cdc/dst_data_9_s0
    joy_usb2_cdc/dst_data_10_s0 joy_usb2_cdc/dst_data_11_s0
}]
