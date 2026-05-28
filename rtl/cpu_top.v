module cpu_top #(
    parameter XLEN = 64,
    parameter IMEM_DEPTH = 16384,
    parameter DMEM_DEPTH = 8192,
    parameter DMEM_BASE = 32'h00000000,
    parameter ENABLE_LOAD_USE_STALL = 1,
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 1,
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0,
    parameter ENABLE_ID_LOAD_EARLY_READ = 0,
    parameter ENABLE_MUL_EARLY_FORWARD = 1,
    parameter ENABLE_MUL_COMPLETE_FORWARD = 1,
    parameter ENABLE_M_EXT_LOAD_RESP_FORWARD = 1,
    parameter REGISTER_REDIRECT_TO_PC = 1,
    parameter MUL_STAGES = 1,
    parameter FAST_MUL = 1,
    parameter BP_BHT_DEPTH = 128,
    parameter BP_BHR_WIDTH = 3,
    parameter BP_BTB_DEPTH = 64,
    parameter BP_LOCAL_HISTORY = 1,
    parameter BP_INIT_TAKEN = 0,
    parameter IMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE_B0 = "",
    parameter DMEM_INIT_FILE_B1 = "",
    parameter DMEM_INIT_FILE_B2 = "",
    parameter DMEM_INIT_FILE_B3 = "",
    parameter SUPPORT_MISALIGNED_DMEM = 1
) (
    input wire clk,
    input wire rst,
    output wire [31:0] debug_dmem_word0,
    output wire [31:0] debug_dmem_word1,
    output wire [31:0] debug_dmem_word2,
    output wire [31:0] debug_dmem_word3,
    output wire [31:0] debug_dmem_word4,
    output wire [31:0] debug_pass_word,
    output wire [31:0] debug_fail_word,
    output wire [31:0] debug_cycle_word
);
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire dmem_read;
    wire dmem_read_early;
    wire dmem_write;
    wire [(XLEN/8)-1:0] dmem_byte_en;
    wire [31:0] dmem_addr;
    wire [XLEN-1:0] dmem_wdata;
    wire [XLEN-1:0] dmem_rdata;

    imem #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_INIT_FILE(IMEM_INIT_FILE)
    ) u_imem (
        .clk(clk),
        .addr(imem_addr),
        .rdata(imem_rdata),
        .loader_we(1'b0),
        .loader_addr(32'h00000000),
        .loader_wdata(32'h00000000)
    );

    dmem #(
        .XLEN(XLEN),
        .DMEM_DEPTH(DMEM_DEPTH),
        .DMEM_BASE(DMEM_BASE),
        .DMEM_INIT_FILE(DMEM_INIT_FILE),
        .DMEM_INIT_FILE_B0(DMEM_INIT_FILE_B0),
        .DMEM_INIT_FILE_B1(DMEM_INIT_FILE_B1),
        .DMEM_INIT_FILE_B2(DMEM_INIT_FILE_B2),
        .DMEM_INIT_FILE_B3(DMEM_INIT_FILE_B3),
        .SUPPORT_MISALIGNED(SUPPORT_MISALIGNED_DMEM)
    ) u_dmem (
        .clk(clk),
        .mem_read(dmem_read),
        .mem_write(dmem_write),
        .byte_en(dmem_byte_en),
        .addr(dmem_addr),
        .wdata(dmem_wdata),
        .rdata(dmem_rdata),
        .debug_word0(debug_dmem_word0),
        .debug_word1(debug_dmem_word1),
        .debug_word2(debug_dmem_word2),
        .debug_word3(debug_dmem_word3),
        .debug_word4(debug_dmem_word4),
        .debug_pass_word(debug_pass_word),
        .debug_fail_word(debug_fail_word),
        .debug_cycle_word(debug_cycle_word),
        .loader_we(1'b0),
        .loader_addr(DMEM_BASE),
        .loader_wdata(32'h00000000)
    );

    cpu_core #(
        .XLEN(XLEN),
        .ENABLE_LOAD_USE_STALL(ENABLE_LOAD_USE_STALL),
        .ENABLE_LOAD_RESP_EX_FORWARD(ENABLE_LOAD_RESP_EX_FORWARD),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(ENABLE_LOAD_CONTROL_EARLY_REPLAY),
        .ENABLE_ID_LOAD_EARLY_READ(ENABLE_ID_LOAD_EARLY_READ),
        .ENABLE_MUL_EARLY_FORWARD(ENABLE_MUL_EARLY_FORWARD),
        .ENABLE_MUL_COMPLETE_FORWARD(ENABLE_MUL_COMPLETE_FORWARD),
        .ENABLE_M_EXT_LOAD_RESP_FORWARD(ENABLE_M_EXT_LOAD_RESP_FORWARD),
        .REGISTER_REDIRECT_TO_PC(REGISTER_REDIRECT_TO_PC),
        .MUL_STAGES(MUL_STAGES),
        .FAST_MUL(FAST_MUL),
        .BP_BHT_DEPTH(BP_BHT_DEPTH),
        .BP_BHR_WIDTH(BP_BHR_WIDTH),
        .BP_BTB_DEPTH(BP_BTB_DEPTH),
        .BP_LOCAL_HISTORY(BP_LOCAL_HISTORY),
        .BP_INIT_TAKEN(BP_INIT_TAKEN)
    ) u_core (
        .clk(clk),
        .rst(rst),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_read(dmem_read),
        .dmem_read_early(dmem_read_early),
        .dmem_write(dmem_write),
        .dmem_byte_en(dmem_byte_en),
        .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata)
    );

endmodule
