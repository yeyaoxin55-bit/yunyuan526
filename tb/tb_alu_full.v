`timescale 1ns/1ps

module tb_alu_full;
    reg clk;
    reg rst;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/alu_full.hex"),
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
        repeat (220) @(posedge clk);

        if ((dut.u_dmem.mem[0] == 32'd8) &&
            (dut.u_dmem.mem[1] == 32'd2) &&
            (dut.u_dmem.mem[2] == 32'd1) &&
            (dut.u_dmem.mem[3] == 32'd7) &&
            (dut.u_dmem.mem[4] == 32'd6) &&
            (dut.u_dmem.mem[5] == 32'd40) &&
            (dut.u_dmem.mem[6] == 32'd0) &&
            (dut.u_dmem.mem[7] == 32'd1) &&
            (dut.u_dmem.mem[8] == 32'd0) &&
            (dut.u_dmem.mem[9] == 32'd8) &&
            (dut.u_dmem.mem[10] == 32'd8)) begin
            $display("PASS ALU full regression completed");
            $finish;
        end

        $display("FAIL ALU full: w0=%08x w1=%08x w2=%08x w3=%08x w4=%08x w5=%08x w6=%08x w7=%08x w8=%08x w9=%08x w10=%08x",
            dut.u_dmem.mem[0], dut.u_dmem.mem[1], dut.u_dmem.mem[2], dut.u_dmem.mem[3],
            dut.u_dmem.mem[4], dut.u_dmem.mem[5], dut.u_dmem.mem[6], dut.u_dmem.mem[7],
            dut.u_dmem.mem[8], dut.u_dmem.mem[9], dut.u_dmem.mem[10]);
        $finish;
    end
endmodule


