`timescale 1ns/1ps

module tb_prefetch;
    reg clk;
    reg rst;
    reg flush;
    reg stall;
    reg fetch_valid;
    reg [31:0] fetch_pc;
    reg [31:0] fetch_instr;
    reg fetch_pred_taken;
    reg [31:0] fetch_pred_target;
    wire [31:0] pc;
    wire [31:0] instr;
    wire pred_taken;
    wire [31:0] pred_target;
    wire valid;

    prefetch #(.DEPTH(4)) dut (
        .clk(clk),
        .rst(rst),
        .flush_i(flush),
        .stall_i(stall),
        .fetch_valid_i(fetch_valid),
        .fetch_pc_i(fetch_pc),
        .fetch_instr_i(fetch_instr),
        .fetch_pred_taken_i(fetch_pred_taken),
        .fetch_pred_target_i(fetch_pred_target),
        .pc_o(pc),
        .instr_o(instr),
        .pred_taken_o(pred_taken),
        .pred_target_o(pred_target),
        .valid_o(valid)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst = 1'b1;
        flush = 1'b0;
        stall = 1'b0;
        fetch_valid = 1'b0;
        fetch_pc = 32'h00000000;
        fetch_instr = 32'h00000013;
        fetch_pred_taken = 1'b0;
        fetch_pred_target = 32'h00000004;
        repeat (3) @(posedge clk);
        rst = 1'b0;

        @(posedge clk);
        fetch_valid = 1'b1;
        fetch_pc = 32'h00000010;
        fetch_instr = 32'h00100093;
        fetch_pred_taken = 1'b1;
        fetch_pred_target = 32'h00000040;
        @(posedge clk);
        #1;
        fetch_valid = 1'b0;
        if (valid !== 1'b1 || pc !== 32'h00000010 || instr !== 32'h00100093 ||
            pred_taken !== 1'b1 || pred_target !== 32'h00000040) begin
            $display("FAIL prefetch accept: valid=%b pc=%08x instr=%08x pred=%b target=%08x",
                valid, pc, instr, pred_taken, pred_target);
            $finish;
        end

        stall = 1'b1;
        fetch_valid = 1'b1;
        fetch_pc = 32'h00000014;
        fetch_instr = 32'h00200113;
        fetch_pred_taken = 1'b0;
        fetch_pred_target = 32'h00000018;
        @(posedge clk);
        #1;
        fetch_valid = 1'b0;
        if (valid !== 1'b1 || pc !== 32'h00000010 || instr !== 32'h00100093) begin
            $display("FAIL prefetch hold: valid=%b pc=%08x instr=%08x", valid, pc, instr);
            $finish;
        end

        stall = 1'b0;
        flush = 1'b1;
        @(posedge clk);
        #1;
        flush = 1'b0;
        if (valid !== 1'b0) begin
            $display("FAIL prefetch flush: valid=%b pc=%08x instr=%08x", valid, pc, instr);
            $finish;
        end

        $display("PASS prefetch unit regression completed");
        $finish;
    end
endmodule
