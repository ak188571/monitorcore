module ui16_monitor_top (
    input logic clk,hclk,resetn,rx,
    input logic [7:0] x,y,
    output wire [14:0] color,
    output wire tx,overlay
);
    iosys_bl616 #(.FREQ(50_000_000),.CORE_ID(0)) sys (
        .clk(clk),.hclk(hclk),.resetn(resetn),.uart_rx(rx),.uart_tx(tx),
        .overlay(overlay),.overlay_x(x),.overlay_y(y),.overlay_color(color),
        .joy1(12'd0),.joy2(12'd0),.hid1(),.hid2(),.rom_loading(),.rom_do(),.rom_do_valid(),
        .mgmt_address(),.mgmt_read(),.mgmt_readdata(16'd0),.mgmt_write(),.mgmt_writedata(),
        .fdd_request(2'd0),.kbd_data(8'd0),.kbd_data_valid(),.core_config()
    );
endmodule
