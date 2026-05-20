`timescale 1ns/1ps

module tb_multiplier;
    reg clk;
    reg rst;
    reg start;
    reg [2:0] funct3;
    reg [31:0] a;
    reg [31:0] b;
    wire busy;
    wire valid;
    wire [31:0] result;

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
        .valid_o(valid),
        .result_o(result)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task run_case;
        input [2:0] op;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            @(posedge clk);
            funct3 <= op;
            a <= lhs;
            b <= rhs;
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            @(posedge clk);
            #1;
            if (valid === 1'b1) begin
                $display("FAIL multiplier latency: valid asserted too early");
                $finish;
            end
            @(posedge clk);
            #1;
            if (valid !== 1'b1) begin
                $display("FAIL multiplier latency: valid did not assert from output pipeline stage");
                $finish;
            end
            if (result !== expected) begin
                $display("FAIL multiplier op=%0d a=%08x b=%08x result=%08x expected=%08x",
                    op, lhs, rhs, result, expected);
                $finish;
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        start = 1'b0;
        funct3 = 3'b000;
        a = 32'h00000000;
        b = 32'h00000000;
        repeat (4) @(posedge clk);
        rst = 1'b0;

        run_case(3'b000, 32'd7, 32'd6, 32'd42);
        run_case(3'b001, 32'hffff_ffff, 32'd2, 32'hffff_ffff);
        run_case(3'b010, 32'hffff_ffff, 32'd2, 32'hffff_ffff);
        run_case(3'b011, 32'hffff_ffff, 32'd2, 32'h00000001);

        $display("PASS multiplier unit regression completed");
        $finish;
    end
endmodule
