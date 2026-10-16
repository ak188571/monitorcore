// Display mux test only. Real projects compile the unchanged Gowin-backed textdisp.v.
module textdisp #(
    parameter [14:0] COLOR_LOGO = 0
) (
    input clk,hclk,resetn,
    input [7:0] x,y,
    output [14:0] color,
    input [3:0] reg_char_we,
    input [31:0] reg_char_di
);
    assign color=15'h1234;
endmodule
