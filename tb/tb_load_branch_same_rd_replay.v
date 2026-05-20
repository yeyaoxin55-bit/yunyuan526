`timescale 1ns/1ps

module tb_load_branch_same_rd_replay;
    reg clk;
    reg rst;
    integer cycle;
    integer load_use_stall_count;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word3;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(1),
        .IMEM_INIT_FILE("tb/programs/load_branch_same_rd_replay.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(),
        .debug_dmem_word3(debug_dmem_word3),
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
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 160; cycle = cycle + 1) begin
            @(posedge clk);
            if (dut.u_core.hazard_stall) begin
                load_use_stall_count = load_use_stall_count + 1;
            end
            if (debug_dmem_word1 == 32'd1) begin
                if (debug_dmem_word3 != 32'd7) begin
                    $display("FAIL load-branch-same-rd-replay result: word3=%08x", debug_dmem_word3);
                    $finish;
                end
                if (load_use_stall_count != 0) begin
                    $display("FAIL load-branch-same-rd-replay count=%0d", load_use_stall_count);
                    $finish;
                end
                $display("PASS load-branch same-rd replay regression completed");
                $finish;
            end
        end

        $display("FAIL load-branch-same-rd-replay timeout: word1=%08x word3=%08x count=%0d",
                 debug_dmem_word1, debug_dmem_word3, load_use_stall_count);
        $finish;
    end
endmodule
