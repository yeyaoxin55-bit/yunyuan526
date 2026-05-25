module multiplier #(
    parameter XLEN = 32,
    parameter MUL_STAGES = 2
) (
    input wire clk,
    input wire rst,
    input wire start_i,
    input wire [2:0] funct3_i,
    input wire [XLEN-1:0] a_i,
    input wire [XLEN-1:0] b_i,
    output wire busy_o,
    output wire early_valid_o,
    output wire [XLEN-1:0] early_result_o,
    output wire valid_o,
    output wire [XLEN-1:0] result_o
);
    reg [MUL_STAGES-1:0] valid_pipe;
    reg [XLEN-1:0] result_pipe [0:MUL_STAGES-1];
    reg operand_valid;
    reg product_valid;
    reg [2:0] funct3_q;
    reg [2:0] product_funct3_q;
    reg [XLEN-1:0] a_q;
    reg [XLEN-1:0] b_q;
    reg [(2*XLEN)-1:0] product_ss_q;
    reg [(2*XLEN)-1:0] product_uu_q;
    reg [(2*XLEN):0] product_su_q;
    integer i;

    wire signed [(2*XLEN)-1:0] product_ss = $signed(a_q) * $signed(b_q);
    wire [(2*XLEN)-1:0] product_uu = a_q * b_q;
    wire signed [(2*XLEN):0] product_su = $signed({a_q[XLEN-1], a_q}) * $signed({1'b0, b_q});

    reg [XLEN-1:0] result_next;

    assign busy_o = 1'b0;
    assign early_valid_o = product_valid;
    assign early_result_o = result_next;
    assign valid_o = valid_pipe[MUL_STAGES-1];
    assign result_o = result_pipe[MUL_STAGES-1];

    always @(*) begin
        case (product_funct3_q)
            3'b000: result_next = product_ss_q[XLEN-1:0];
            3'b001: result_next = product_ss_q[(2*XLEN)-1:XLEN];
            3'b010: result_next = product_su_q[(2*XLEN)-1:XLEN];
            3'b011: result_next = product_uu_q[(2*XLEN)-1:XLEN];
            default: result_next = {XLEN{1'b0}};
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            operand_valid <= 1'b0;
            product_valid <= 1'b0;
            funct3_q <= 3'b000;
            product_funct3_q <= 3'b000;
            a_q <= {XLEN{1'b0}};
            b_q <= {XLEN{1'b0}};
            product_ss_q <= {(2*XLEN){1'b0}};
            product_uu_q <= {(2*XLEN){1'b0}};
            product_su_q <= {(2*XLEN+1){1'b0}};
            valid_pipe <= {MUL_STAGES{1'b0}};
            for (i = 0; i < MUL_STAGES; i = i + 1) begin
                result_pipe[i] <= {XLEN{1'b0}};
            end
        end else begin
            operand_valid <= start_i;
            if (start_i) begin
                funct3_q <= funct3_i;
                a_q <= a_i;
                b_q <= b_i;
            end

            product_valid <= operand_valid;
            if (operand_valid) begin
                product_funct3_q <= funct3_q;
                product_ss_q <= product_ss;
                product_uu_q <= product_uu;
                product_su_q <= product_su;
            end

            valid_pipe[0] <= product_valid;
            result_pipe[0] <= result_next;
            for (i = 1; i < MUL_STAGES; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                result_pipe[i] <= result_pipe[i-1];
            end
        end
    end
endmodule
