`timescale 1ns/1ps

module tb_ras_return;
    reg clk;
    reg rst;
    integer cycle;
    integer jump_flush_count;
    wire [31:0] debug_dmem_word1;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(1),
        .ENABLE_ID_LOAD_EARLY_READ(1),
        .IMEM_INIT_FILE("tb/programs/ras_return.hex"),
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
        jump_flush_count = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.jump_needs_flush) begin
                jump_flush_count = jump_flush_count + 1;
            end

            if (debug_dmem_word1 == 32'd1) begin
                if (jump_flush_count != 0) begin
                    $display("FAIL ras-return jump flush count=%0d", jump_flush_count);
                    $finish;
                end
                $display("PASS ras return regression completed");
                $finish;
            end
        end

        $display("FAIL ras-return timeout: word1=%08x jump_flush=%0d",
                 debug_dmem_word1, jump_flush_count);
        $finish;
    end
endmodule
