`timescale 1ns/1ps
module usb_recovery_test;
    reg clk = 0;
    always #5 clk = ~clk;
    reg resetn = 0;
    tri dm, dp;
    wire connected, auto_start, auto_wdt;
    wire [11:0] buttons;
    usb_hid_host dut (
        .usbclk(clk), .usbrst_n(resetn), .usb_dm(dm), .usb_dp(dp),
        .game_snes(buttons), .dbg_connected(connected),
        .dbg_auto_start_seen(auto_start), .dbg_auto_wdt_seen(auto_wdt)
    );
    task automatic ticks(input integer count);
        repeat (count) @(negedge clk);
    endtask
    initial begin
        force dut.start_wait = 0;
        force dut.conerr = 0;
        ticks(2);
        resetn = 1;
        ticks(60002);
        if (!dut.host_reset_n || buttons != 0) $fatal(1, "initial reset failed");
        force dut.report = 1;
        ticks(1);
        force dut.report = 0;
        force dut.start_wait = 1;
        ticks(1199999);
        if (auto_start) $fatal(1, "START reset fired too soon");
        ticks(2);
        if (!auto_start || dut.host_reset_n) $fatal(1, "START recovery missing");
        ticks(60002);
        if (!dut.host_reset_n) $fatal(1, "recovery reset did not release");
        ticks(1200002);
        if (!dut.host_reset_n) $fatal(1, "recovery loop without report");
        force dut.start_wait = 0;
        force dut.report = 1;
        ticks(1);
        force dut.report = 0;
        force dut.conerr = 1;
        ticks(2);
        if (!auto_wdt || dut.host_reset_n) $fatal(1, "watchdog recovery missing");
        resetn = 0;
        ticks(2);
        if (auto_start || auto_wdt || buttons != 0) $fatal(1, "manual reset failed");
        $display("PASS USB recovery: START timeout, no reset loop, report rearm, watchdog, manual reset");
        $finish;
    end
endmodule
