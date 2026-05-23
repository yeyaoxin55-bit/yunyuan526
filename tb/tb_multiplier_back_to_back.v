`timescale 1ns/1ps

module tb_multiplier_back_to_back;
    reg clk;
    reg rst;
    reg start;
    reg [2:0] funct3;
    reg [31:0] a;
    reg [31:0] b;
    wire busy;
    wire early_valid;
    wire [31:0] early_result;
    wire valid;
    wire [31:0] result;
    integer valid_count;

    multiplier #(
        .XLEN(32),
        .MUL_STAGES(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start_i(start),
        .funct3_i(funct3),
        .a_i(a),
        .b_i(b),
        .busy_o(busy),
        .early_valid_o(early_valid),
        .early_result_o(early_result),
        .valid_o(valid),
        .result_o(result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (rst) begin
            valid_count <= 0;
        end else if (valid) begin
            valid_count <= valid_count + 1;
            case (valid_count)
                0: if (result !== 32'd6) begin
                    $display("FAIL b2b mul result0=%08x", result);
                    $finish;
                end
                1: if (result !== 32'd20) begin
                    $display("FAIL b2b mul result1=%08x", result);
                    $finish;
                end
                2: if (result !== 32'd42) begin
                    $display("FAIL b2b mul result2=%08x", result);
                    $finish;
                end
                default: begin
                    $display("FAIL b2b mul extra valid result=%08x", result);
                    $finish;
                end
            endcase
        end
    end

    initial begin
        rst = 1'b1;
        start = 1'b0;
        funct3 = 3'b000;
        a = 32'd0;
        b = 32'd0;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        @(posedge clk);
        start <= 1'b1;
        a <= 32'd2;
        b <= 32'd3;
        @(posedge clk);
        a <= 32'd4;
        b <= 32'd5;
        @(posedge clk);
        a <= 32'd6;
        b <= 32'd7;
        @(posedge clk);
        start <= 1'b0;
        a <= 32'd0;
        b <= 32'd0;

        repeat (12) @(posedge clk);
        if (valid_count != 3) begin
            $display("FAIL b2b mul valid_count=%0d", valid_count);
            $finish;
        end

        $display("PASS multiplier back-to-back regression completed");
        $finish;
    end
endmodule
