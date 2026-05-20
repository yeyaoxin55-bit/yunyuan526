`timescale 1ns/1ps

module tb_load_use;
    reg clk;
    reg rst;
    wire [31:0] debug_dmem_word0;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;
    wire [31:0] debug_dmem_word3;
    wire [31:0] debug_dmem_word4;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/load_use.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(debug_dmem_word0),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(debug_dmem_word2),
        .debug_dmem_word3(debug_dmem_word3),
        .debug_dmem_word4(debug_dmem_word4),
        .debug_pass_word(),
        .debug_fail_word(),
        .debug_cycle_word()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (100) @(posedge clk);

        if ((debug_dmem_word2 == 32'd43) && (debug_dmem_word1 == 32'd1)) begin
            $display("PASS load-use regression completed");
            $finish;
        end

        $display("FAIL load-use: word2=%08x word1=%08x", debug_dmem_word2, debug_dmem_word1);
        $finish;
    end
endmodule


