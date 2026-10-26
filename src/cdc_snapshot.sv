// Coherent slow-changing bus transfer. src_data is copied into a holding
// register on src_valid, then a toggle crosses through two destination-clock
// registers. The held bus remains unchanged until the next toggle, so the
// destination captures all bits from the same source snapshot.
module cdc_snapshot #(
    parameter integer WIDTH = 1
) (
    input  logic src_clk,
    input  logic src_resetn,
    input  logic src_valid,
    input  logic [WIDTH-1:0] src_data,
    input  logic dst_clk,
    input  logic dst_resetn,
    output logic [WIDTH-1:0] dst_data,
    output logic dst_valid
);
    logic [WIDTH-1:0] src_hold = '0 /* synthesis syn_preserve=1 */;
    logic src_toggle = 0 /* synthesis syn_preserve=1 */;
    logic [1:0] toggle_sync = 0 /* synthesis syn_preserve=1 */;
    logic toggle_seen = 0;

    always_ff @(posedge src_clk) begin
        if (!src_resetn) begin
            src_hold <= '0;
            src_toggle <= 0;
        end else if (src_valid) begin
            src_hold <= src_data;
            src_toggle <= ~src_toggle;
        end
    end

    always_ff @(posedge dst_clk) begin
        dst_valid <= 0;
        if (!dst_resetn) begin
            toggle_sync <= 0;
            toggle_seen <= 0;
            dst_data <= '0;
        end else begin
            toggle_sync <= {toggle_sync[0],src_toggle};
            if (toggle_sync[1] != toggle_seen) begin
                dst_data <= src_hold;
                toggle_seen <= toggle_sync[1];
                dst_valid <= 1;
            end
        end
    end
endmodule
