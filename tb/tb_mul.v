`timescale 1ns/1ps

module tb_mul;
    reg clk;
    reg rst;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .MUL_STAGES(1),
        .FAST_MUL(0),
        .IMEM_INIT_FILE("tb/programs/mul.hex"),
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
        repeat (160) @(posedge clk);

        if ((dut.u_dmem.mem[0] == 32'd42) &&
            (dut.u_dmem.mem[1] == 32'hffff_ffff) &&
            (dut.u_dmem.mem[2] == 32'h00000001) &&
            (dut.u_dmem.mem[3] == 32'hffff_ffff)) begin
            $display("PASS multiply regression completed");
            $finish;
        end

        $display("FAIL multiply: w0=%08x w1=%08x w2=%08x w3=%08x",
            dut.u_dmem.mem[0], dut.u_dmem.mem[1], dut.u_dmem.mem[2], dut.u_dmem.mem[3]);
        $finish;
    end
endmodule


