`timescale 1ns/1ps

module tb_registered_redirect;
    reg clk;
    reg rst;
    reg saw_redirect_detect;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/branch.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(),
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

    always @(posedge clk) begin
        if (rst) begin
            saw_redirect_detect <= 1'b0;
        end
    end

    always @(negedge clk) begin
        if (!rst && dut.u_core.branch_mispredict_raw && !dut.u_core.pipe_wait) begin
            saw_redirect_detect <= 1'b1;
            if (dut.u_core.flush) begin
                $display("FAIL registered redirect: flush asserted before redirect register edge");
                $finish;
            end
            @(posedge clk);
            #1;
            if (!dut.u_core.flush) begin
                $display("FAIL registered redirect: flush missing after redirect register edge");
                $finish;
            end
        end
    end

    initial begin
        rst = 1'b1;
        saw_redirect_detect = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (120) @(posedge clk);

        if (saw_redirect_detect) begin
            $display("PASS registered redirect regression completed");
            $finish;
        end

        $display("FAIL registered redirect: no redirect detected");
        $finish;
    end
endmodule
