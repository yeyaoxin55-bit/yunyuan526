`timescale 1ns/1ps

module tb_m_unit_pipeline;
    reg clk;
    reg rst;
    reg req_valid;
    wire req_ready;
    reg [2:0] req_op;
    reg [31:0] req_rs1;
    reg [31:0] req_rs2;
    reg [4:0] req_rd;
    reg req_reg_write;
    reg [1:0] req_epoch;
    reg [1:0] current_epoch;
    wire resp_valid;
    reg resp_ready;
    wire [4:0] resp_rd;
    wire [31:0] resp_result;
    wire resp_reg_write;
    wire [1:0] resp_epoch;

    localparam OP_MUL = 3'b000;

    m_unit #(
        .XLEN(32),
        .MUL_PIPE_STAGES(3),
        .EPOCH_WIDTH(2)
    ) dut (
        .clk(clk),
        .rst(rst),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready),
        .req_op_i(req_op),
        .req_rs1_i(req_rs1),
        .req_rs2_i(req_rs2),
        .req_rd_i(req_rd),
        .req_reg_write_i(req_reg_write),
        .req_epoch_i(req_epoch),
        .current_epoch_i(current_epoch),
        .resp_valid_o(resp_valid),
        .resp_ready_i(resp_ready),
        .resp_rd_o(resp_rd),
        .resp_result_o(resp_result),
        .resp_reg_write_o(resp_reg_write),
        .resp_epoch_o(resp_epoch)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task issue;
        input [31:0] lhs;
        input [31:0] rhs;
        input [4:0] rd;
        input reg_write;
        input [1:0] epoch;
        begin
            @(negedge clk);
            while (req_ready !== 1'b1) begin
                @(negedge clk);
            end
            req_op = OP_MUL;
            req_rs1 = lhs;
            req_rs2 = rhs;
            req_rd = rd;
            req_reg_write = reg_write;
            req_epoch = epoch;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
        end
    endtask

    task expect_resp;
        input [4:0] rd;
        input [31:0] expected;
        input expected_reg_write;
        input [1:0] expected_epoch;
        integer cycles;
        begin
            cycles = 0;
            while (resp_valid !== 1'b1) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (cycles > 40) begin
                    $display("FAIL m_unit pipeline response timeout");
                    $finish;
                end
            end
            if (resp_rd !== rd || resp_result !== expected ||
                resp_reg_write !== expected_reg_write || resp_epoch !== expected_epoch) begin
                $display("FAIL m_unit pipeline response rd=%0d result=%08x reg_write=%b epoch=%0d expected rd=%0d result=%08x reg_write=%b epoch=%0d",
                    resp_rd, resp_result, resp_reg_write, resp_epoch,
                    rd, expected, expected_reg_write, expected_epoch);
                $finish;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task expect_no_response;
        input integer cycles;
        integer i;
        begin
            for (i = 0; i < cycles; i = i + 1) begin
                @(posedge clk);
                #1;
                if (resp_valid === 1'b1) begin
                    $display("FAIL m_unit stale response was not killed");
                    $finish;
                end
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        req_valid = 1'b0;
        req_op = OP_MUL;
        req_rs1 = 32'h0000_0000;
        req_rs2 = 32'h0000_0000;
        req_rd = 5'd0;
        req_reg_write = 1'b0;
        req_epoch = 2'b00;
        current_epoch = 2'b00;
        resp_ready = 1'b1;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);

        issue(32'd2, 32'd3, 5'd10, 1'b1, 2'b00);
        issue(32'd4, 32'd5, 5'd11, 1'b1, 2'b00);
        expect_resp(5'd10, 32'd6, 1'b1, 2'b00);
        expect_resp(5'd11, 32'd20, 1'b1, 2'b00);

        resp_ready = 1'b0;
        issue(32'd6, 32'd7, 5'd12, 1'b1, 2'b00);
        while (resp_valid !== 1'b1) begin
            @(posedge clk);
            #1;
        end
        if (resp_result !== 32'd42 || resp_rd !== 5'd12) begin
            $display("FAIL m_unit backpressure initial response");
            $finish;
        end
        repeat (3) begin
            @(posedge clk);
            #1;
            if (resp_valid !== 1'b1 || resp_result !== 32'd42 || resp_rd !== 5'd12) begin
                $display("FAIL m_unit response not stable under backpressure");
                $finish;
            end
        end
        resp_ready = 1'b1;
        @(posedge clk);
        #1;

        current_epoch = 2'b00;
        issue(32'd8, 32'd9, 5'd13, 1'b1, 2'b00);
        @(negedge clk);
        current_epoch = 2'b01;
        expect_no_response(12);

        issue(32'd3, 32'd9, 5'd0, 1'b1, 2'b01);
        expect_resp(5'd0, 32'd27, 1'b0, 2'b01);

        issue(32'd2, 32'd10, 5'd7, 1'b1, 2'b01);
        issue(32'd3, 32'd10, 5'd7, 1'b1, 2'b01);
        expect_resp(5'd7, 32'd20, 1'b1, 2'b01);
        expect_resp(5'd7, 32'd30, 1'b1, 2'b01);

        $display("PASS m_unit pipeline regression completed");
        $finish;
    end
endmodule
