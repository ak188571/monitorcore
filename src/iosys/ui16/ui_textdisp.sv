`include "src/iosys/ui16/ui_config.svh"

// clk: cell writes; hclk: synchronous RAM -> font ROM -> BGR555 output.
// No reset of memory arrays: preserve block-RAM inference and initialized contents.
module ui_textdisp #(
    parameter bit SELFTEST = 0
) (
    input logic clk,
    input logic hclk,
    input logic resetn,
    input logic we,
    input logic [7:0] wr_x, wr_y,
    input logic [11:0] wr_glyph,
    input logic wr_selected, wr_half, wr_vertical_half,
    input logic font_we,
    input logic [`UI_FONT_ADDR_BITS-1:0] font_wr_addr,
    input logic [15:0] font_wr_data,
    input logic font_display_enabled,
    input logic [7:0] x, y,
    output logic [14:0] color,
    output logic color_valid
);
    logic [14:0] cells [0:(1 << `UI_CELL_ADDR_BITS)-1];
    logic [15:0] font_rom [0:`UI_FONT_ROM_SIZE-1];
    initial begin
        if (SELFTEST)
            $readmemh("src/iosys/ui16/cells_selftest.hex", cells);
        else
            $readmemh("src/iosys/ui16/cells_zero.hex", cells);
        $readmemh("src/iosys/ui16/font16_full.hex", font_rom);
    end
    wire [`UI_CELL_ADDR_BITS-1:0] wr_addr =
        `UI_CELL_ADDR_BITS'(int'(wr_y)*`UI_TEXT_UNITS_PER_ROW + int'(wr_x));
    always_ff @(posedge clk) begin
        if (resetn && font_we) font_rom[font_wr_addr] <= font_wr_data;
        if (resetn && we && int'(wr_x)<`UI_TEXT_UNITS_PER_ROW && int'(wr_y)<`UI_MENU_ROWS)
            cells[wr_addr] <= {wr_vertical_half, wr_half, wr_selected, wr_glyph};
    end

    // Synchronize reset release to the read clock.
    logic [1:0] reset_pipe = 0 /* synthesis syn_preserve=1 */;
    logic [1:0] font_gate_sync = 0 /* synthesis syn_preserve=1 */;
    always_ff @(posedge hclk) begin
        reset_pipe <= {reset_pipe[0],resetn};
        if (!reset_pipe[1]) font_gate_sync <= 0;
        else font_gate_sync <= {font_gate_sync[0],font_display_enabled};
    end
    logic [14:0] cell_q;
    logic [2:0] xoff1;
    logic [2:0] yoff1;
    logic [3:0] glyph_x2;
    logic selected2, valid1, valid2;
    logic [15:0] font_q;
    wire [`UI_CELL_ADDR_BITS-1:0] read_addr =
        `UI_CELL_ADDR_BITS'((int'(y)/`UI_VERTICAL_UNIT_HEIGHT)*`UI_TEXT_UNITS_PER_ROW +
                            int'(x)/`UI_TEXT_UNIT_WIDTH);
    // Two synchronous memory reads. Registers next to each read carry its metadata.
    always_ff @(posedge hclk) begin
        cell_q <= cells[read_addr];
        xoff1 <= x[2:0]; yoff1 <= y[2:0];
        valid1 <= reset_pipe[1] && int'(y)<`UI_SCREEN_HEIGHT;

        font_q <= font_rom[`UI_FONT_ADDR_BITS'({cell_q[11:0],cell_q[14],yoff1})];
        glyph_x2 <= {cell_q[13],xoff1};
        selected2 <= cell_q[12]; valid2 <= valid1;

        color_valid <= valid2 && reset_pipe[1];
        color <= 0;
        if (valid2 && reset_pipe[1] && font_gate_sync[1] && font_q[15-int'(glyph_x2)]) begin
            // PC constants are RGB555. TangCore overlay is BGR555.
            if (selected2)
                color <= {5'(`UI_COLOR_SELECTED),5'(`UI_COLOR_SELECTED >> 5),5'(`UI_COLOR_SELECTED >> 10)};
            else
                color <= {5'(`UI_COLOR_NORMAL),5'(`UI_COLOR_NORMAL >> 5),5'(`UI_COLOR_NORMAL >> 10)};
        end
    end
endmodule
