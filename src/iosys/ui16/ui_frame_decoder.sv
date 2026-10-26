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
    output logic verified_we, // any CRC8-verified row command 0x14
    output logic full_row_we, // only CRC8-verified 32-cell row at x=0
    output logic [7:0] x,
    output logic [7:0] y,
    output logic [11:0] glyph,
    output logic selected,
    output logic half,
    output logic vertical_half
);
    localparam int COLS = `UI_TEXT_UNITS_PER_ROW;
    localparam int ROWS = `UI_MENU_ROWS;
    localparam logic [2:0] IDLE=0, LEN_HI=1, LEN_LO=2, COMMAND=3, BODY=4, COMMIT=5;
    logic [2:0] state = IDLE;
    logic [15:0] length;
    logic [15:0] pos;
    logic [7:0] command, row, start_x, count, pending_glyph;
    logic good;
    logic [7:0] crc;
    localparam logic [7:0] ROW_CRC_COMMAND = 8'h14;
    function automatic [7:0] crc_next(input [7:0] current,input [7:0] b);
        reg [7:0] c;
        begin
            c=current^b;
            for (integer j=0;j<8;j=j+1)
                c=c[7] ? ((c<<1)^8'h07) : (c<<1);
            crc_next=c;
        end
    endfunction
    logic [11:0] stage_glyph [0:COLS-1];
    logic [1:0] stage_attr [0:COLS-1];
    logic stage_vertical_half [0:COLS-1];
    integer index;
    assign busy = state == COMMIT;
    assign receiving = state != IDLE && state != COMMIT;
    assign verified_we = we && (command == ROW_CRC_COMMAND);
    // A protected menu refresh must cover an entire row; partial updates cannot
    // satisfy the font receiver's 28-row safety barrier.
    assign full_row_we = verified_we && start_x == 0 && count == 8'(COLS);

    always_ff @(posedge clk) begin
        we <= 0;
        error <= 0;
        if (reset) begin
            state <= IDLE;
            x <= 0; y <= 0; glyph <= 0; selected <= 0; half <= 0; vertical_half <= 0;
            length <= 0; pos <= 0; good <= 0; index <= 0; crc <= 0;
        end else if (state == COMMIT) begin
            if (rx_valid) error <= 1; // Too-fast producer; real UART spacing is much longer.
            we <= 1;
            x <= 8'(int'(start_x) + index);
            y <= row;
            glyph <= stage_glyph[index];
            selected <= stage_attr[index][`UI_ATTR_SELECTED_BIT];
            half <= stage_attr[index][`UI_ATTR_HALF_BIT];
            vertical_half <= stage_vertical_half[index];
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
                good <= ((rx_data == `UI_ROW_COMMAND && length >= 6) ||
                         (rx_data == ROW_CRC_COMMAND && length >= 7));
                crc <= 0;
                if (length == 1) begin
                    state <= IDLE;
                    if (rx_data == `UI_ROW_COMMAND || rx_data == ROW_CRC_COMMAND) error <= 1;
                end else state <= BODY;
            end
            BODY: begin
                pos <= pos + 16'd1;
                if (command == `UI_ROW_COMMAND || command == ROW_CRC_COMMAND) begin
                    // New row format: all header and cell bytes are CRC8-protected;
                    // the last byte is the CRC itself and is never written.
                    if (command == ROW_CRC_COMMAND && pos < length-2)
                        crc <= crc_next(crc,rx_data);
                    if (!(command == ROW_CRC_COMMAND && pos == length-2)) begin
                    case (pos)
                    0: begin row <= rx_data; if (int'(rx_data) >= ROWS) good <= 0; end
                    1: begin start_x <= rx_data; if (int'(rx_data) >= COLS) good <= 0; end
                    2: begin
                        count <= rx_data;
                        if (rx_data == 0 || int'(rx_data) > COLS ||
                            int'(start_x) + int'(rx_data) > COLS ||
                            int'(length) != (command == ROW_CRC_COMMAND ? 5 : 4) +
                                                 2 * int'(rx_data)) good <= 0;
                    end
                    default: begin
                        if (!pos[0]) begin
                            if (((int'(pos) - 3) >> 1) < COLS) begin
                                stage_glyph[(int'(pos) - 3) >> 1] <= {rx_data[5:2], pending_glyph};
                                stage_attr[(int'(pos) - 3) >> 1] <= rx_data[1:0];
                                stage_vertical_half[(int'(pos) - 3) >> 1] <= rx_data[`UI_ATTR_VERTICAL_HALF_BIT];
                            end
                            if ((rx_data[7] != 0 || int'({rx_data[5:2], pending_glyph}) >= `UI_GLYPH_COUNT)) good <= 0;
                        end else pending_glyph <= rx_data;
                    end
                    endcase
                    end
                end
                if (pos == length - 2) begin
                    state <= IDLE;
                    if (command == `UI_ROW_COMMAND || command == ROW_CRC_COMMAND) begin
                        if (good && ((command == ROW_CRC_COMMAND && rx_data == crc) ||
                                     (command == `UI_ROW_COMMAND && pos >= 4 && !pos[0] &&
                                      rx_data[7] == 0 &&
                                      int'({rx_data[5:2], pending_glyph}) < `UI_GLYPH_COUNT))) begin
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
