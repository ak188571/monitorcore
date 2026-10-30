// "Monitor" core that is loaded as the default core on power-up.
// nand2mario, 2025.2

`ifndef VERILATOR
`ifndef MEGA
`ifndef CONSOLE
`ifndef PRIMER
`ifndef NANO
`error "config.v must be read before monitor_top.v"
`endif
`endif
`endif
`endif
`endif

import configPackage::*;

module monitor_top (
    input        sys_clk,
    input        s0,

    // UART
    input        UART_RXD,
    output       UART_TXD,

    // HDMI TX
    output       tmds_clk_p,    
    output       tmds_clk_n,
    output [2:0] tmds_d_p,
    output [2:0] tmds_d_n,

    // USB1 and USB2
`ifdef USB1
    inout usb1_dp,
    inout usb1_dn,
`endif
`ifdef USB2
    inout usb2_dp,
    inout usb2_dn,
`endif

`ifdef CONTROLLER_SNES
    // snes controllers
    output       joy1_strb,
    output       joy1_clk,
    input        joy1_data,
    output       joy2_strb,
    output       joy2_clk,
    input        joy2_data,
`endif

`ifdef CONTROLLER_DS2
    // dualshock controllers
    output       ds_clk,
    input        ds_miso,
    output       ds_mosi,
    output       ds_cs,
    output       ds_clk2,
    input        ds_miso2,
    output       ds_mosi2,
    output       ds_cs2,
`endif

    // LED
    output [7:0] led
);

// Clock signals
wire clk;                       // main clock 50Mhz
wire clk27;                     // 27Mhz for HDMI
wire hclk5, hclk;               // 720p pixel clock at 74.25Mhz, and 5x high-speed

reg resetn = 0;              // reset is cleared after 4 cycles

// HDMI clocks
`ifdef NANO
// GW2A Nano20K
assign clk27 = sys_clk;       
assign clk = sys_clk;
localparam FREQ = 27_000_000;
gowin_pll_hdmi pll_hdmi (.clkin(clk27), .clkout(hclk5));
CLKDIV #(.DIV_MODE(5)) div5 (
    .CLKOUT(hclk),
    .HCLKIN(hclk5),
    .RESETN(1'b1),
    .CALIB(1'b0)
);

`else
// GW5 devices
assign clk = sys_clk;
localparam FREQ = 50_000_000;
pll_27 pll_27 (
    .clkin(sys_clk),
    .clkout0(clk27)
);
pll_74 pll_74 (
    .clkin(clk27),              // 27 Mhz input
    .clkout0(hclk), .clkout1(hclk5)
);
`endif

reg [15:0] resetcnt = 16'hffff;
always @(posedge clk) begin
    resetcnt <= resetcnt == 0 ? 0 : resetcnt - 1;
     if (resetcnt == 0)
//  if (resetcnt == 0 && s0)    // primer25k, nano20k
//  if (resetcnt == 0 && ~s0)   // mega138k
        resetn <= 1'b1;
end

wire overlay;
wor [11:0] joy1_btns, joy2_btns;

// Controller input
`ifdef CONTROLLER_SNES
controller_snes #(.FREQ(FREQ)) joy1_snes (
    .clk(clk), .resetn(resetn), .buttons(joy1_btns),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
);
controller_snes #(.FREQ(FREQ)) joy2_snes (
    .clk(clk), .resetn(resetn), .buttons(joy2_btns),
    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
);
`endif

`ifdef CONTROLLER_DS2
controller_ds2 #(.FREQ(FREQ)) joy1_ds2 (
    .clk(clk), .snes_buttons(joy1_btns),
    .ds_clk(ds_clk), .ds_miso(ds_miso), .ds_mosi(ds_mosi), .ds_cs(ds_cs) 
);
controller_ds2 #(.FREQ(FREQ)) joy2_ds2 (
   .clk(clk), .snes_buttons(joy2_btns),
   .ds_clk(ds_clk2), .ds_miso(ds_miso2), .ds_mosi(ds_mosi2), .ds_cs(ds_cs2) 
);
`endif

wire [11:0] joy_usb1_raw, joy_usb2_raw;
wire [11:0] joy_usb1, joy_usb2;
wire [3:0] fs_state1,fs_state2;
wire [7:0] fs_error1,fs_error2;
wire fs_owner1,fs_owner2;
wire [7:0] fs_context1,fs_context2;
wire [23:0] fs_first_unexpected2;

`ifdef USB1

wire clk12,clk96;
wire usb_reset96n;
usb_reset_sync usb_reset96_release (.clk(clk96), .async_resetn(pll_lock_12 && s0), .resetn(usb_reset96n));
wire pll_lock_12;
wire usb_resetn;
usb_reset_sync usb_reset_release (.clk(clk12), .async_resetn(pll_lock_12 && s0), .resetn(usb_resetn));
wire usb_conerr;
wire [1:0] usb_type;
wire usb_report;
wire p1_connected;
wire p1_auto_start_seen, p1_auto_wdt_seen;

pll_usb pll12(
    .clkin(sys_clk),
    .clk12(clk12), .clk96(clk96),
    .lock(pll_lock_12)
);

usb_dual_speed_host usb_hid_host (
    .usbclk96(clk96), .usbrst96_n(usb_reset96n), .usbclk(clk12),
    .usbrst_n(usb_resetn),
    .usb_dm(usb1_dn),
    .usb_dp(usb1_dp),
    .game_snes(joy_usb1_raw),
    .typ(usb_type),
    .conerr(usb_conerr),
    .report(usb_report),
    .dbg_connected(p1_connected),
    .dbg_auto_start_seen(p1_auto_start_seen),
    .dbg_auto_wdt_seen(p1_auto_wdt_seen),
    .dbg_fs_owner(fs_owner1),.dbg_fs_state(fs_state1),.dbg_fs_error(fs_error1),.dbg_fs_context(fs_context1)
);

// Delay snapshots until the decoded bus is stable, including cleared buttons
// after host disconnect or manual reset.
reg usb_report1_delayed = 0, p1_connected_prev = 0, p1_s0_prev = 1;
always @(posedge clk12) begin
    if (!pll_lock_12) begin
        usb_report1_delayed <= 0;
        p1_connected_prev <= 0;
        p1_s0_prev <= 1;
    end else begin
        usb_report1_delayed <= usb_report ||
            (p1_connected_prev && !p1_connected) || (p1_s0_prev && !s0);
        p1_connected_prev <= p1_connected;
        p1_s0_prev <= s0;
    end
end
wire unused_joy_usb1_valid;
usb_game_cdc #(.WIDTH(12)) joy_usb1_cdc (
    .src_clk(clk12), .src_resetn(pll_lock_12),
    .src_valid(usb_report1_delayed), .src_data(joy_usb1_raw),
    .dst_clk(clk), .dst_resetn(resetn),
    .dst_data(joy_usb1), .dst_valid(unused_joy_usb1_valid)
);
`else
assign joy_usb1_raw = 12'b0;
assign joy_usb1 = 12'b0;
`endif

`ifdef USB2
wire p2_report;
wire p2_connected;
wire p2_auto_start_seen, p2_auto_wdt_seen;
usb_dual_speed_host usb_hid_host2 (
    .usbclk96(clk96), .usbrst96_n(usb_reset96n), .usbclk(clk12), .usbrst_n(usb_resetn),
    .usb_dm(usb2_dn), .usb_dp(usb2_dp),
    .game_snes(joy_usb2_raw), .report(p2_report),
    .dbg_connected(p2_connected),
    .dbg_auto_start_seen(p2_auto_start_seen),
    .dbg_auto_wdt_seen(p2_auto_wdt_seen),
    .dbg_fs_owner(fs_owner2),.dbg_fs_state(fs_state2),.dbg_fs_error(fs_error2),.dbg_fs_context(fs_context2),.dbg_fs_first_unexpected(fs_first_unexpected2)
);
// Delay snapshots until the decoded bus is stable, including cleared buttons
// after host disconnect or manual reset.
reg usb_report2_delayed = 0, p2_connected_prev = 0, p2_s0_prev = 1;
always @(posedge clk12) begin
    if (!pll_lock_12) begin
        usb_report2_delayed <= 0;
        p2_connected_prev <= 0;
        p2_s0_prev <= 1;
    end else begin
        usb_report2_delayed <= p2_report ||
            (p2_connected_prev && !p2_connected) || (p2_s0_prev && !s0);
        p2_connected_prev <= p2_connected;
        p2_s0_prev <= s0;
    end
end
wire unused_joy_usb2_valid;
usb_game_cdc #(.WIDTH(12)) joy_usb2_cdc (
    .src_clk(clk12), .src_resetn(pll_lock_12),
    .src_valid(usb_report2_delayed), .src_data(joy_usb2_raw),
    .dst_clk(clk), .dst_resetn(resetn),
    .dst_data(joy_usb2), .dst_valid(unused_joy_usb2_valid)
);
`else
assign joy_usb2_raw = 12'b0;
assign joy_usb2 = 12'b0;
`endif

// P1/P2 share the PMOD LED pattern used by the successful Host test.
reg [11:0] p1_buttons_prev = 0, p2_buttons_prev = 0;
reg [22:0] p1_button_hold = 0, p1_report_hold = 0;
reg [22:0] p2_button_hold = 0, p2_report_hold = 0;
localparam integer LED_HOLD_CYCLES = 6000000; // 0.5 s at 12 MHz
always @(posedge clk12) begin
    if (!pll_lock_12 || !s0) begin
        p1_buttons_prev <= 0;
        p2_buttons_prev <= 0;
        p1_button_hold <= 0;
        p1_report_hold <= 0;
        p2_button_hold <= 0;
        p2_report_hold <= 0;
    end else begin
        p1_buttons_prev <= joy_usb1_raw;
        p2_buttons_prev <= joy_usb2_raw;
        if (|(joy_usb1_raw & ~p1_buttons_prev)) p1_button_hold <= LED_HOLD_CYCLES;
        else if (p1_button_hold != 0) p1_button_hold <= p1_button_hold - 1'b1;
        if (usb_report) p1_report_hold <= LED_HOLD_CYCLES;
        else if (p1_report_hold != 0) p1_report_hold <= p1_report_hold - 1'b1;
        if (|(joy_usb2_raw & ~p2_buttons_prev)) p2_button_hold <= LED_HOLD_CYCLES;
        else if (p2_button_hold != 0) p2_button_hold <= p2_button_hold - 1'b1;
        if (p2_report) p2_report_hold <= LED_HOLD_CYCLES;
        else if (p2_report_hold != 0) p2_report_hold <= p2_report_hold - 1'b1;
    end
end
wire [7:0] led_lit = {(p2_auto_start_seen || p2_auto_wdt_seen),
                      (p2_report_hold != 0), p2_connected, (p2_button_hold != 0),
                      (p1_auto_start_seen || p1_auto_wdt_seen),
                      (p1_report_hold != 0), p1_connected, (p1_button_hold != 0)};
// Diagnostic monitor only: ten pages. Hold S1 for >=5 seconds to
// explicitly select page 0; shorter qualified presses advance one page.
reg [3:0] diag_page=0;
reg [2:0] diag_s0=3'b111;
reg diag_stable_s0=1;
reg [19:0] diag_debounce=0;
reg [27:0] diag_press_count=0;
reg [71:0] diag_meta=0,diag_sync=0;
reg [1:0] diag_report_seen=0,diag_report_meta=0,diag_report_sync=0;
always @(posedge clk12)begin
 if(!pll_lock_12 || !s0)diag_report_seen<=0;
 else begin
  if(usb_report)diag_report_seen[0]<=1;
  if(p2_report)diag_report_seen[1]<=1;
 end
end
wire [7:0] diag_raw={p2_connected,fs_owner2,usb2_dn,usb2_dp,
                    p1_connected,fs_owner1,usb1_dn,usb1_dp};
always @(posedge clk)begin
 if(!resetn)begin
  diag_page<=0;diag_s0<=3'b111;diag_stable_s0<=1;diag_debounce<=0;
  diag_press_count<=0;diag_meta<=0;diag_sync<=0;diag_report_meta<=0;diag_report_sync<=0;
 end else begin
  diag_s0<={diag_s0[1:0],s0};
  if(!diag_stable_s0)begin
   if(diag_press_count<FREQ*5)diag_press_count<=diag_press_count+1'b1;
  end else diag_press_count<=0;
  if(diag_s0[2]==diag_stable_s0)diag_debounce<=0;
  else if(diag_debounce==FREQ/50-1)begin
   diag_stable_s0<=diag_s0[2];diag_debounce<=0;
   if(diag_s0[2])begin
    if(diag_press_count>=FREQ*5 || diag_page==9)diag_page<=0;
    else diag_page<=diag_page+1'b1;
   end
  end else diag_debounce<=diag_debounce+1'b1;
  // Debug display only: multi-bit transitions are not atomic. Read settled data.
  diag_meta<={fs_first_unexpected2,fs_context2,fs_context1,diag_raw,fs_error2,fs_error1,fs_state2,fs_state1};
  diag_sync<=diag_meta;diag_report_meta<=diag_report_seen;diag_report_sync<=diag_report_meta;
 end
end
wire [7:0] diag_byte=diag_page==0 ? diag_sync[7:0] :
                    diag_page==1 ? diag_sync[15:8] :
                    diag_page==2 ? diag_sync[23:16] :
                    diag_page==3 ? diag_sync[31:24] :
                    diag_page==4 ? diag_sync[39:32] :
                    diag_page==5 ? diag_sync[47:40] :
                    diag_page==6 ? {6'b101100,diag_report_sync} :
                    diag_page==7 ? diag_sync[71:64] :
                    diag_page==8 ? diag_sync[63:56] : diag_sync[55:48];
assign led=s0 ? ~diag_byte : 8'h00; // Keep all LEDs on while S1 is held

wire [14:0] overlay_color;
wire [7:0] overlay_x;
wire [7:0] overlay_y;

monitor2hdmi s2h(
    .clk(clk), .resetn(1'b1), 
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y),
    .overlay_color(overlay_color), 
    .clk_pixel(hclk),.clk_5x_pixel(hclk5),
    .tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p),
    .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p)
);

// IOSys for menu, rom loading...
iosys_bl616 #(.CORE_ID(0), .FREQ(FREQ), .COLOR_LOGO(15'b11011_10010_00011)) sys (        // CORE ID 0: Monitor
    .clk(clk), .hclk(hclk), .resetn(resetn),
    // overlay generated by textdisp
    .overlay(overlay), .overlay_x(overlay_x), .overlay_y(overlay_y), .overlay_color(overlay_color),
    // joystick buttons to be sent to companion MCU
    .joy1(joy1_btns | joy_usb1), .joy2(joy2_btns | joy_usb2),
    // UART connection to the companion MCU
    .uart_rx(UART_RXD), .uart_tx(UART_TXD)
);


endmodule
