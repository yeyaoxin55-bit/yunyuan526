`timescale 1ns/1ps

module tb_branch_conditions;
    reg clk;
    reg rst;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/branch_conditions.hex"),
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

    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (180) @(posedge clk);

        if ((dut.u_dmem.mem[2] == 32'd7) && (dut.u_dmem.mem[1] == 32'd1)) begin
            $display("PASS branch condition regression completed");
            $finish;
        end

        $display("FAIL branch condition: w1=%08x w2=%08x",
            dut.u_dmem.mem[1], dut.u_dmem.mem[2]);
        $finish;
    end
endmodule


