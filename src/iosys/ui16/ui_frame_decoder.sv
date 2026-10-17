`include "src/iosys/ui16/ui_config.svh"

// Byte-level TangCore frame decoder. UART bit timing/idle timeout are external.
// A valid row is staged before any write. Allow COLS+2 clocks after its last byte.
module ui_frame_decoder (
    input logic clk,
    input logic reset,
    input logic [7:0] rx_data,
    input logic rx_valid,
    input logic rx_abort,
    output logic busy,
    output logic receiving,
    output logic error,
    output logic we,
    output logic [7:0] x,
    output logic [7:0] y,
    output logic [11:0] glyph,
    output logic selected,
    output logic half
);
    localparam int COLS = `UI_TEXT_UNITS_PER_ROW;
    localparam int ROWS = `UI_MENU_ROWS;
    localparam logic [2:0] IDLE=0, LEN_HI=1, LEN_LO=2, COMMAND=3, BODY=4, COMMIT=5;
    logic [2:0] state = IDLE;
    logic [15:0] length;
    logic [15:0] pos;
    logic [7:0] command, row, start_x, count, pending_glyph;
    logic good;
    logic [11:0] stage_glyph [0:COLS-1];
    logic [1:0] stage_attr [0:COLS-1];
    integer index;
    assign busy = state == COMMIT;
    assign receiving = state != IDLE && state != COMMIT;

    always_ff @(posedge clk) begin
        we <= 0;
        error <= 0;
        if (reset) begin
            state <= IDLE;
            x <= 0; y <= 0; glyph <= 0; selected <= 0; half <= 0;
            length <= 0; pos <= 0; good <= 0; index <= 0;
        end else if (state == COMMIT) begin
            if (rx_valid) error <= 1; // Too-fast producer; real UART spacing is much longer.
            we <= 1;
            x <= 8'(int'(start_x) + index);
            y <= row;
            glyph <= stage_glyph[index];
            selected <= stage_attr[index][`UI_ATTR_SELECTED_BIT];
            half <= stage_attr[index][`UI_ATTR_HALF_BIT];
            if (index + 1 == int'(count)) state <= IDLE;
            else index <= index + 1;
        end else if (rx_abort) begin
            if (state != IDLE) error <= 1;
            state <= IDLE;
        end else if (rx_valid) begin
            case (state)
            IDLE: if (rx_data == 8'hAA) state <= LEN_HI;
            LEN_HI: begin length[15:8] <= rx_data; state <= LEN_LO; end
            LEN_LO: begin
                length[7:0] <= rx_data;
                if ({length[15:8], rx_data} == 0 ||
                    int'({length[15:8], rx_data}) > `UI_MAX_FRAME_LENGTH) begin
                    error <= 1; state <= IDLE;
                end else state <= COMMAND;
            end
            COMMAND: begin
                command <= rx_data; pos <= 0;
                good <= rx_data == `UI_ROW_COMMAND && length >= 6;
                if (length == 1) begin
                    state <= IDLE;
                    if (rx_data == `UI_ROW_COMMAND) error <= 1;
                end else state <= BODY;
            end
            BODY: begin
                pos <= pos + 1;
                if (command == `UI_ROW_COMMAND) begin
                    case (pos)
                    0: begin row <= rx_data; if (int'(rx_data) >= ROWS) good <= 0; end
                    1: begin start_x <= rx_data; if (int'(rx_data) >= COLS) good <= 0; end
                    2: begin
                        count <= rx_data;
                        if (rx_data == 0 || int'(rx_data) > COLS ||
                            int'(start_x) + int'(rx_data) > COLS ||
                            int'(length) != 4 + 2 * int'(rx_data)) good <= 0;
                    end
                    default: begin
                        if (!pos[0]) begin
                            if (((int'(pos) - 3) >> 1) < COLS) begin
                                stage_glyph[(int'(pos) - 3) >> 1] <= {rx_data[5:2], pending_glyph};
                                stage_attr[(int'(pos) - 3) >> 1] <= rx_data[1:0];
                            end
                            if ((rx_data[7:6] != 0 || int'({rx_data[5:2], pending_glyph}) >= `UI_GLYPH_COUNT)) good <= 0;
                        end else pending_glyph <= rx_data;
                    end
                    endcase
                end
                if (pos == length - 2) begin
                    state <= IDLE;
                    if (command == `UI_ROW_COMMAND) begin
                        if (good && pos >= 4 && !pos[0] &&
                            rx_data[7:6] == 0 && int'({rx_data[5:2], pending_glyph}) < `UI_GLYPH_COUNT) begin
                            index <= 0; state <= COMMIT;
                        end else error <= 1;
                    end
                end
            end
            default: state <= IDLE;
            endcase
        end
    end
endmodule
