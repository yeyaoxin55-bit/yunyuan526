`timescale 1ns/1ps

module tb_mul_result_forward_early;
    reg clk;
    reg rst;
    integer cycle;
    integer mul_src_stalls;

    wire [31:0] debug_dmem_word0;

    cpu_top #(
        .IMEM_INIT_FILE("tb/programs/mul_result_forward_early.hex"),
        .DMEM_INIT_FILE(""),
        .FAST_MUL(0),
        .MUL_STAGES(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(debug_dmem_word0),
        .debug_dmem_word1(),
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
        mul_src_stalls = 0;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 80; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.u_hazard.if_id_mul_src_dep) begin
                mul_src_stalls = mul_src_stalls + 1;
            end
            if (debug_dmem_word0 == 32'd8) begin
                if (mul_src_stalls != 1) begin
                    $display("FAIL expected one mul source stall, got %0d", mul_src_stalls);
                    $finish;
                end
                $display("PASS early multiply result forwarding regression completed");
                $finish;
            end
        end

        $display("FAIL timeout word0=%08x mul_src_stalls=%0d", debug_dmem_word0, mul_src_stalls);
        $finish;
    end
endmodule
