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
`define OPCODE_OP       7'b0110011
`define OPCODE_MISC_MEM 7'b0001111
`define OPCODE_SYSTEM   7'b1110011

`define CSR_OP_NONE 3'd0
`define CSR_OP_RW   3'd1
`define CSR_OP_RS   3'd2
`define CSR_OP_RC   3'd3
`define CSR_OP_RWI  3'd4
`define CSR_OP_RSI  3'd5
`define CSR_OP_RCI  3'd6

`define SYS_EVT_NONE   3'd0
`define SYS_EVT_ECALL  3'd1
`define SYS_EVT_EBREAK 3'd2
`define SYS_EVT_MRET   3'd3
`define SYS_EVT_ILLEGAL 3'd4

`define CSR_MSTATUS  12'h300
`define CSR_MISA     12'h301
`define CSR_MIE      12'h304
`define CSR_MTVEC    12'h305
`define CSR_MSCRATCH 12'h340
`define CSR_MEPC     12'h341
`define CSR_MCAUSE   12'h342
`define CSR_MTVAL    12'h343
`define CSR_MIP      12'h344
`define CSR_MCYCLE   12'hB00
`define CSR_MINSTRET 12'hB02
`define CSR_MCYCLEH  12'hB80
`define CSR_MINSTRETH 12'hB82
`define CSR_MVENDORID 12'hF11
`define CSR_MARCHID   12'hF12
`define CSR_MIMPID    12'hF13
`define CSR_MHARTID   12'hF14

`define CAUSE_INSTR_ADDR_MISALIGNED 32'd0
`define CAUSE_ILLEGAL_INSTRUCTION   32'd2
`define CAUSE_BREAKPOINT            32'd3
`define CAUSE_LOAD_ADDR_MISALIGNED  32'd4
`define CAUSE_STORE_ADDR_MISALIGNED 32'd6
`define CAUSE_ECALL_MMODE           32'd11

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
