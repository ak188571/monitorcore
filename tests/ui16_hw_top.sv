`include "src/iosys/ui16/ui_config.svh"
module ui16_hw_top (
    input logic clk, hclk, resetn,
    input logic serial_rx,
    input logic byte_valid,
    input logic [7:0] byte_data,
    input logic use_serial,
    input logic [7:0] x,y,
    output logic [14:0] color, selftest_color,
    output logic color_valid,
    output logic abort_frame,error,busy,
    output logic font_error_o, font_visible,
    output logic [7:0] serial_data,
    output logic serial_valid
    ,output logic [31:0] writes
    ,output logic [11:0] last_glyph
);
    wire unused_idle, unused_eop;
    async_receiver #(.ClkFrequency(50_000_000),.Baud(2_000_000)) rx (
        .clk(clk),.RxD(serial_rx),.RxD_data(serial_data),.RxD_data_ready(serial_valid),
        .RxD_idle(unused_idle),.RxD_endofpacket(unused_eop)
    );
    wire we,verified_we,full_row_we,selected,half,vertical_half;
    wire [7:0] wx,wy;
    wire [11:0] glyph;
    wire unused_selftest_valid;
    always_ff @(posedge clk) begin
        if (!resetn) begin writes <= 0; last_glyph <= 0; end
        else if (we) begin writes <= writes + 1; last_glyph <= glyph; end
    end
    ui16_transport #(.FREQ(50_000_000),.TIMEOUT_MS(10)) transport (
        .clk(clk),.resetn(resetn),.rx_data(use_serial?serial_data:byte_data),
        .rx_valid(use_serial?serial_valid:byte_valid),.abort_frame(abort_frame),
        .error(error),.busy(busy),.we(we),.verified_we(verified_we),.full_row_we(full_row_we),.x(wx),.y(wy),.glyph(glyph),.selected(selected),.half(half),.vertical_half(vertical_half)
    );
    wire font_we, font_enabled, font_error;
    assign font_error_o = font_error;
    assign font_visible = font_enabled;
    wire [`UI_FONT_ADDR_BITS-1:0] font_addr;
    wire [15:0] font_data;
    ui_font_transport #(.FREQ(50_000_000),.TIMEOUT_MS(10)) font_rx (
        .clk(clk),.resetn(resetn),.rx_data(use_serial?serial_data:byte_data),
        .rx_valid(use_serial?serial_valid:byte_valid),.live_update(1'b0),.row_error(error),
        .row_we(full_row_we),.row_x(wx),.row_y(wy),.font_we(font_we),
        .font_addr(font_addr),.font_data(font_data),.display_enabled(font_enabled),
        .error(font_error)
    );
    wire cell_we = we && (!verified_we || !font_enabled);
    ui_textdisp #(.SELFTEST(0)) disp (
        .clk(clk),.hclk(hclk),.resetn(resetn),.we(cell_we),.wr_x(wx),.wr_y(wy),.wr_glyph(glyph),
        .wr_selected(selected),.wr_half(half),.wr_vertical_half(vertical_half),
        .font_we(font_we),.font_wr_addr(font_addr),.font_wr_data(font_data),
        .font_display_enabled(font_enabled),.x(x),.y(y),.color(color),.color_valid(color_valid)
    );
    ui_textdisp #(.SELFTEST(1)) selftest (
        .clk(clk),.hclk(hclk),.resetn(resetn),.we(cell_we),.wr_x(wx),.wr_y(wy),.wr_glyph(glyph),
        .wr_selected(selected),.wr_half(half),.wr_vertical_half(vertical_half),
        .font_we(font_we),.font_wr_addr(font_addr),.font_wr_data(font_data),
        .font_display_enabled(font_enabled),.x(x),.y(y),.color(selftest_color),.color_valid(unused_selftest_valid)
    );
endmodule
