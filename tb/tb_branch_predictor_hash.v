`timescale 1ns/1ps

module tb_branch_predictor_hash;
    reg clk;
    reg rst;
    reg [31:0] pc;
    wire predict_taken;
    wire [31:0] predict_target;
    reg update;
    reg update_uncond;
    reg [31:0] update_pc;
    reg actual_taken;
    reg [31:0] actual_target;

    branch_predictor #(
        .BHT_DEPTH(4),
        .BHR_WIDTH(1),
        .BTB_DEPTH(4),
        .LOCAL_HISTORY(0),
        .INIT_TAKEN(0),
        .BTB_INDEX_HASH(4)
    ) dut (
        .clk(clk),
        .rst(rst),
        .pc_i(pc),
        .predict_taken_o(predict_taken),
        .predict_target_o(predict_target),
        .update_i(update),
        .update_uncond_i(update_uncond),
        .update_pc_i(update_pc),
        .actual_taken_i(actual_taken),
        .actual_target_i(actual_target)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task train_uncond;
        input [31:0] pc_i;
        input [31:0] target_i;
        begin
            @(posedge clk);
            update_pc <= pc_i;
            actual_taken <= 1'b1;
            actual_target <= target_i;
            update_uncond <= 1'b1;
            update <= 1'b1;
            @(posedge clk);
            #1;
            update <= 1'b0;
            update_uncond <= 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst = 1'b1;
        pc = 32'h00000000;
        update = 1'b0;
        update_uncond = 1'b0;
        update_pc = 32'h00000000;
        actual_taken = 1'b0;
        actual_target = 32'h00000000;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;

        train_uncond(32'h00000000, 32'h00000100);
        train_uncond(32'h00000010, 32'h00000200);

        pc = 32'h00000000;
        #1;
        if (predict_taken !== 1'b1 || predict_target !== 32'h00000100) begin
            $display("FAIL hash should preserve first colliding BTB entry: taken=%b target=%08x",
                     predict_taken, predict_target);
            $finish;
        end

        pc = 32'h00000010;
        #1;
        if (predict_taken !== 1'b1 || predict_target !== 32'h00000200) begin
            $display("FAIL hash should preserve second colliding BTB entry: taken=%b target=%08x",
                     predict_taken, predict_target);
            $finish;
        end

        $display("PASS branch predictor hash regression completed");
        $finish;
    end
endmodule
