`include "defines.vh"

module decoder #(
    parameter XLEN = 32
) (
    input wire [31:0] instr,
    output wire [6:0] opcode,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [6:0] funct7,
    output reg [XLEN-1:0] imm,
    output reg [4:0] alu_op,
    output reg alu_src_imm,
    output reg reg_write,
    output reg mem_read,
    output reg mem_write,
    output reg [1:0] wb_sel,
    output reg branch,
    output reg jump,
    output reg jalr,
    output reg csr_instr,
    output reg m_ext,
    output reg word_op
);
    assign opcode = instr[6:0];
    assign rd = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign funct7 = instr[31:25];

    wire [XLEN-1:0] imm_i = {{(XLEN-12){instr[31]}}, instr[31:20]};
    wire [XLEN-1:0] imm_s = {{(XLEN-12){instr[31]}}, instr[31:25], instr[11:7]};
    wire [XLEN-1:0] imm_b = {{(XLEN-13){instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [XLEN-1:0] imm_u = {{(XLEN-32){instr[31]}}, instr[31:12], 12'b0};
    wire [XLEN-1:0] imm_j = {{(XLEN-21){instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    always @(*) begin
        imm = {XLEN{1'b0}};
        alu_op = `ALU_ADD;
        alu_src_imm = 1'b0;
        reg_write = 1'b0;
        mem_read = 1'b0;
        mem_write = 1'b0;
        wb_sel = 2'd0;
        branch = 1'b0;
        jump = 1'b0;
        jalr = 1'b0;
        csr_instr = 1'b0;
        m_ext = 1'b0;
        word_op = 1'b0;

        case (opcode)
            `OPCODE_LUI: begin
                imm = imm_u;
                alu_op = `ALU_PASS;
                alu_src_imm = 1'b1;
                reg_write = 1'b1;
            end
            `OPCODE_AUIPC: begin
                imm = imm_u;
                alu_op = `ALU_ADD;
                alu_src_imm = 1'b1;
                reg_write = 1'b1;
                wb_sel = 2'd3;
            end
            `OPCODE_JAL: begin
                imm = imm_j;
                reg_write = 1'b1;
                wb_sel = 2'd2;
                jump = 1'b1;
            end
            `OPCODE_JALR: begin
                imm = imm_i;
                reg_write = 1'b1;
                wb_sel = 2'd2;
                jump = 1'b1;
                jalr = 1'b1;
            end
            `OPCODE_BRANCH: begin
                imm = imm_b;
                branch = 1'b1;
            end
            `OPCODE_LOAD: begin
                imm = imm_i;
                alu_op = `ALU_ADD;
                alu_src_imm = 1'b1;
                reg_write = 1'b1;
                mem_read = 1'b1;
                wb_sel = 2'd1;
            end
            `OPCODE_STORE: begin
                imm = imm_s;
                alu_op = `ALU_ADD;
                alu_src_imm = 1'b1;
                mem_write = 1'b1;
            end
            `OPCODE_OP_IMM: begin
                imm = imm_i;
                alu_src_imm = 1'b1;
                reg_write = 1'b1;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    3'b001: alu_op = `ALU_SLL;
                    3'b101: alu_op = instr[30] ? `ALU_SRA : `ALU_SRL;
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OPCODE_OP_IMM_32: begin
                if (XLEN == 64) begin
                    imm = imm_i;
                    alu_src_imm = 1'b1;
                    reg_write = 1'b1;
                    word_op = 1'b1;
                    case (funct3)
                        3'b000: alu_op = `ALU_ADD;
                        3'b001: alu_op = `ALU_SLL;
                        3'b101: alu_op = instr[30] ? `ALU_SRA : `ALU_SRL;
                        default: begin
                            reg_write = 1'b0;
                            word_op = 1'b0;
                        end
                    endcase
                end
            end
            `OPCODE_OP: begin
                reg_write = 1'b1;
                if (funct7 == 7'b0000001) begin
                    m_ext = 1'b1;
                end else begin
                    case ({funct7[5], funct3})
                        4'b0_000: alu_op = `ALU_ADD;
                        4'b1_000: alu_op = `ALU_SUB;
                        4'b0_001: alu_op = `ALU_SLL;
                        4'b0_010: alu_op = `ALU_SLT;
                        4'b0_011: alu_op = `ALU_SLTU;
                        4'b0_100: alu_op = `ALU_XOR;
                        4'b0_101: alu_op = `ALU_SRL;
                        4'b1_101: alu_op = `ALU_SRA;
                        4'b0_110: alu_op = `ALU_OR;
                        4'b0_111: alu_op = `ALU_AND;
                        default:  alu_op = `ALU_ADD;
                    endcase
                end
            end
            `OPCODE_OP_32: begin
                if (XLEN == 64) begin
                    reg_write = 1'b1;
                    word_op = 1'b1;
                    if (funct7 == 7'b0000001) begin
                        m_ext = 1'b1;
                    end else begin
                        case ({funct7[5], funct3})
                            4'b0_000: alu_op = `ALU_ADD;
                            4'b1_000: alu_op = `ALU_SUB;
                            4'b0_001: alu_op = `ALU_SLL;
                            4'b0_101: alu_op = `ALU_SRL;
                            4'b1_101: alu_op = `ALU_SRA;
                            default: begin
                                reg_write = 1'b0;
                                word_op = 1'b0;
                            end
                        endcase
                    end
                end
            end
            `OPCODE_SYSTEM: begin
                if (funct3 != 3'b000) begin
                    reg_write = 1'b1;
                    csr_instr = 1'b1;
                end
            end
            default: begin
                imm = {XLEN{1'b0}};
            end
        endcase
    end
endmodule
