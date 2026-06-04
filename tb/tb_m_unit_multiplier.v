`timescale 1ns/1ps

module tb_m_unit_multiplier;
    reg clk;
    reg rst;

    reg req_valid32;
    wire req_ready32;
    reg [2:0] req_op32;
    reg [31:0] req_rs1_32;
    reg [31:0] req_rs2_32;
    reg [4:0] req_rd32;
    reg req_reg_write32;
    reg [1:0] req_epoch32;
    reg [1:0] current_epoch32;
    wire resp_valid32;
    reg resp_ready32;
    wire [4:0] resp_rd32;
    wire [31:0] resp_result32;
    wire resp_reg_write32;
    wire [1:0] resp_epoch32;

    reg req_valid64;
    wire req_ready64;
    reg [2:0] req_op64;
    reg [63:0] req_rs1_64;
    reg [63:0] req_rs2_64;
    reg [4:0] req_rd64;
    reg req_reg_write64;
    reg [1:0] req_epoch64;
    reg [1:0] current_epoch64;
    wire resp_valid64;
    reg resp_ready64;
    wire [4:0] resp_rd64;
    wire [63:0] resp_result64;
    wire resp_reg_write64;
    wire [1:0] resp_epoch64;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    m_unit #(
        .XLEN(32),
        .MUL_PIPE_STAGES(3),
        .EPOCH_WIDTH(2)
    ) dut32 (
        .clk(clk),
        .rst(rst),
        .req_valid_i(req_valid32),
        .req_ready_o(req_ready32),
        .req_op_i(req_op32),
        .req_rs1_i(req_rs1_32),
        .req_rs2_i(req_rs2_32),
        .req_rd_i(req_rd32),
        .req_reg_write_i(req_reg_write32),
        .req_epoch_i(req_epoch32),
        .current_epoch_i(current_epoch32),
        .resp_valid_o(resp_valid32),
        .resp_ready_i(resp_ready32),
        .resp_rd_o(resp_rd32),
        .resp_result_o(resp_result32),
        .resp_reg_write_o(resp_reg_write32),
        .resp_epoch_o(resp_epoch32)
    );

    m_unit #(
        .XLEN(64),
        .MUL_PIPE_STAGES(3),
        .EPOCH_WIDTH(2)
    ) dut64 (
        .clk(clk),
        .rst(rst),
        .req_valid_i(req_valid64),
        .req_ready_o(req_ready64),
        .req_op_i(req_op64),
        .req_rs1_i(req_rs1_64),
        .req_rs2_i(req_rs2_64),
        .req_rd_i(req_rd64),
        .req_reg_write_i(req_reg_write64),
        .req_epoch_i(req_epoch64),
        .current_epoch_i(current_epoch64),
        .resp_valid_o(resp_valid64),
        .resp_ready_i(resp_ready64),
        .resp_rd_o(resp_rd64),
        .resp_result_o(resp_result64),
        .resp_reg_write_o(resp_reg_write64),
        .resp_epoch_o(resp_epoch64)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task issue32;
        input [2:0] op;
        input [31:0] lhs;
        input [31:0] rhs;
        input [4:0] rd;
        begin
            @(negedge clk);
            while (req_ready32 !== 1'b1) begin
                @(negedge clk);
            end
            req_op32 = op;
            req_rs1_32 = lhs;
            req_rs2_32 = rhs;
            req_rd32 = rd;
            req_reg_write32 = 1'b1;
            req_epoch32 = 2'b00;
            req_valid32 = 1'b1;
            @(negedge clk);
            req_valid32 = 1'b0;
        end
    endtask

    task expect32;
        input [4:0] rd;
        input [31:0] expected;
        integer cycles;
        begin
            cycles = 0;
            while (resp_valid32 !== 1'b1) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (cycles > 30) begin
                    $display("FAIL m_unit RV32 response timeout");
                    $finish;
                end
            end
            if (resp_rd32 !== rd || resp_result32 !== expected ||
                resp_reg_write32 !== 1'b1 || resp_epoch32 !== 2'b00) begin
                $display("FAIL m_unit RV32 rd=%0d result=%08x reg_write=%b epoch=%0d expected rd=%0d result=%08x",
                    resp_rd32, resp_result32, resp_reg_write32, resp_epoch32, rd, expected);
                $finish;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task run32;
        input [2:0] op;
        input [31:0] lhs;
        input [31:0] rhs;
        input [31:0] expected;
        begin
            issue32(op, lhs, rhs, 5'd5);
            expect32(5'd5, expected);
        end
    endtask

    task issue64;
        input [2:0] op;
        input [63:0] lhs;
        input [63:0] rhs;
        input [4:0] rd;
        begin
            @(negedge clk);
            while (req_ready64 !== 1'b1) begin
                @(negedge clk);
            end
            req_op64 = op;
            req_rs1_64 = lhs;
            req_rs2_64 = rhs;
            req_rd64 = rd;
            req_reg_write64 = 1'b1;
            req_epoch64 = 2'b00;
            req_valid64 = 1'b1;
            @(negedge clk);
            req_valid64 = 1'b0;
        end
    endtask

    task expect64;
        input [4:0] rd;
        input [63:0] expected;
        integer cycles;
        begin
            cycles = 0;
            while (resp_valid64 !== 1'b1) begin
                @(posedge clk);
                #1;
                cycles = cycles + 1;
                if (cycles > 30) begin
                    $display("FAIL m_unit RV64 response timeout");
                    $finish;
                end
            end
            if (resp_rd64 !== rd || resp_result64 !== expected ||
                resp_reg_write64 !== 1'b1 || resp_epoch64 !== 2'b00) begin
                $display("FAIL m_unit RV64 rd=%0d result=%016x reg_write=%b epoch=%0d expected rd=%0d result=%016x",
                    resp_rd64, resp_result64, resp_reg_write64, resp_epoch64, rd, expected);
                $finish;
            end
            @(posedge clk);
            #1;
        end
    endtask

    task run64;
        input [2:0] op;
        input [63:0] lhs;
        input [63:0] rhs;
        input [63:0] expected;
        begin
            issue64(op, lhs, rhs, 5'd6);
            expect64(5'd6, expected);
        end
    endtask

    initial begin
        rst = 1'b1;
        req_valid32 = 1'b0;
        req_op32 = OP_MUL;
        req_rs1_32 = 32'h0000_0000;
        req_rs2_32 = 32'h0000_0000;
        req_rd32 = 5'd0;
        req_reg_write32 = 1'b0;
        req_epoch32 = 2'b00;
        current_epoch32 = 2'b00;
        resp_ready32 = 1'b1;

        req_valid64 = 1'b0;
        req_op64 = OP_MUL;
        req_rs1_64 = 64'h0000_0000_0000_0000;
        req_rs2_64 = 64'h0000_0000_0000_0000;
        req_rd64 = 5'd0;
        req_reg_write64 = 1'b0;
        req_epoch64 = 2'b00;
        current_epoch64 = 2'b00;
        resp_ready64 = 1'b1;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(negedge clk);

        run32(OP_MUL,    32'hffff_ffff, 32'h0000_0002, 32'hffff_fffe);
        run32(OP_MULH,   32'hffff_ffff, 32'h0000_0002, 32'hffff_ffff);
        run32(OP_MULHSU, 32'hffff_ffff, 32'h0000_0002, 32'hffff_ffff);
        run32(OP_MULHU,  32'hffff_ffff, 32'h0000_0002, 32'h0000_0001);

        run64(OP_MUL,    64'hffff_ffff_ffff_ffff, 64'h0000_0000_0000_0002, 64'hffff_ffff_ffff_fffe);
        run64(OP_MULH,   64'hffff_ffff_ffff_ffff, 64'h0000_0000_0000_0002, 64'hffff_ffff_ffff_ffff);
        run64(OP_MULHSU, 64'hffff_ffff_ffff_ffff, 64'h0000_0000_0000_0002, 64'hffff_ffff_ffff_ffff);
        run64(OP_MULHU,  64'hffff_ffff_ffff_ffff, 64'h0000_0000_0000_0002, 64'h0000_0000_0000_0001);

        $display("PASS m_unit multiplier directed regression completed");
        $finish;
    end
endmodule
