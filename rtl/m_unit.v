module m_unit #(
    parameter XLEN = 32,
    parameter MUL_PIPE_STAGES = 3,
    parameter EPOCH_WIDTH = 2,
    parameter M_BACKEND = 0
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

    localparam M_BACKEND_GENERIC = 0;
    localparam M_BACKEND_XILINX_DSP = 1;

    reg [PIPE_DEPTH-1:0] valid_pipe;
    reg [4:0] rd_pipe [0:PIPE_DEPTH-1];
    reg reg_write_pipe [0:PIPE_DEPTH-1];
    reg [EPOCH_WIDTH-1:0] epoch_pipe [0:PIPE_DEPTH-1];

    integer i;

    wire backend_valid;
    wire [XLEN-1:0] backend_result;
    wire final_slot_valid = valid_pipe[PIPE_DEPTH-1];
    wire final_valid = final_slot_valid && backend_valid;
    wire final_stale = final_valid &&
                       (epoch_pipe[PIPE_DEPTH-1] != current_epoch_i);
    wire advance_pipe = !final_slot_valid || final_stale || resp_ready_i;

    assign req_ready_o = advance_pipe;
    assign resp_valid_o = final_valid && !final_stale;
    assign resp_rd_o = rd_pipe[PIPE_DEPTH-1];
    assign resp_result_o = backend_result;
    assign resp_reg_write_o = resp_valid_o &&
                              reg_write_pipe[PIPE_DEPTH-1] &&
                              (rd_pipe[PIPE_DEPTH-1] != 5'd0);
    assign resp_epoch_o = epoch_pipe[PIPE_DEPTH-1];

    generate
        if (M_BACKEND == M_BACKEND_XILINX_DSP) begin : gen_xilinx_backend
            m_unit_backend_xilinx_dsp #(
                .XLEN(XLEN),
                .PIPE_STAGES(PIPE_DEPTH)
            ) u_backend (
                .clk(clk),
                .rst(rst),
                .advance_i(advance_pipe),
                .valid_i(req_valid_i),
                .op_i(req_op_i),
                .rs1_i(req_rs1_i),
                .rs2_i(req_rs2_i),
                .valid_o(backend_valid),
                .result_o(backend_result)
            );
        end else begin : gen_generic_backend
            m_unit_backend_generic #(
                .XLEN(XLEN),
                .PIPE_STAGES(PIPE_DEPTH)
            ) u_backend (
                .clk(clk),
                .rst(rst),
                .advance_i(advance_pipe),
                .valid_i(req_valid_i),
                .op_i(req_op_i),
                .rs1_i(req_rs1_i),
                .rs2_i(req_rs2_i),
                .valid_o(backend_valid),
                .result_o(backend_result)
            );
        end
    endgenerate

    always @(posedge clk) begin
        if (rst) begin
            valid_pipe <= {PIPE_DEPTH{1'b0}};
            for (i = 0; i < PIPE_DEPTH; i = i + 1) begin
                rd_pipe[i] <= 5'd0;
                reg_write_pipe[i] <= 1'b0;
                epoch_pipe[i] <= {EPOCH_WIDTH{1'b0}};
            end
        end else if (advance_pipe) begin
            valid_pipe[0] <= req_valid_i;
            rd_pipe[0] <= req_rd_i;
            reg_write_pipe[0] <= req_reg_write_i;
            epoch_pipe[0] <= req_epoch_i;

            for (i = 1; i < PIPE_DEPTH; i = i + 1) begin
                valid_pipe[i] <= valid_pipe[i-1];
                rd_pipe[i] <= rd_pipe[i-1];
                reg_write_pipe[i] <= reg_write_pipe[i-1];
                epoch_pipe[i] <= epoch_pipe[i-1];
            end
        end
    end
endmodule
