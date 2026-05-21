`ifndef YL3_DEFINES_VH
`define YL3_DEFINES_VH

`define OPCODE_LUI      7'b0110111
`define OPCODE_AUIPC    7'b0010111
`define OPCODE_JAL      7'b1101111
`define OPCODE_JALR     7'b1100111
`define OPCODE_BRANCH   7'b1100011
`define OPCODE_LOAD     7'b0000011
`define OPCODE_STORE    7'b0100011
`define OPCODE_OP_IMM   7'b0010011
`define OPCODE_OP_IMM_32 7'b0011011
`define OPCODE_OP       7'b0110011
`define OPCODE_OP_32    7'b0111011
`define OPCODE_MISC_MEM 7'b0001111
`define OPCODE_SYSTEM   7'b1110011

`define ALU_ADD  5'd0
`define ALU_SUB  5'd1
`define ALU_SLL  5'd2
`define ALU_SLT  5'd3
`define ALU_SLTU 5'd4
`define ALU_XOR  5'd5
`define ALU_SRL  5'd6
`define ALU_SRA  5'd7
`define ALU_OR   5'd8
`define ALU_AND  5'd9
`define ALU_PASS 5'd10

`endif
