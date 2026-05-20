`timescale 1ns/1ps

module tb_jal_predict;
    reg clk;
    reg rst;
    integer cycle;
    integer id_jal_redirect_count;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .BP_BHT_DEPTH(16),
        .BP_BHR_WIDTH(2),
        .BP_BTB_DEPTH(16),
        .BP_LOCAL_HISTORY(1),
        .IMEM_INIT_FILE("tb/programs/jal_predict.hex"),
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
        id_jal_redirect_count = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 160; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.id_jal_redirect && (dut.u_core.if_id_pc == 32'h00000004)) begin
                id_jal_redirect_count = id_jal_redirect_count + 1;
            end

            if ((dut.u_dmem.mem[0] == 32'd0) && (dut.u_dmem.mem[1] == 32'd8)) begin
                if (dut.u_dmem.mem[3] != 32'd0) begin
                    $display("FAIL jal predict skipped path executed: word3=%08x", dut.u_dmem.mem[3]);
                    $finish;
                end
                if (id_jal_redirect_count > 1) begin
                    $display("FAIL jal predict redirects=%0d", id_jal_redirect_count);
                    $finish;
                end
                $display("PASS jal predict regression completed redirects=%0d", id_jal_redirect_count);
                $finish;
            end
        end

        $display("FAIL jal predict timeout: w0=%08x w1=%08x redirects=%0d",
                 dut.u_dmem.mem[0], dut.u_dmem.mem[1], id_jal_redirect_count);
        $finish;
    end
endmodule
