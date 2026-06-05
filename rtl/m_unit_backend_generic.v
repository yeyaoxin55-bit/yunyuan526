module m_unit_backend_generic #(
    parameter XLEN = 32,
    parameter PIPE_STAGES = 4
) (
    input wire clk,
    input wire rst,
    input wire advance_i,
    input wire valid_i,
    input wire [2:0] op_i,
    input wire [XLEN-1:0] rs1_i,
    input wire [XLEN-1:0] rs2_i,
    output wire valid_o,
    output wire [XLEN-1:0] result_o
);
    localparam PIPE_DEPTH = (PIPE_STAGES < 4) ? 4 : PIPE_STAGES;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    reg [PIPE_DEPTH-1:0] valid_pipe;
    reg [2:0] op_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs1_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs2_pipe [0:PIPE_DEPTH-1];
    reg signed [(2*XLEN)+1:0] product_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] result_pipe [0:PIPE_DEPTH-1];

    integer i;

    wire lhs_signed = (op_pipe[0] == OP_MULH) || (op_pipe[0] == OP_MULHSU);
    wire rhs_signed = (op_pipe[0] == OP_MULH);
    wire signed [XLEN:0] lhs_ext = lhs_signed ? {rs1_pipe[0][XLEN-1], rs1_pipe[0]} :
                                                {1'b0, rs1_pipe[0]};
    wire signed [XLEN:0] rhs_ext = rhs_signed ? {rs2_pipe[0][XLEN-1], rs2_pipe[0]} :
                                                {1'b0, rs2_pipe[0]};
    wire signed [(2*XLEN)+1:0] product = $signed(lhs_ext) * $signed(rhs_ext);

    reg [XLEN-1:0] product_result;

    assign valid_o = valid_pipe[PIPE_DEPTH-1];
    assign result_o = result_pipe[PIPE_DEPTH-1];

    always @(*) begin
        case (op_pipe[2])
            OP_MUL: begin
                product_result = product_pipe[2][XLEN-1:0];
            end
            OP_MULH,
            OP_MULHSU,
            OP_MULHU: begin
                product_result = product_pipe[2][(2*XLEN)-1:XLEN];
            end
            default: begin
                product_result = {XLEN{1'b0}};
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {PIPE_DEPTH{1'b0}};
            for (i = 0; i < PIPE_DEPTH; i = i + 1) begin
                op_pipe[i] <= OP_MUL;
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= {((2*XLEN)+2){1'b0}};
                result_pipe[i] <= {XLEN{1'b0}};
            end
        end else if (advance_i) begin
            valid_pipe[0] <= valid_i;
            op_pipe[0] <= op_i;
            rs1_pipe[0] <= rs1_i;
            rs2_pipe[0] <= rs2_i;
            product_pipe[0] <= {((2*XLEN)+2){1'b0}};
            result_pipe[0] <= {XLEN{1'b0}};

            valid_pipe[1] <= valid_pipe[0];
            op_pipe[1] <= op_pipe[0];
            rs1_pipe[1] <= {XLEN{1'b0}};
            rs2_pipe[1] <= {XLEN{1'b0}};
            product_pipe[1] <= product;
            result_pipe[1] <= {XLEN{1'b0}};

            valid_pipe[2] <= valid_pipe[1];
            op_pipe[2] <= op_pipe[1];
            rs1_pipe[2] <= {XLEN{1'b0}};
            rs2_pipe[2] <= {XLEN{1'b0}};
            product_pipe[2] <= product_pipe[1];
            result_pipe[2] <= {XLEN{1'b0}};

            valid_pipe[3] <= valid_pipe[2];
            op_pipe[3] <= op_pipe[2];
            rs1_pipe[3] <= {XLEN{1'b0}};
            rs2_pipe[3] <= {XLEN{1'b0}};
            product_pipe[3] <= product_pipe[2];
            result_pipe[3] <= product_result;

            for (i = 4; i < PIPE_DEPTH; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                op_pipe[i] <= op_pipe[i-1];
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                product_pipe[i] <= product_pipe[i-1];
                result_pipe[i] <= result_pipe[i-1];
            end
        end
    end
endmodule
