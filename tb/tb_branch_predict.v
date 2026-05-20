`timescale 1ns/1ps

module tb_branch_predict;
    reg clk;
    reg rst;
    reg saw_taken_prediction;
    wire [31:0] debug_dmem_word0;
    wire [31:0] debug_dmem_word1;
    wire [31:0] debug_dmem_word2;
    wire [31:0] debug_dmem_word3;
    wire [31:0] debug_dmem_word4;

    cpu_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("tb/programs/branch_predict.hex"),
        .DMEM_INIT_FILE("")
    ) dut (
        .clk(clk),
        .rst(rst),
        .debug_dmem_word0(debug_dmem_word0),
        .debug_dmem_word1(debug_dmem_word1),
        .debug_dmem_word2(debug_dmem_word2),
        .debug_dmem_word3(debug_dmem_word3),
        .debug_dmem_word4(debug_dmem_word4),
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
            saw_taken_prediction <= 1'b0;
        end else if ((dut.u_core.pc == 32'h0000000c) && dut.u_core.predict_taken &&
                     (dut.u_core.predict_target == 32'h00000008)) begin
            saw_taken_prediction <= 1'b1;
        end
    end

    initial begin
        rst = 1'b1;
        saw_taken_prediction = 1'b0;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (160) @(posedge clk);

        if ((debug_dmem_word2 == 32'd5) && (debug_dmem_word1 == 32'd1) && saw_taken_prediction) begin
            $display("PASS branch prediction core regression completed");
            $finish;
        end

        $display("FAIL branch prediction: word2=%08x word1=%08x saw=%b",
            debug_dmem_word2, debug_dmem_word1, saw_taken_prediction);
        $finish;
    end
endmodule


