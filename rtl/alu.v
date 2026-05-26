`include "defines.vh"

module alu #(
    parameter XLEN = 32
) (
    input wire [XLEN-1:0] a,
    input wire [XLEN-1:0] b,
    input wire [4:0] op,
    input wire word_op,
    output reg [XLEN-1:0] y
);
    wire [5:0] shamt = (XLEN == 64) ? b[5:0] : {1'b0, b[4:0]};
    wire [4:0] shamtw = b[4:0];
    reg [31:0] word_y;

    function [XLEN-1:0] sign_extend_word;
        input [31:0] value;
        begin
            if (XLEN == 32) begin
                sign_extend_word = value;
            end else begin
                sign_extend_word = {{(XLEN-32){value[31]}}, value};
            end
        end
    endfunction

    always @(*) begin
        if (word_op) begin
            case (op)
                `ALU_ADD:  word_y = a[31:0] + b[31:0];
                `ALU_SUB:  word_y = a[31:0] - b[31:0];
                `ALU_SLL:  word_y = a[31:0] << shamtw;
                `ALU_SRL:  word_y = a[31:0] >> shamtw;
                `ALU_SRA:  word_y = $signed(a[31:0]) >>> shamtw;
                default:   word_y = 32'h00000000;
            endcase
            y = sign_extend_word(word_y);
        end else begin
            case (op)
                `ALU_ADD:  y = a + b;
                `ALU_SUB:  y = a - b;
                `ALU_SLL:  y = a << shamt;
                `ALU_SLT:  y = ($signed(a) < $signed(b)) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
                `ALU_SLTU: y = (a < b) ? {{(XLEN-1){1'b0}}, 1'b1} : {XLEN{1'b0}};
                `ALU_XOR:  y = a ^ b;
                `ALU_SRL:  y = a >> shamt;
                `ALU_SRA:  y = $signed(a) >>> shamt;
                `ALU_OR:   y = a | b;
                `ALU_AND:  y = a & b;
                `ALU_PASS: y = b;
                default:   y = {XLEN{1'b0}};
            endcase
        end
    end
endmodule
