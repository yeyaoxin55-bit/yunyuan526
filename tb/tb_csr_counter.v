`timescale 1ns/1ps

module tb_csr_counter;
    reg clk;
    reg rst;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/csr_counter.hex"),
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
        repeat (100) @(posedge clk);

        if ((dut.u_dmem.mem[0] > 32'd0) &&
            (dut.u_dmem.mem[1] > 32'd0) &&
            (dut.u_dmem.mem[1] < dut.u_dmem.mem[0])) begin
            $display("PASS CSR counter regression completed");
            $finish;
        end

        $display("FAIL CSR counter: expected 0 < minstret < mcycle, mcycle=%08x minstret=%08x",
            dut.u_dmem.mem[0], dut.u_dmem.mem[1]);
        $finish;
    end
endmodule


