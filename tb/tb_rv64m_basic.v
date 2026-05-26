`timescale 1ns/1ps

module tb_rv64m_basic;
    reg clk;
    reg rst;
    integer cycle;

    cpu_top #(
        .XLEN(64),
        .IMEM_DEPTH(128),
        .DMEM_DEPTH(128),
        .DMEM_BASE(32'h00000000),
        .ENABLE_LOAD_RESP_EX_FORWARD(1),
        .FAST_MUL(1)
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
        dut.u_imem.mem[0]  = i_type(-2, 5'd0, 3'b000, 5'd1, 7'b0011011);         // addiw x1,x0,-2
        dut.u_imem.mem[1]  = i_type(3, 5'd0, 3'b000, 5'd2, 7'b0010011);          // addi x2,x0,3
        dut.u_imem.mem[2]  = r_type(7'b0000001, 5'd2, 5'd1, 3'b000, 5'd3, 7'b0111011); // mulw x3,x1,x2
        dut.u_imem.mem[3]  = s_type(0, 5'd3, 5'd0, 3'b011, 7'b0100011);          // sd x3,0(x0)
        dut.u_imem.mem[4]  = i_type(-7, 5'd0, 3'b000, 5'd4, 7'b0011011);         // addiw x4,x0,-7
        dut.u_imem.mem[5]  = i_type(2, 5'd0, 3'b000, 5'd5, 7'b0010011);          // addi x5,x0,2
        dut.u_imem.mem[6]  = r_type(7'b0000001, 5'd5, 5'd4, 3'b100, 5'd6, 7'b0111011); // divw x6,x4,x5
        dut.u_imem.mem[7]  = r_type(7'b0000001, 5'd5, 5'd4, 3'b110, 5'd7, 7'b0111011); // remw x7,x4,x5
        dut.u_imem.mem[8]  = s_type(8, 5'd6, 5'd0, 3'b011, 7'b0100011);          // sd x6,8(x0)
        dut.u_imem.mem[9]  = s_type(16, 5'd7, 5'd0, 3'b011, 7'b0100011);         // sd x7,16(x0)
        dut.u_imem.mem[10] = i_type(-16, 5'd0, 3'b000, 5'd8, 7'b0011011);        // addiw x8,x0,-16
        dut.u_imem.mem[11] = i_type(16, 5'd0, 3'b000, 5'd9, 7'b0010011);         // addi x9,x0,16
        dut.u_imem.mem[12] = r_type(7'b0000001, 5'd9, 5'd8, 3'b101, 5'd10, 7'b0111011); // divuw x10,x8,x9
        dut.u_imem.mem[13] = r_type(7'b0000001, 5'd9, 5'd8, 3'b111, 5'd11, 7'b0111011); // remuw x11,x8,x9
        dut.u_imem.mem[14] = s_type(24, 5'd10, 5'd0, 3'b011, 7'b0100011);        // sd x10,24(x0)
        dut.u_imem.mem[15] = s_type(32, 5'd11, 5'd0, 3'b011, 7'b0100011);        // sd x11,32(x0)
        dut.u_imem.mem[16] = u_type(20'h80000, 5'd12, 7'b0110111);               // lui x12,0x80000
        dut.u_imem.mem[17] = i_type(-1, 5'd0, 3'b000, 5'd13, 7'b0011011);        // addiw x13,x0,-1
        dut.u_imem.mem[18] = r_type(7'b0000001, 5'd13, 5'd12, 3'b100, 5'd14, 7'b0111011); // divw overflow
        dut.u_imem.mem[19] = r_type(7'b0000001, 5'd0, 5'd1, 3'b100, 5'd15, 7'b0111011);   // divw by zero
        dut.u_imem.mem[20] = r_type(7'b0000001, 5'd0, 5'd1, 3'b110, 5'd16, 7'b0111011);   // remw by zero
        dut.u_imem.mem[21] = s_type(40, 5'd14, 5'd0, 3'b011, 7'b0100011);        // sd x14,40(x0)
        dut.u_imem.mem[22] = s_type(48, 5'd15, 5'd0, 3'b011, 7'b0100011);        // sd x15,48(x0)
        dut.u_imem.mem[23] = s_type(56, 5'd16, 5'd0, 3'b011, 7'b0100011);        // sd x16,56(x0)
        dut.u_imem.mem[24] = 32'h0000006f;                                      // jal x0,0

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 900; cycle = cycle + 1) begin
            @(posedge clk);
        end

        if (dut.u_dmem.mem[0] !== 64'hffff_ffff_ffff_fffa) begin
            $display("FAIL rv64m: mulw result=%016x", dut.u_dmem.mem[0]);
            $finish;
        end
        if (dut.u_dmem.mem[1] !== 64'hffff_ffff_ffff_fffd) begin
            $display("FAIL rv64m: divw result=%016x", dut.u_dmem.mem[1]);
            $finish;
        end
        if (dut.u_dmem.mem[2] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64m: remw result=%016x", dut.u_dmem.mem[2]);
            $finish;
        end
        if (dut.u_dmem.mem[3] !== 64'h0000_0000_0fff_ffff) begin
            $display("FAIL rv64m: divuw result=%016x", dut.u_dmem.mem[3]);
            $finish;
        end
        if (dut.u_dmem.mem[4] !== 64'h0000_0000_0000_0000) begin
            $display("FAIL rv64m: remuw result=%016x", dut.u_dmem.mem[4]);
            $finish;
        end
        if (dut.u_dmem.mem[5] !== 64'hffff_ffff_8000_0000) begin
            $display("FAIL rv64m: divw overflow result=%016x", dut.u_dmem.mem[5]);
            $finish;
        end
        if (dut.u_dmem.mem[6] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64m: divw zero result=%016x", dut.u_dmem.mem[6]);
            $finish;
        end
        if (dut.u_dmem.mem[7] !== 64'hffff_ffff_ffff_fffe) begin
            $display("FAIL rv64m: remw zero result=%016x", dut.u_dmem.mem[7]);
            $finish;
        end

        $display("PASS rv64m basic");
        $finish;
    end
endmodule
