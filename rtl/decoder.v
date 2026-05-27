`include "defines.vh"

module decoder (
    input wire [31:0] instr,
    output wire [6:0] opcode,
    output wire [4:0] rd,
    output wire [2:0] funct3,
    output wire [4:0] rs1,
    output wire [4:0] rs2,
    output wire [6:0] funct7,
    output reg [31:0] imm,
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
    output reg [2:0] csr_op,
    output reg [2:0] sys_event,
    output reg illegal_instr,
    output reg m_ext
);
    assign opcode = instr[6:0];
    assign rd = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs1 = instr[19:15];
    assign rs2 = instr[24:20];
    assign funct7 = instr[31:25];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    always @(*) begin
        imm = 32'h00000000;
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
        csr_op = `CSR_OP_NONE;
        sys_event = `SYS_EVT_NONE;
        illegal_instr = 1'b0;
        m_ext = 1'b0;

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
                if (funct3 != 3'b000) begin
                    illegal_instr = 1'b1;
                end
            end
            `OPCODE_BRANCH: begin
                imm = imm_b;
                branch = 1'b1;
                case (funct3)
                    3'b000,
                    3'b001,
                    3'b100,
                    3'b101,
                    3'b110,
                    3'b111: illegal_instr = 1'b0;
                    default: illegal_instr = 1'b1;
                endcase
            end
            `OPCODE_LOAD: begin
                imm = imm_i;
                alu_op = `ALU_ADD;
                alu_src_imm = 1'b1;
                reg_write = 1'b1;
                mem_read = 1'b1;
                wb_sel = 2'd1;
                case (funct3)
                    3'b000,
                    3'b001,
                    3'b010,
                    3'b100,
                    3'b101: illegal_instr = 1'b0;
                    default: illegal_instr = 1'b1;
                endcase
            end
            `OPCODE_STORE: begin
                imm = imm_s;
                alu_op = `ALU_ADD;
                alu_src_imm = 1'b1;
                mem_write = 1'b1;
                case (funct3)
                    3'b000,
                    3'b001,
                    3'b010: illegal_instr = 1'b0;
                    default: illegal_instr = 1'b1;
                endcase
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
                    3'b001: begin
                        alu_op = `ALU_SLL;
                        illegal_instr = (funct7 != 7'b0000000);
                    end
                    3'b101: begin
                        alu_op = instr[30] ? `ALU_SRA : `ALU_SRL;
                        illegal_instr = !((funct7 == 7'b0000000) ||
                                          (funct7 == 7'b0100000));
                    end
                    default: alu_op = `ALU_ADD;
                endcase
            end
            `OPCODE_OP: begin
                reg_write = 1'b1;
                if (funct7 == 7'b0000001) begin
                    m_ext = 1'b1;
                end else if (funct7 == 7'b0000000) begin
                    case ({funct7[5], funct3})
                        4'b0_000: alu_op = `ALU_ADD;
                        4'b0_001: alu_op = `ALU_SLL;
                        4'b0_010: alu_op = `ALU_SLT;
                        4'b0_011: alu_op = `ALU_SLTU;
                        4'b0_100: alu_op = `ALU_XOR;
                        4'b0_101: alu_op = `ALU_SRL;
                        4'b0_110: alu_op = `ALU_OR;
                        4'b0_111: alu_op = `ALU_AND;
                        default:  alu_op = `ALU_ADD;
                    endcase
                end else if (funct7 == 7'b0100000) begin
                    case (funct3)
                        3'b000: alu_op = `ALU_SUB;
                        3'b101: alu_op = `ALU_SRA;
                        default: illegal_instr = 1'b1;
                    endcase
                end else begin
                    illegal_instr = 1'b1;
                end
            end
            `OPCODE_MISC_MEM: begin
                illegal_instr = (funct3 != 3'b000);
            end
            `OPCODE_SYSTEM: begin
                case (funct3)
                    3'b000: begin
                        if (instr == 32'h00000073) begin
                            sys_event = `SYS_EVT_ECALL;
                        end else if (instr == 32'h00100073) begin
                            sys_event = `SYS_EVT_EBREAK;
                        end else if (instr == 32'h30200073) begin
                            sys_event = `SYS_EVT_MRET;
                        end else begin
                            sys_event = `SYS_EVT_ILLEGAL;
                            illegal_instr = 1'b1;
                        end
                    end
                    3'b001: begin csr_instr = 1'b1; csr_op = `CSR_OP_RW;  reg_write = 1'b1; end
                    3'b010: begin csr_instr = 1'b1; csr_op = `CSR_OP_RS;  reg_write = 1'b1; end
                    3'b011: begin csr_instr = 1'b1; csr_op = `CSR_OP_RC;  reg_write = 1'b1; end
                    3'b101: begin csr_instr = 1'b1; csr_op = `CSR_OP_RWI; reg_write = 1'b1; end
                    3'b110: begin csr_instr = 1'b1; csr_op = `CSR_OP_RSI; reg_write = 1'b1; end
                    3'b111: begin csr_instr = 1'b1; csr_op = `CSR_OP_RCI; reg_write = 1'b1; end
                    default: begin
                        sys_event = `SYS_EVT_ILLEGAL;
                        illegal_instr = 1'b1;
                    end
                endcase
            end
            default: begin
                imm = 32'h00000000;
                illegal_instr = 1'b1;
            end
        endcase
    end
endmodule
