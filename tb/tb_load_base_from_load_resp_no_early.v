`timescale 1ns/1ps

module tb_load_base_from_load_resp_no_early;
    reg clk;
    reg rst;
    integer cycle;
    integer early_resp_base_violation;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .ENABLE_ID_LOAD_EARLY_READ(1),
        .IMEM_INIT_FILE("tb/programs/load_base_from_load_resp_no_early.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(debug_dmem_word2),
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
        early_resp_base_violation = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 160; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.id_load_early_read &&
                dut.u_core.load_wb_write_en &&
                (dut.u_core.load_resp_rd == dut.u_core.dec_hazard_rs1) &&
                (dut.u_core.dec_hazard_rs1 != 5'd0)) begin
                early_resp_base_violation = early_resp_base_violation + 1;
            end

            if (debug_dmem_word1 == 32'd1) begin
                if (debug_dmem_word2 != 32'd43) begin
                    $display("FAIL load-base-from-load-resp result: word2=%08x", debug_dmem_word2);
                    $finish;
                end
                if (early_resp_base_violation != 0) begin
                    $display("FAIL load-base-from-load-resp early-read violation count=%0d", early_resp_base_violation);
                    $finish;
                end
                $display("PASS load base from load response does not early-read");
                $finish;
            end
        end

        $display("FAIL load-base-from-load-resp timeout: word1=%08x word2=%08x violation=%0d",
                 debug_dmem_word1, debug_dmem_word2, early_resp_base_violation);
        $finish;
    end
endmodule
