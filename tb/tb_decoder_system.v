`timescale 1ns/1ps
`include "defines.vh"

module tb_decoder_system;
    reg [31:0] instr;
    wire [6:0] opcode;
    wire [4:0] rd;
    wire [2:0] funct3;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [6:0] funct7;
    wire [31:0] imm;
    wire [4:0] alu_op;
    wire alu_src_imm;
    wire reg_write;
    wire mem_read;
    wire mem_write;
    wire [1:0] wb_sel;
    wire branch;
    wire jump;
    wire jalr;
    wire csr_instr;
    wire [2:0] csr_op;
    wire [2:0] sys_event;
    wire illegal_instr;
    wire m_ext;

    decoder dut (
        .instr(instr),
        .opcode(opcode),
        .rd(rd),
        .funct3(funct3),
        .rs1(rs1),
        .rs2(rs2),
        .funct7(funct7),
        .imm(imm),
        .alu_op(alu_op),
        .alu_src_imm(alu_src_imm),
        .reg_write(reg_write),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .wb_sel(wb_sel),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .csr_instr(csr_instr),
        .csr_op(csr_op),
        .sys_event(sys_event),
        .illegal_instr(illegal_instr),
        .m_ext(m_ext)
    );

    task expect;
        input [31:0] value;
        input exp_csr;
        input [2:0] exp_csr_op;
        input [2:0] exp_sys;
        input exp_illegal;
        input exp_reg_write;
        begin
            instr = value;
            #1;
            if (csr_instr !== exp_csr ||
                csr_op !== exp_csr_op ||
                sys_event !== exp_sys ||
                illegal_instr !== exp_illegal ||
                reg_write !== exp_reg_write) begin
                $display("FAIL instr=%08x csr=%b/%b csr_op=%0d/%0d sys=%0d/%0d illegal=%b/%b reg_write=%b/%b",
                    value, csr_instr, exp_csr, csr_op, exp_csr_op,
                    sys_event, exp_sys, illegal_instr, exp_illegal,
                    reg_write, exp_reg_write);
                $finish;
            end
        end
    endtask

    initial begin
        expect(32'h00000073, 1'b0, `CSR_OP_NONE, `SYS_EVT_ECALL, 1'b0, 1'b0);
        expect(32'h00100073, 1'b0, `CSR_OP_NONE, `SYS_EVT_EBREAK, 1'b0, 1'b0);
        expect(32'h30200073, 1'b0, `CSR_OP_NONE, `SYS_EVT_MRET, 1'b0, 1'b0);
        expect(32'h300110f3, 1'b1, `CSR_OP_RW, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3001a0f3, 1'b1, `CSR_OP_RS, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3001b0f3, 1'b1, `CSR_OP_RC, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002d0f3, 1'b1, `CSR_OP_RWI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002e0f3, 1'b1, `CSR_OP_RSI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h3002f0f3, 1'b1, `CSR_OP_RCI, `SYS_EVT_NONE, 1'b0, 1'b1);
        expect(32'h10500073, 1'b0, `CSR_OP_NONE, `SYS_EVT_ILLEGAL, 1'b1, 1'b0);

        $display("PASS decoder system regression completed");
        $finish;
    end
endmodule
