`timescale 1ns/1ps

module tb_mem_pipeline;
    reg clk;
    reg rst;
    integer cycle;
    integer mem_wait_count;
    wire [31:0] debug_dmem_word0;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;
    wire [31:0] debug_dmem_word3;
    wire [31:0] debug_dmem_word4;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .IMEM_INIT_FILE("tb/programs/mem_pipeline.hex"),
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
        mem_wait_count = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.mem_wait) begin
                mem_wait_count = mem_wait_count + 1;
            end
            if (debug_dmem_word3 == 32'd1) begin
                if (debug_dmem_word2 != 32'd49) begin
                    $display("FAIL mem-pipeline result: word2=%08x", debug_dmem_word2);
                    $finish;
                end
                if (mem_wait_count != 0) begin
                    $display("FAIL mem-pipeline: mem_wait_count=%0d", mem_wait_count);
                    $finish;
                end
                $display("PASS mem-pipeline regression completed");
                $finish;
            end
        end

        $display("FAIL mem-pipeline timeout: word2=%08x word3=%08x mem_wait_count=%0d",
                 debug_dmem_word2, debug_dmem_word3, mem_wait_count);
        $finish;
    end
endmodule
