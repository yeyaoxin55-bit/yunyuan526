`timescale 1ns/1ps

module tb_load_mul_forward_boundary;
    reg clk;
    reg rst;
    integer cycle;
    wire [31:0] debug_dmem_word1;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(1),
        .ENABLE_ID_LOAD_EARLY_READ(1),
        .FAST_MUL(1),
        .MUL_STAGES(1),
        .IMEM_INIT_FILE("tb/programs/load_mul_forward_boundary.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(),
        .debug_dmem_word3(),
        .debug_dmem_word4(),
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

        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);
            if (debug_dmem_word1 == 32'd42) begin
                $display("PASS load-mul forwarding boundary regression completed");
                $finish;
            end
        end

        $display("FAIL load-mul forwarding boundary: word1=%08x", debug_dmem_word1);
        $finish;
    end
endmodule
