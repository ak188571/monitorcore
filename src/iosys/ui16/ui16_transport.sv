module ui16_transport #(
    parameter integer FREQ = 50_000_000,
    parameter integer TIMEOUT_MS = 10
) (
    input logic clk, resetn,
    input logic [7:0] rx_data,
    input logic rx_valid,
    output logic abort_frame,
    output logic busy,
    output logic error,
    output logic we,
    output logic [7:0] x, y, glyph,
    output logic selected, half
);
    localparam integer TIMEOUT_CYCLES = (FREQ/1000)*TIMEOUT_MS;
    localparam integer TIMER_BITS = $clog2(TIMEOUT_CYCLES+1);
    logic [TIMER_BITS-1:0] idle_cycles;
    wire receiving;
    // Commit is excluded from receiving: accepted rows always finish their writes.
    always_ff @(posedge clk) begin
        abort_frame <= 0;
        if (!resetn || rx_valid || !receiving) idle_cycles <= 0;
        else if (idle_cycles == TIMER_BITS'(TIMEOUT_CYCLES-1)) begin
            idle_cycles <= 0; abort_frame <= 1;
        end else idle_cycles <= idle_cycles + 1'b1;
    end
    ui_frame_decoder decoder (
        .clk(clk), .reset(!resetn), .rx_data(rx_data), .rx_valid(rx_valid),
        .rx_abort(abort_frame), .busy(busy), .receiving(receiving), .error(error),
        .we(we), .x(x), .y(y), .glyph(glyph), .selected(selected), .half(half)
    );
endmodule
