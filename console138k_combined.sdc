# Explicit board clocks; USB PLL outputs are verified as 12 MHz and 96 MHz.
create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name hclk5 -period 2.693602694 -waveform {0 1.346801347} [get_nets {hclk5}]
create_generated_clock -name hclk -source [get_nets {hclk5}] -master_clock hclk5 -divide_by 5 [get_nets {hclk}]
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

# Independent 12 MHz USB PLL. Only the implemented mailbox crossings below are excepted.
create_clock -name clk12 -period 83.333333333 -waveform {0 41.6666666665} [get_nets {clk12}]
# USB clock is derived from the 50 MHz PLL by Gowin auto-clock inference.
# Acknowledged mailbox: src_hold is held through destination capture and returned acknowledgement.
set_false_path -to [get_regs {
    joy_usb1_cdc/toggle_sync_0_s0
    joy_usb1_cdc/ack_sync_0_s0
    joy_usb1_cdc/dst_data_0_s0
    joy_usb1_cdc/dst_data_1_s0
    joy_usb1_cdc/dst_data_2_s0
    joy_usb1_cdc/dst_data_3_s0
    joy_usb1_cdc/dst_data_4_s0
    joy_usb1_cdc/dst_data_5_s0
    joy_usb1_cdc/dst_data_6_s0
    joy_usb1_cdc/dst_data_7_s0
    joy_usb1_cdc/dst_data_8_s0
    joy_usb1_cdc/dst_data_9_s0
    joy_usb1_cdc/dst_data_10_s0
    joy_usb1_cdc/dst_data_11_s0
    joy_usb2_cdc/toggle_sync_0_s0
    joy_usb2_cdc/ack_sync_0_s0
    joy_usb2_cdc/dst_data_0_s0
    joy_usb2_cdc/dst_data_1_s0
    joy_usb2_cdc/dst_data_2_s0
    joy_usb2_cdc/dst_data_3_s0
    joy_usb2_cdc/dst_data_4_s0
    joy_usb2_cdc/dst_data_5_s0
    joy_usb2_cdc/dst_data_6_s0
    joy_usb2_cdc/dst_data_7_s0
    joy_usb2_cdc/dst_data_8_s0
    joy_usb2_cdc/dst_data_9_s0
    joy_usb2_cdc/dst_data_10_s0
    joy_usb2_cdc/dst_data_11_s0
}]

# FS asynchronous pin capture and acknowledged FS->12 MHz mailboxes.
set_false_path -to [get_regs {
 usb_hid_host/owner_sync_0_s0
 usb_hid_host/fs/dp_meta_s0
 usb_hid_host/fs/dm_meta_s0
 usb_hid_host/fs/phy/dp_meta_s0
 usb_hid_host/fs/phy/dm_meta_s0
 usb_hid_host/fs_to_ls/toggle_sync_0_s0
 usb_hid_host/fs_to_ls/ack_sync_0_s0
 usb_hid_host/fs_to_ls/dst_data_0_s0
 usb_hid_host/fs_to_ls/dst_data_1_s0
 usb_hid_host/fs_to_ls/dst_data_2_s0
 usb_hid_host/fs_to_ls/dst_data_3_s0
 usb_hid_host/fs_to_ls/dst_data_4_s0
 usb_hid_host/fs_to_ls/dst_data_5_s0
 usb_hid_host/fs_to_ls/dst_data_6_s0
 usb_hid_host/fs_to_ls/dst_data_7_s0
 usb_hid_host/fs_to_ls/dst_data_8_s0
 usb_hid_host/fs_to_ls/dst_data_9_s0
 usb_hid_host/fs_to_ls/dst_data_10_s0
 usb_hid_host/fs_to_ls/dst_data_11_s0
 usb_hid_host/fs_to_ls/dst_data_12_s0
 usb_hid_host2/owner_sync_0_s0
 usb_hid_host2/fs/dp_meta_s0
 usb_hid_host2/fs/dm_meta_s0
 usb_hid_host2/fs/phy/dp_meta_s0
 usb_hid_host2/fs/phy/dm_meta_s0
 usb_hid_host2/fs_to_ls/toggle_sync_0_s0
 usb_hid_host2/fs_to_ls/ack_sync_0_s0
 usb_hid_host2/fs_to_ls/dst_data_0_s0
 usb_hid_host2/fs_to_ls/dst_data_1_s0
 usb_hid_host2/fs_to_ls/dst_data_2_s0
 usb_hid_host2/fs_to_ls/dst_data_3_s0
 usb_hid_host2/fs_to_ls/dst_data_4_s0
 usb_hid_host2/fs_to_ls/dst_data_5_s0
 usb_hid_host2/fs_to_ls/dst_data_6_s0
 usb_hid_host2/fs_to_ls/dst_data_7_s0
 usb_hid_host2/fs_to_ls/dst_data_8_s0
 usb_hid_host2/fs_to_ls/dst_data_9_s0
 usb_hid_host2/fs_to_ls/dst_data_10_s0
 usb_hid_host2/fs_to_ls/dst_data_11_s0
 usb_hid_host2/fs_to_ls/dst_data_12_s0
}]

set_false_path -to [get_regs {usb_hid_host/fs_to_ls/dst_data_13_s0 usb_hid_host2/fs_to_ls/dst_data_13_s0}]

# Explicit PLL output clock, following the existing clk12 output-clock policy.
create_clock -name clk96 -period 10.416666667 -waveform {0 5.2083333335} [get_nets {clk96}]

# Diagnostic-only asynchronous display samplers, first stages only.
# Read settled values after 8 seconds; debug bus transitions are not atomic.
set_false_path -to [get_regs {
 diag_meta_0_s0
 diag_meta_1_s0
 diag_meta_2_s0
 diag_meta_4_s0
 diag_meta_5_s0
 diag_meta_6_s0
 diag_meta_8_s0
 diag_meta_9_s0
 diag_meta_10_s0
 diag_meta_11_s0
 diag_meta_12_s0
 diag_meta_13_s0
 diag_meta_14_s0
 diag_meta_15_s0
 diag_meta_16_s0
 diag_meta_17_s0
 diag_meta_18_s0
 diag_meta_19_s0
 diag_meta_20_s0
 diag_meta_21_s0
 diag_meta_22_s0
 diag_meta_23_s0
 diag_meta_24_s0
 diag_meta_25_s0
 diag_meta_26_s0
 diag_meta_27_s0
 diag_meta_28_s0
 diag_meta_29_s0
 diag_meta_30_s0
 diag_meta_31_s0
 diag_s0_0_s0
}]

# Added first-stage diagnostic context samplers; second stages remain timed.
set_false_path -to [get_regs {
 diag_meta_32_s0
 diag_meta_33_s0
 diag_meta_34_s0
 diag_meta_35_s0
 diag_meta_36_s0
 diag_meta_37_s0
 diag_meta_38_s0
 diag_meta_39_s0
 diag_meta_40_s0
 diag_meta_41_s0
 diag_meta_42_s0
 diag_meta_43_s0
 diag_meta_44_s0
 diag_meta_45_s0
 diag_meta_46_s0
 diag_meta_47_s0
}]

# First-stage report-seen display synchronizers only.
set_false_path -to [get_regs {diag_report_meta_0_s0 diag_report_meta_1_s0}]

# First-stage unexpected-record display synchronizers only.
set_false_path -to [get_regs {
 diag_meta_48_s0
 diag_meta_49_s0
 diag_meta_50_s0
 diag_meta_51_s0
 diag_meta_52_s0
 diag_meta_53_s0
 diag_meta_54_s0
 diag_meta_55_s0
 diag_meta_56_s0
 diag_meta_57_s0
 diag_meta_58_s0
 diag_meta_59_s0
 diag_meta_60_s0
 diag_meta_61_s0
 diag_meta_62_s0
 diag_meta_63_s0
 diag_meta_64_s0
 diag_meta_65_s0
 diag_meta_66_s0
 diag_meta_67_s0
 diag_meta_68_s0
 diag_meta_69_s0
 diag_meta_70_s0
 diag_meta_71_s0
}]
