`include "src/iosys/ui16/ui_config.svh"
// Dedicated microSD font update receiver. All payloads are staged and CRC8
// checked before changing the font RAM. Version-2 validated replays can write
// hidden slots while the display remains on; legacy writes require BLANK.
// UART protocol (all lengths count command itself):
//  AA 00 03 13 [0=BLANK,1=SHOW] [CRC8(data)]
//  AA 00 24 12 [slot_low slot_high 16*word_BE] [CRC8(34 bytes)]
// CRC-protected full-row commits from command 0x14 are observed via row_we/x/y;
// SHOW is accepted only after all 28 rows since BLANK and no error occurred.
// No ACK: malformed/dropped updates stay blank rather than displaying mixed glyphs.
module ui_font_transport #(
    parameter integer FREQ = 50_000_000,
    parameter integer TIMEOUT_MS = 10
) (
    input logic clk, resetn,
    input logic [7:0] rx_data,
    input logic rx_valid,
    input logic live_update,
    input logic row_error,
    input logic row_we,
    input logic [7:0] row_x,row_y,
    output logic font_we,
    output logic [`UI_FONT_ADDR_BITS-1:0] font_addr,
    output logic [15:0] font_data,
    output logic display_enabled,
    output logic error
);
    localparam integer TIMEOUT_CYCLES=(FREQ/1000)*TIMEOUT_MS;
    localparam integer TIMER_BITS=$clog2(TIMEOUT_CYCLES+1);
    localparam logic [2:0] IDLE=0,LEN_HI=1,LEN_LO=2,CMD=3,BODY=4,WRITE=5;
    logic [2:0] state=IDLE;
    logic [TIMER_BITS-1:0] idle_cycles=0;
    logic [15:0] length;
    logic [7:0] command, crc, high_byte, control_byte;
    logic [15:0] pos;
    logic slot_hi_valid;
    logic live_font_packet;
    logic [9:0] slot;
    logic [3:0] write_index;
    logic [15:0] pending_rows [0:15];
    logic [27:0] rows_seen;
    logic session_ok;
    wire font_write_allowed=(!display_enabled && session_ok) ||
                            (display_enabled && live_font_packet && live_update);

    function automatic [7:0] crc_next(input [7:0] current,input [7:0] b);
        reg [7:0] c;
        begin
            c=current^b;
            for (integer j=0;j<8;j=j+1)
                c = c[7] ? ((c<<1)^8'h07) : (c<<1);
            crc_next=c;
        end
    endfunction
    always_ff @(posedge clk) begin
        font_we <= 0;
        error <= 0;
        if (!resetn) begin
            state <= IDLE;
            idle_cycles <= 0;
            display_enabled <= 1;
            session_ok <= 0;
            rows_seen <= 0;
            length <= 0; command <= 0; pos <= 0; crc <= 0;
            slot <= 0; slot_hi_valid <= 0; write_index <= 0;
            live_font_packet <= 0;
            font_addr <= 0; font_data <= 0;
        end else begin
            if (!display_enabled) begin
                if (row_we && row_x == 31 && row_y < 28)
                    rows_seen[row_y[4:0]] <= 1;
                if (row_error) session_ok <= 0;
            end
            if (state == WRITE) begin
                font_we <= 1;
                font_addr <= `UI_FONT_ADDR_BITS'({slot,write_index});
                font_data <= pending_rows[write_index];
                if (write_index == 15) state <= IDLE;
                else write_index <= write_index + 1'b1;
            end
            if (state == IDLE || rx_valid) idle_cycles <= 0;
            else if (idle_cycles == TIMER_BITS'(TIMEOUT_CYCLES-1)) begin
                idle_cycles <= 0;
                state <= IDLE;
                error <= 1;
                if (!display_enabled) session_ok <= 0;
            end else idle_cycles <= idle_cycles + 1'b1;

            if (rx_valid && state != WRITE) begin
                case (state)
                IDLE: if (rx_data == 8'haa) state <= LEN_HI;
                LEN_HI: begin length[15:8] <= rx_data; state <= LEN_LO; end
                LEN_LO: begin
                    length[7:0] <= rx_data;
                    if ({length[15:8],rx_data} == 0 ||
                        {length[15:8],rx_data} > 16'd2047) state <= IDLE;
                    else state <= CMD;
                end
                CMD: begin
                    command <= rx_data; pos <= 0; crc <= 0;
                    live_font_packet <= live_update && rx_data == 8'h12;
                    if (length == 1) state <= IDLE;
                    else state <= BODY;
                    if ((rx_data == 8'h12 && length != 36) ||
                        (rx_data == 8'h13 && length != 3)) begin
                        error <= 1;
                        if (!display_enabled) session_ok <= 0;
                    end
                end
                BODY: begin
                    pos <= pos + 1'b1;
                    if (command == 8'h12 && length == 36) begin
                        if (pos < 34) crc <= crc_next(crc,rx_data);
                        case (pos)
                        0: slot[7:0] <= rx_data;
                        1: begin slot[9:8] <= rx_data[1:0]; slot_hi_valid <= (rx_data[7:2] == 0); end
                        default: if (pos >= 2 && pos <= 33) begin
                            if (pos[0] == 0) high_byte <= rx_data;
                            else pending_rows[(pos-2)>>1] <= {high_byte,rx_data};
                        end
                        endcase
                        if (pos == 34) begin
                            if (rx_data == crc && slot_hi_valid && font_write_allowed) begin
                                write_index <= 0;
                                state <= WRITE;
                            end else begin
                                error <= 1;
                                if (!display_enabled) session_ok <= 0;
                                state <= IDLE;
                            end
                        end
                    end else if (command == 8'h13 && length == 3) begin
                        if (pos == 0) begin
                            control_byte <= rx_data;
                            crc <= crc_next(crc,rx_data);
                        end
                        if (pos == 1) begin
                            if (rx_data == crc && control_byte == 0) begin
                                display_enabled <= 0;
                                rows_seen <= 0;
                                session_ok <= 1;
                            end else if (rx_data == crc && control_byte == 1 &&
                                         !display_enabled && session_ok && (&rows_seen)) begin
                                display_enabled <= 1;
                            end else begin
                                error <= 1;
                                if (!display_enabled) session_ok <= 0;
                            end
                        end
                    end
                    if (pos == length-2 &&
                        !(command == 8'h12 && length == 36 && rx_data == crc &&
                          slot_hi_valid && font_write_allowed)) state <= IDLE;
                end
                default: state <= IDLE;
                endcase
            end
        end
    end
endmodule
