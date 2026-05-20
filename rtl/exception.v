module exception_unit (
    input wire illegal_instr_i,
    input wire load_misaligned_i,
    input wire store_misaligned_i,
    output wire trap_o,
    output wire [31:0] mcause_o
);
    assign trap_o = illegal_instr_i | load_misaligned_i | store_misaligned_i;
    assign mcause_o = illegal_instr_i ? 32'd2 :
                      load_misaligned_i ? 32'd4 :
                      store_misaligned_i ? 32'd6 :
                      32'd0;
endmodule
