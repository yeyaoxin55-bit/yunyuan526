module fpga_coremark_top #(
    parameter XLEN = 64,
    parameter IMEM_INIT_FILE = "build/coremark/fpga/coremark.imem.hex",
    parameter DMEM_INIT_FILE = "build/coremark/fpga/coremark.dmem.hex",
    parameter MUL_STAGES = 1,
    parameter FAST_MUL = 0,
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 0,
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0,
    parameter ENABLE_ID_LOAD_EARLY_READ = 0,
    parameter BP_BHT_DEPTH = 64,
    parameter BP_BHR_WIDTH = 2,
    parameter BP_BTB_DEPTH = 32,
    parameter BP_LOCAL_HISTORY = 0
) (
    input wire clk,
    input wire rst_n,
    output wire pass_o,
    output wire fail_o,
    output wire done_o,
    output wire [31:0] cycle_o,
    output wire [3:0] led
);
    wire rst = ~rst_n;
    wire [31:0] debug_dmem_word0;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;
    wire [31:0] debug_dmem_word3;
    wire [31:0] debug_dmem_word4;
    wire [31:0] debug_pass_word;
    wire [31:0] debug_fail_word;
    wire [31:0] debug_cycle_word;

    cpu_top #(
        .XLEN(XLEN),
        .IMEM_DEPTH(16384),
        .DMEM_DEPTH(8192),
        .DMEM_BASE(32'h00010000),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(ENABLE_LOAD_RESP_EX_FORWARD),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(ENABLE_LOAD_CONTROL_EARLY_REPLAY),
        .ENABLE_ID_LOAD_EARLY_READ(ENABLE_ID_LOAD_EARLY_READ),
        .MUL_STAGES(MUL_STAGES),
        .FAST_MUL(FAST_MUL),
        .BP_BHT_DEPTH(BP_BHT_DEPTH),
        .BP_BHR_WIDTH(BP_BHR_WIDTH),
        .BP_BTB_DEPTH(BP_BTB_DEPTH),
        .BP_LOCAL_HISTORY(BP_LOCAL_HISTORY),
        .IMEM_INIT_FILE(IMEM_INIT_FILE),
        .DMEM_INIT_FILE(DMEM_INIT_FILE),
        .DMEM_INIT_FILE_B0({DMEM_INIT_FILE, ".b0"}),
        .DMEM_INIT_FILE_B1({DMEM_INIT_FILE, ".b1"}),
        .DMEM_INIT_FILE_B2({DMEM_INIT_FILE, ".b2"}),
        .DMEM_INIT_FILE_B3({DMEM_INIT_FILE, ".b3"}),
        .SUPPORT_MISALIGNED_DMEM(0)
    ) u_cpu_top (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(debug_dmem_word0),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(debug_dmem_word2),
        .debug_dmem_word3(debug_dmem_word3),
        .debug_dmem_word4(debug_dmem_word4),
        .debug_pass_word(debug_pass_word),
        .debug_fail_word(debug_fail_word),
        .debug_cycle_word(debug_cycle_word)
    );

    assign pass_o = (debug_pass_word == 32'h00000001);
    assign fail_o = (debug_fail_word != 32'h00000000);
    assign done_o = pass_o || fail_o;
    assign cycle_o = debug_cycle_word;
    assign led = {done_o, fail_o, pass_o, cycle_o[0]};
endmodule
