`timescale 1ns/1ps

module tb_rv64i_basic;
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

    function [31:0] shift_iw;
        input [6:0] funct7;
        input [4:0] shamt;
        input [4:0] rs1;
        input [2:0] funct3;
        input [4:0] rd;
        begin
            shift_iw = {funct7, shamt, rs1, funct3, rd, 7'b0011011};
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        dut.u_imem.mem[0]  = i_type(-1, 5'd0, 3'b000, 5'd1, 7'b0011011);         // addiw x1,x0,-1
        dut.u_imem.mem[1]  = shift_iw(7'b0000000, 5'd1, 5'd1, 3'b001, 5'd2);     // slliw x2,x1,1
        dut.u_imem.mem[2]  = shift_iw(7'b0000000, 5'd1, 5'd2, 3'b101, 5'd3);     // srliw x3,x2,1
        dut.u_imem.mem[3]  = shift_iw(7'b0100000, 5'd1, 5'd2, 3'b101, 5'd4);     // sraiw x4,x2,1
        dut.u_imem.mem[4]  = r_type(7'b0000000, 5'd3, 5'd3, 3'b000, 5'd5, 7'b0111011); // addw x5,x3,x3
        dut.u_imem.mem[5]  = r_type(7'b0100000, 5'd3, 5'd0, 3'b000, 5'd6, 7'b0111011); // subw x6,x0,x3
        dut.u_imem.mem[6]  = s_type(0, 5'd1, 5'd0, 3'b011, 7'b0100011);          // sd x1,0(x0)
        dut.u_imem.mem[7]  = s_type(8, 5'd2, 5'd0, 3'b011, 7'b0100011);          // sd x2,8(x0)
        dut.u_imem.mem[8]  = s_type(16, 5'd3, 5'd0, 3'b011, 7'b0100011);         // sd x3,16(x0)
        dut.u_imem.mem[9]  = s_type(24, 5'd4, 5'd0, 3'b011, 7'b0100011);         // sd x4,24(x0)
        dut.u_imem.mem[10] = s_type(32, 5'd5, 5'd0, 3'b011, 7'b0100011);         // sd x5,32(x0)
        dut.u_imem.mem[11] = s_type(40, 5'd6, 5'd0, 3'b011, 7'b0100011);         // sd x6,40(x0)
        dut.u_imem.mem[12] = i_type(32, 5'd0, 3'b011, 5'd7, 7'b0000011);         // ld x7,32(x0)
        dut.u_imem.mem[13] = s_type(48, 5'd7, 5'd0, 3'b011, 7'b0100011);         // sd x7,48(x0)
        dut.u_imem.mem[14] = i_type(32, 5'd0, 3'b110, 5'd8, 7'b0000011);         // lwu x8,32(x0)
        dut.u_imem.mem[15] = s_type(56, 5'd8, 5'd0, 3'b011, 7'b0100011);         // sd x8,56(x0)
        dut.u_imem.mem[16] = 32'h0000006f;                                      // jal x0,0

        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;

        for (cycle = 0; cycle < 120; cycle = cycle + 1) begin
            @(posedge clk);
        end

        if (dut.u_dmem.mem[0] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64i: addiw/sd result=%016x", dut.u_dmem.mem[0]);
            $finish;
        end
        if (dut.u_dmem.mem[1] !== 64'hffff_ffff_ffff_fffe) begin
            $display("FAIL rv64i: slliw result=%016x", dut.u_dmem.mem[1]);
            $finish;
        end
        if (dut.u_dmem.mem[2] !== 64'h0000_0000_7fff_ffff) begin
            $display("FAIL rv64i: srliw result=%016x", dut.u_dmem.mem[2]);
            $finish;
        end
        if (dut.u_dmem.mem[3] !== 64'hffff_ffff_ffff_ffff) begin
            $display("FAIL rv64i: sraiw result=%016x", dut.u_dmem.mem[3]);
            $finish;
        end
        if (dut.u_dmem.mem[4] !== 64'hffff_ffff_ffff_fffe) begin
            $display("FAIL rv64i: addw result=%016x", dut.u_dmem.mem[4]);
            $finish;
        end
        if (dut.u_dmem.mem[5] !== 64'hffff_ffff_8000_0001) begin
            $display("FAIL rv64i: subw result=%016x", dut.u_dmem.mem[5]);
            $finish;
        end
        if (dut.u_dmem.mem[6] !== 64'hffff_ffff_ffff_fffe) begin
            $display("FAIL rv64i: ld result=%016x", dut.u_dmem.mem[6]);
            $finish;
        end
        if (dut.u_dmem.mem[7] !== 64'h0000_0000_ffff_fffe) begin
            $display("FAIL rv64i: lwu result=%016x", dut.u_dmem.mem[7]);
            $finish;
        end

        $display("PASS rv64i basic");
        $finish;
    end
endmodule
