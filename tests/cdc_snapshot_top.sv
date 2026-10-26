module cdc_snapshot_top (
    input logic src_clk, src_resetn, src_valid,
    input logic [11:0] src_data,
    input logic dst_clk, dst_resetn,
    output logic [11:0] dst_data,
    output logic dst_valid
);
    cdc_snapshot #(.WIDTH(12)) dut (.*);
endmodule
