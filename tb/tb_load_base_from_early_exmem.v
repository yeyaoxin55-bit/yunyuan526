`timescale 1ns/1ps

module tb_load_base_from_early_exmem;
    reg clk;
    reg rst;
    integer cycle;
    integer load_use_stall_count;
    integer base_wait_count;
    integer exmem_base_early_count;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .ENABLE_ID_LOAD_EARLY_READ(1),
        .IMEM_INIT_FILE("tb/programs/load_base_from_early_exmem.hex"),
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
        load_use_stall_count = 0;
        base_wait_count = 0;
        exmem_base_early_count = 0;
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 140; cycle = cycle + 1) begin
            @(negedge clk);
            if (dut.u_core.id_load_early_read &&
                dut.u_core.ex_mem_valid &&
                dut.u_core.ex_mem_mem_read &&
                dut.u_core.ex_mem_load_early_valid &&
                (dut.u_core.ex_mem_rd == dut.u_core.if_id_load_rs1_q) &&
                (dut.u_core.if_id_load_rs1_q != 5'd0)) begin
                exmem_base_early_count = exmem_base_early_count + 1;
            end

            @(posedge clk);
            if (dut.u_core.hazard_stall) begin
                load_use_stall_count = load_use_stall_count + 1;
            end
            if (dut.u_core.id_load_early_base_wait) begin
                base_wait_count = base_wait_count + 1;
            end

            if (debug_dmem_word1 == 32'd1) begin
                if (debug_dmem_word2 != 32'd44) begin
                    $display("FAIL load-base-from-early-exmem result: word2=%08x", debug_dmem_word2);
                    $finish;
                end
                if (exmem_base_early_count == 0) begin
                    $display("FAIL load-base-from-early-exmem did not use EX/MEM early base");
                    $finish;
                end
                if (base_wait_count != 1) begin
                    $display("FAIL load-base-from-early-exmem base_wait=%0d", base_wait_count);
                    $finish;
                end
                if (load_use_stall_count != 0) begin
                    $display("FAIL load-base-from-early-exmem count=%0d", load_use_stall_count);
                    $finish;
                end
                $display("PASS load base from EX/MEM early-read regression completed");
                $finish;
            end
        end

        $display("FAIL load-base-from-early-exmem timeout: word1=%08x word2=%08x count=%0d base_wait=%0d exmem_count=%0d",
                 debug_dmem_word1, debug_dmem_word2, load_use_stall_count, base_wait_count, exmem_base_early_count);
        $finish;
    end
endmodule
