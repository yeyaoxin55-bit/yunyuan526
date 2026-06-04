module m_unit #(
    parameter XLEN = 32,
    parameter MUL_PIPE_STAGES = 3,
    parameter EPOCH_WIDTH = 2
) (
    input wire clk,
    input wire rst,
    input wire req_valid_i,
    output wire req_ready_o,
    input wire [2:0] req_op_i,
    input wire [XLEN-1:0] req_rs1_i,
    input wire [XLEN-1:0] req_rs2_i,
    input wire [4:0] req_rd_i,
    input wire req_reg_write_i,
    input wire [EPOCH_WIDTH-1:0] req_epoch_i,
    input wire [EPOCH_WIDTH-1:0] current_epoch_i,
    output wire resp_valid_o,
    input wire resp_ready_i,
    output wire [4:0] resp_rd_o,
    output wire [XLEN-1:0] resp_result_o,
    output wire resp_reg_write_o,
    output wire [EPOCH_WIDTH-1:0] resp_epoch_o
);
    localparam PIPE_DEPTH = (MUL_PIPE_STAGES < 4) ? 4 : MUL_PIPE_STAGES;

    localparam OP_MUL    = 3'b000;
    localparam OP_MULH   = 3'b001;
    localparam OP_MULHSU = 3'b010;
    localparam OP_MULHU  = 3'b011;

    reg [PIPE_DEPTH-1:0] valid_pipe;
    reg [2:0] op_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs1_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] rs2_pipe [0:PIPE_DEPTH-1];
    reg [4:0] rd_pipe [0:PIPE_DEPTH-1];
    reg reg_write_pipe [0:PIPE_DEPTH-1];
    reg [EPOCH_WIDTH-1:0] epoch_pipe [0:PIPE_DEPTH-1];
    reg signed [(2*XLEN)+1:0] product_pipe [0:PIPE_DEPTH-1];
    reg [XLEN-1:0] result_pipe [0:PIPE_DEPTH-1];

    integer i;

    wire stage0_valid = valid_pipe[0];
    wire [2:0] stage_op = op_pipe[0];
    wire [XLEN-1:0] stage_rs1 = rs1_pipe[0];
    wire [XLEN-1:0] stage_rs2 = rs2_pipe[0];

    wire lhs_signed = (stage_op == OP_MULH) || (stage_op == OP_MULHSU);
    wire rhs_signed = (stage_op == OP_MULH);
    wire signed [XLEN:0] lhs_ext = lhs_signed ? {stage_rs1[XLEN-1], stage_rs1} :
                                                {1'b0, stage_rs1};
    wire signed [XLEN:0] rhs_ext = rhs_signed ? {stage_rs2[XLEN-1], stage_rs2} :
                                                {1'b0, stage_rs2};
    wire signed [(2*XLEN)+1:0] product = $signed(lhs_ext) * $signed(rhs_ext);

    reg [XLEN-1:0] product_result;
    wire final_valid = valid_pipe[PIPE_DEPTH-1];
    wire final_stale = final_valid &&
                       (epoch_pipe[PIPE_DEPTH-1] != current_epoch_i);
    wire advance_pipe = !final_valid || final_stale || resp_ready_i;

    assign req_ready_o = advance_pipe;
    assign resp_valid_o = final_valid && !final_stale;
    assign resp_rd_o = rd_pipe[PIPE_DEPTH-1];
    assign resp_result_o = result_pipe[PIPE_DEPTH-1];
    assign resp_reg_write_o = resp_valid_o &&
                              reg_write_pipe[PIPE_DEPTH-1] &&
                              (rd_pipe[PIPE_DEPTH-1] != 5'd0);
    assign resp_epoch_o = epoch_pipe[PIPE_DEPTH-1];

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
                rd_pipe[i] <= 5'd0;
                reg_write_pipe[i] <= 1'b0;
                epoch_pipe[i] <= {EPOCH_WIDTH{1'b0}};
                product_pipe[i] <= {((2*XLEN)+2){1'b0}};
                result_pipe[i] <= {XLEN{1'b0}};
            end
        end else if (advance_pipe) begin
            valid_pipe[0] <= req_valid_i;
            op_pipe[0] <= req_op_i;
            rs1_pipe[0] <= req_rs1_i;
            rs2_pipe[0] <= req_rs2_i;
            rd_pipe[0] <= req_rd_i;
            reg_write_pipe[0] <= req_reg_write_i;
            epoch_pipe[0] <= req_epoch_i;
            product_pipe[0] <= {((2*XLEN)+2){1'b0}};
            result_pipe[0] <= {XLEN{1'b0}};

            valid_pipe[1] <= stage0_valid;
            op_pipe[1] <= op_pipe[0];
            rs1_pipe[1] <= {XLEN{1'b0}};
            rs2_pipe[1] <= {XLEN{1'b0}};
            rd_pipe[1] <= rd_pipe[0];
            reg_write_pipe[1] <= reg_write_pipe[0];
            epoch_pipe[1] <= epoch_pipe[0];
            product_pipe[1] <= product;
            result_pipe[1] <= {XLEN{1'b0}};

            valid_pipe[2] <= valid_pipe[1];
            op_pipe[2] <= op_pipe[1];
            rs1_pipe[2] <= {XLEN{1'b0}};
            rs2_pipe[2] <= {XLEN{1'b0}};
            rd_pipe[2] <= rd_pipe[1];
            reg_write_pipe[2] <= reg_write_pipe[1];
            epoch_pipe[2] <= epoch_pipe[1];
            product_pipe[2] <= product_pipe[1];
            result_pipe[2] <= {XLEN{1'b0}};

            valid_pipe[3] <= valid_pipe[2];
            op_pipe[3] <= op_pipe[2];
            rs1_pipe[3] <= {XLEN{1'b0}};
            rs2_pipe[3] <= {XLEN{1'b0}};
            rd_pipe[3] <= rd_pipe[2];
            reg_write_pipe[3] <= reg_write_pipe[2];
            epoch_pipe[3] <= epoch_pipe[2];
            product_pipe[3] <= product_pipe[2];
            result_pipe[3] <= product_result;

            for (i = 4; i < PIPE_DEPTH; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                op_pipe[i] <= op_pipe[i-1];
                rs1_pipe[i] <= {XLEN{1'b0}};
                rs2_pipe[i] <= {XLEN{1'b0}};
                rd_pipe[i] <= rd_pipe[i-1];
                reg_write_pipe[i] <= reg_write_pipe[i-1];
                epoch_pipe[i] <= epoch_pipe[i-1];
                product_pipe[i] <= product_pipe[i-1];
                result_pipe[i] <= result_pipe[i-1];
            end
        end
    end
endmodule
