`timescale 1ns/1ps

module tb_branch_predictor;
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
        .BHT_DEPTH(8),
        .BHR_WIDTH(2),
        .BTB_DEPTH(8)
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

    task train;
        input [31:0] pc_i;
        input taken_i;
        input [31:0] target_i;
        begin
            @(posedge clk);
            update_pc <= pc_i;
            actual_taken <= taken_i;
            actual_target <= target_i;
            update_uncond <= 1'b0;
            update <= 1'b1;
            @(posedge clk);
            #1;
            update <= 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

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
        pc = 32'h00000020;
        update = 1'b0;
        update_uncond = 1'b0;
        update_pc = 32'h00000000;
        actual_taken = 1'b0;
        actual_target = 32'h00000000;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;

        if (predict_taken !== 1'b0 || predict_target !== 32'h00000024) begin
            $display("FAIL predictor reset prediction: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        train_uncond(32'h00000060, 32'h00000090);
        pc = 32'h00000060;
        #1;
        if (predict_taken !== 1'b1 || predict_target !== 32'h00000090) begin
            $display("FAIL predictor unconditional target: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        train(32'h00000020, 1'b1, 32'h00000010);
        train(32'h00000020, 1'b1, 32'h00000010);
        pc = 32'h00000020;
        #1;
        if (predict_taken !== 1'b1 || predict_target !== 32'h00000010) begin
            $display("FAIL predictor taken prediction: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        train(32'h00000020, 1'b0, 32'h00000024);
        train(32'h00000020, 1'b0, 32'h00000024);
        pc = 32'h00000020;
        #1;
        if (predict_taken !== 1'b0 || predict_target !== 32'h00000024) begin
            $display("FAIL predictor not-taken prediction: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        train(32'h00000040, 1'b0, 32'h00000044);
        train(32'h00000040, 1'b1, 32'h00000080);
        train(32'h00000040, 1'b0, 32'h00000044);
        train(32'h00000040, 1'b1, 32'h00000080);
        train(32'h00000040, 1'b0, 32'h00000044);
        train(32'h00000040, 1'b1, 32'h00000080);
        train(32'h00000040, 1'b0, 32'h00000044);
        train(32'h00000040, 1'b1, 32'h00000080);
        pc = 32'h00000040;
        #1;
        if (predict_taken !== 1'b0 || predict_target !== 32'h00000044) begin
            $display("FAIL predictor local-history not-taken: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        train(32'h00000040, 1'b0, 32'h00000044);
        pc = 32'h00000040;
        #1;
        if (predict_taken !== 1'b1 || predict_target !== 32'h00000080) begin
            $display("FAIL predictor local-history taken: taken=%b target=%08x", predict_taken, predict_target);
            $finish;
        end

        $display("PASS branch predictor unit regression completed");
        $finish;
    end
endmodule
