`timescale 1ns/1ps

module tb_load_mul_slow_one_stall;
    reg clk;
    reg rst;
    integer cycle;
    integer id_ex_load_stalls;
    integer ex_mem_load_stalls;
    wire [31:0] debug_dmem_word1;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(1),
        .ENABLE_ID_LOAD_EARLY_READ(1),
        .FAST_MUL(0),
        .MUL_STAGES(1),
        .IMEM_INIT_FILE("tb/programs/load_mul_forward_boundary.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(),
        .debug_dmem_word1(debug_dmem_word1),
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
            id_ex_load_stalls <= 0;
            ex_mem_load_stalls <= 0;
        end else if (dut.u_core.hazard_stall) begin
            if (dut.u_core.u_hazard.id_ex_load_use) begin
                id_ex_load_stalls <= id_ex_load_stalls + 1;
            end
            if (dut.u_core.u_hazard.ex_mem_load_use) begin
                ex_mem_load_stalls <= ex_mem_load_stalls + 1;
            end
        end
    end

    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 140; cycle = cycle + 1) begin
            @(posedge clk);
            if (debug_dmem_word1 == 32'd42) begin
                if (id_ex_load_stalls != 1 || ex_mem_load_stalls != 0) begin
                    $display("FAIL slow load-mul stalls: id_ex=%0d ex_mem=%0d",
                        id_ex_load_stalls, ex_mem_load_stalls);
                    $finish;
                end
                $display("PASS slow load-mul one-stall regression completed");
                $finish;
            end
        end

        $display("FAIL slow load-mul result: word1=%08x", debug_dmem_word1);
        $finish;
    end
endmodule
