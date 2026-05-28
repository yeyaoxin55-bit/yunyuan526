`timescale 1ns/1ps

module tb_rv64m_slow_mul_pipeline;
    reg clk;
    reg rst;
    integer cycle;

    cpu_top #(
        .XLEN(64),
        .IMEM_DEPTH(128),
        .DMEM_DEPTH(128),
        .DMEM_BASE(32'h00000000),
        .MUL_STAGES(4),
        .FAST_MUL(0),
        .ENABLE_MUL_EARLY_FORWARD(0),
        .ENABLE_MUL_COMPLETE_FORWARD(0),
        .BP_LOCAL_HISTORY(0)
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

    function [31:0] r_type;
        input [6:0] funct7;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            r_type = {funct7, rs2, rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] i_type;
        input integer imm;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            i_type = {imm[11:0], rs1, funct3, rd, opcode};
        end
    endfunction

    function [31:0] s_type;
        input integer imm;
        input [4:0] rs2;
        input [4:0] rs1;
        input [2:0] funct3;
        input [6:0] opcode;
        begin
            s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
        end
    endfunction

    function [31:0] u_type;
        input [19:0] imm20;
        input [4:0] rd;
        input [6:0] opcode;
        begin
            u_type = {imm20, rd, opcode};
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        dut.u_imem.mem[0]  = u_type(20'h80000, 5'd1, 7'b0110111);               // lui x1,0x80000
        dut.u_imem.mem[1]  = i_type(2, 5'd0, 3'b000, 5'd2, 7'b0010011);         // addi x2,x0,2
        dut.u_imem.mem[2]  = r_type(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0111011); // mulw x3,x1,x2
        dut.u_imem.mem[3]  = s_type(0, 5'd3, 5'd0, 3'b011, 7'b0100011);         // sd x3,0(x0)
        dut.u_imem.mem[4]  = i_type(-1, 5'd0, 3'b000, 5'd4, 7'b0011011);        // addiw x4,x0,-1
        dut.u_imem.mem[5]  = r_type(7'b0000001, 5'd2, 5'd4, 3'b001, 5'd5, 7'b0110011); // mulh x5,x4,x2
        dut.u_imem.mem[6]  = r_type(7'b0000001, 5'd2, 5'd4, 3'b010, 5'd6, 7'b0110011); // mulhsu x6,x4,x2
        dut.u_imem.mem[7]  = r_type(7'b0000001, 5'd2, 5'd4, 3'b011, 5'd7, 7'b0110011); // mulhu x7,x4,x2
        dut.u_imem.mem[8]  = s_type(8, 5'd5, 5'd0, 3'b011, 7'b0100011);         // sd x5,8(x0)
        dut.u_imem.mem[9]  = s_type(16, 5'd6, 5'd0, 3'b011, 7'b0100011);        // sd x6,16(x0)
        dut.u_imem.mem[10] = s_type(24, 5'd7, 5'd0, 3'b011, 7'b0100011);        // sd x7,24(x0)
        dut.u_imem.mem[11] = 32'h0000006f;                                      // jal x0,0

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 500; cycle = cycle + 1) begin
            @(posedge clk);
        end

        if (dut.u_dmem.mem[0] !== 64'h0000_0000_0000_0000) begin
            $display("FAIL rv64m slow mulw sign extension result=%016x", dut.u_dmem.mem[0]);
            $finish;
        end
        if (dut.u_dmem.mem[1] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64m slow mulh result=%016x", dut.u_dmem.mem[1]);
            $finish;
        end
        if (dut.u_dmem.mem[2] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64m slow mulhsu result=%016x", dut.u_dmem.mem[2]);
            $finish;
        end
        if (dut.u_dmem.mem[3] !== 64'h0000_0000_0000_0001) begin
            $display("FAIL rv64m slow mulhu result=%016x", dut.u_dmem.mem[3]);
            $finish;
        end

        $display("PASS rv64m slow multiplier pipeline");
        $finish;
    end
endmodule
