`include "defines.vh"

module alu #(
    parameter XLEN = 32
) (
    input wire [XLEN-1:0] a,
    input wire [XLEN-1:0] b,
    input wire [4:0] op,
    output reg [XLEN-1:0] y
);
    wire [4:0] shamt = b[4:0];

    always @(*) begin
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
endmodule
