`timescale 1ns/1ps

module tb_mem_width;
    reg clk;
    reg rst;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/mem_width.hex"),
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
        repeat (140) @(posedge clk);

        if ((dut.u_dmem.mem[2] == 32'd255) &&
            (dut.u_dmem.mem[3] == 32'hffff_ffff) &&
            (dut.u_dmem.mem[4] == 32'd52) &&
            (dut.u_dmem.mem[5] == 32'd52)) begin
            $display("PASS memory width regression completed");
            $finish;
        end

        $display("FAIL memory width: w2=%08x w3=%08x w4=%08x w5=%08x",
            dut.u_dmem.mem[2],
            dut.u_dmem.mem[3],
            dut.u_dmem.mem[4],
            dut.u_dmem.mem[5]);
        $finish;
    end
endmodule


