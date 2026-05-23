`timescale 1ns/1ps

module tb_mul_pipeline_back_to_back;
    reg clk;
    reg rst;
    integer mul_struct_stall_count;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .MUL_STAGES(1),
        .FAST_MUL(0),
        .BP_LOCAL_HISTORY(0),
        .IMEM_INIT_FILE("tb/programs/mul_pipeline_back_to_back.hex"),
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

    always @(posedge clk) begin
        if (rst) begin
            mul_struct_stall_count <= 0;
        end else if (dut.u_core.u_hazard.if_id_mul_struct_dep) begin
            mul_struct_stall_count <= mul_struct_stall_count + 1;
        end
    end

    initial begin
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (120) @(posedge clk);

        if (dut.u_dmem.mem[0] !== 32'd6 ||
            dut.u_dmem.mem[1] !== 32'd6 ||
            dut.u_dmem.mem[2] !== 32'd6) begin
            $display("FAIL CPU b2b mul results: w0=%08x w1=%08x w2=%08x",
                dut.u_dmem.mem[0], dut.u_dmem.mem[1], dut.u_dmem.mem[2]);
            $finish;
        end

        if (mul_struct_stall_count != 0) begin
            $display("FAIL CPU b2b mul structural stalls=%0d", mul_struct_stall_count);
            $finish;
        end

        $display("PASS CPU back-to-back multiply pipeline regression completed");
        $finish;
    end
endmodule
