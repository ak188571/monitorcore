// The upstream UART uses an undefined module as a compile-time parameter assertion.
// Supply its declaration for Verilator; valid parameter generate branches omit it.
module ASSERTION_ERROR(input [799:0] message);
    initial $fatal(1,"UART parameter out of range: %s",message);
endmodule
