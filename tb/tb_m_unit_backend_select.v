`timescale 1ns/1ps

module tb_m_unit_backend_select;
    reg clk;
    reg rst;
    reg req_valid;
    wire req_ready_generic;
    wire req_ready_xilinx;
    reg [2:0] req_op;
    reg [31:0] req_rs1;
    reg [31:0] req_rs2;
    reg [4:0] req_rd;
    reg req_reg_write;
    reg [1:0] req_epoch;
    reg [1:0] current_epoch;
    wire resp_valid_generic;
    wire resp_valid_xilinx;
    reg resp_ready;
    wire [4:0] resp_rd_generic;
    wire [4:0] resp_rd_xilinx;
    wire [31:0] resp_result_generic;
    wire [31:0] resp_result_xilinx;
    wire resp_reg_write_generic;
    wire resp_reg_write_xilinx;
    wire [1:0] resp_epoch_generic;
    wire [1:0] resp_epoch_xilinx;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    m_unit #(
        .XLEN(32),
        .MUL_PIPE_STAGES(4),
        .EPOCH_WIDTH(2),
        .M_BACKEND(0)
    ) dut_generic (
        .clk(clk),
        .rst(rst),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready_generic),
        .req_op_i(req_op),
        .req_rs1_i(req_rs1),
        .req_rs2_i(req_rs2),
        .req_rd_i(req_rd),
        .req_reg_write_i(req_reg_write),
        .req_epoch_i(req_epoch),
        .current_epoch_i(current_epoch),
        .resp_valid_o(resp_valid_generic),
        .resp_ready_i(resp_ready),
        .resp_rd_o(resp_rd_generic),
        .resp_result_o(resp_result_generic),
        .resp_reg_write_o(resp_reg_write_generic),
        .resp_epoch_o(resp_epoch_generic)
    );

    m_unit #(
        .XLEN(32),
        .MUL_PIPE_STAGES(4),
        .EPOCH_WIDTH(2),
        .M_BACKEND(1)
    ) dut_xilinx (
        .clk(clk),
        .rst(rst),
        .req_valid_i(req_valid),
        .req_ready_o(req_ready_xilinx),
        .req_op_i(req_op),
        .req_rs1_i(req_rs1),
        .req_rs2_i(req_rs2),
        .req_rd_i(req_rd),
        .req_reg_write_i(req_reg_write),
        .req_epoch_i(req_epoch),
        .current_epoch_i(current_epoch),
        .resp_valid_o(resp_valid_xilinx),
        .resp_ready_i(resp_ready),
        .resp_rd_o(resp_rd_xilinx),
        .resp_result_o(resp_result_xilinx),
        .resp_reg_write_o(resp_reg_write_xilinx),
        .resp_epoch_o(resp_epoch_xilinx)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task issue;
        input [2:0] op;
        input [31:0] lhs;
        input [31:0] rhs;
        input [4:0] rd;
        begin
            @(negedge clk);
            while ((req_ready_generic !== 1'b1) || (req_ready_xilinx !== 1'b1)) begin
                @(negedge clk);
            end
            req_op = op;
            req_rs1 = lhs;
            req_rs2 = rhs;
            req_rd = rd;
            req_reg_write = 1'b1;
            req_epoch = 2'b00;
            req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
        end
    endtask

    task expect_both;
        input [4:0] rd;
        input [31:0] expected;
        integer cycles;
        begin
            cycles = 0;
            while ((resp_valid_generic !== 1'b1) || (resp_valid_xilinx !== 1'b1)) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (cycles > 40) begin
                    $display("FAIL m_unit backend selection response timeout generic_valid=%b xilinx_valid=%b",
                        resp_valid_generic, resp_valid_xilinx);
                    $finish;
                end
            end
            if (resp_rd_generic !== rd || resp_result_generic !== expected ||
                resp_reg_write_generic !== 1'b1 || resp_epoch_generic !== 2'b00) begin
                $display("FAIL m_unit generic backend rd=%0d result=%08x reg_write=%b epoch=%0d expected rd=%0d result=%08x",
                    resp_rd_generic, resp_result_generic, resp_reg_write_generic,
                    resp_epoch_generic, rd, expected);
                $finish;
            end
            if (resp_rd_xilinx !== rd || resp_result_xilinx !== expected ||
                resp_reg_write_xilinx !== 1'b1 || resp_epoch_xilinx !== 2'b00) begin
                $display("FAIL m_unit xilinx backend rd=%0d result=%08x reg_write=%b epoch=%0d expected rd=%0d result=%08x",
                    resp_rd_xilinx, resp_result_xilinx, resp_reg_write_xilinx,
                    resp_epoch_xilinx, rd, expected);
                $finish;
            end
            if (resp_result_generic !== resp_result_xilinx ||
                resp_rd_generic !== resp_rd_xilinx ||
                resp_reg_write_generic !== resp_reg_write_xilinx ||
                resp_epoch_generic !== resp_epoch_xilinx) begin
                $display("FAIL m_unit backend mismatch generic=%08x xilinx=%08x",
                    resp_result_generic, resp_result_xilinx);
                $finish;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task run_case;
        input [2:0] op;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            issue(op, lhs, rhs, 5'd9);
            expect_both(5'd9, expected);
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

        run_case(OP_MUL,    32'hffff_ffff, 32'h0000_0002, 32'hffff_fffe);
        run_case(OP_MULH,   32'hffff_ffff, 32'h0000_0002, 32'hffff_ffff);
        run_case(OP_MULHSU, 32'hffff_ffff, 32'h0000_0002, 32'hffff_ffff);
        run_case(OP_MULHU,  32'hffff_ffff, 32'h0000_0002, 32'h0000_0001);
        run_case(OP_MUL,    32'h0001_0001, 32'h0000_0003, 32'h0003_0003);

        $display("PASS m_unit backend selection regression completed");
        $finish;
    end
endmodule
