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
    assign busy_o = 1'b0;

    generate
        if ((XLEN == 64) && (MUL_STAGES >= 4)) begin : gen_rv64_partial_pipeline
            reg operand_valid;
            reg partial_valid;
            reg sum_valid;
            reg [2:0] operand_funct3_q;
            reg [2:0] partial_funct3_q;
            reg [2:0] sum_funct3_q;
            reg operand_negate_q;
            reg partial_negate_q;
            reg sum_negate_q;
            reg [63:0] operand_a_mag_q;
            reg [63:0] operand_b_mag_q;
            reg [63:0] partial_ll_q;
            reg [63:0] partial_lh_q;
            reg [63:0] partial_hl_q;
            reg [63:0] partial_hh_q;
            reg [63:0] product_low_unsigned_q;
            reg [63:0] product_high_unsigned_q;
            reg [MUL_STAGES-1:0] valid_pipe;
            reg [63:0] result_pipe [0:MUL_STAGES-1];
            integer i;

            wire operand_signed_a = (funct3_i == 3'b001) || (funct3_i == 3'b010);
            wire operand_signed_b = (funct3_i == 3'b001);
            wire operand_a_neg = operand_signed_a && a_i[63];
            wire operand_b_neg = operand_signed_b && b_i[63];
            wire [63:0] operand_a_mag = operand_a_neg ? (~a_i + 64'd1) : a_i;
            wire [63:0] operand_b_mag = operand_b_neg ? (~b_i + 64'd1) : b_i;

            wire [63:0] product_ll = operand_a_mag_q[31:0] * operand_b_mag_q[31:0];
            wire [63:0] product_lh = operand_a_mag_q[31:0] * operand_b_mag_q[63:32];
            wire [63:0] product_hl = operand_a_mag_q[63:32] * operand_b_mag_q[31:0];
            wire [63:0] product_hh = operand_a_mag_q[63:32] * operand_b_mag_q[63:32];

            wire [33:0] partial_mid_sum = {2'b00, partial_ll_q[63:32]} +
                                          {2'b00, partial_lh_q[31:0]} +
                                          {2'b00, partial_hl_q[31:0]};
            wire [63:0] product_low_unsigned = {partial_mid_sum[31:0], partial_ll_q[31:0]};
            wire [65:0] product_high_sum = {2'b00, partial_hh_q} +
                                           {34'd0, partial_lh_q[63:32]} +
                                           {34'd0, partial_hl_q[63:32]} +
                                           {64'd0, partial_mid_sum[33:32]};
            wire [63:0] product_high_unsigned = product_high_sum[63:0];
            wire [63:0] product_low_signed = sum_negate_q ?
                                             (~product_low_unsigned_q + 64'd1) :
                                             product_low_unsigned_q;
            wire [63:0] product_high_signed = sum_negate_q ?
                                              (~product_high_unsigned_q +
                                               ((product_low_unsigned_q == 64'd0) ? 64'd1 : 64'd0)) :
                                              product_high_unsigned_q;

            reg [63:0] result_next;

            assign early_valid_o = valid_pipe[0];
            assign early_result_o = result_pipe[0];
            assign valid_o = valid_pipe[MUL_STAGES-1];
            assign result_o = result_pipe[MUL_STAGES-1];

            always @(*) begin
                case (sum_funct3_q)
                    3'b000: result_next = product_low_signed;
                    3'b001: result_next = product_high_signed;
                    3'b010: result_next = product_high_signed;
                    3'b011: result_next = product_high_unsigned_q;
                    default: result_next = 64'h0000_0000_0000_0000;
                endcase
            end

            always @(posedge clk) begin
                if (rst) begin
                    operand_valid <= 1'b0;
                    partial_valid <= 1'b0;
                    sum_valid <= 1'b0;
                    operand_funct3_q <= 3'b000;
                    partial_funct3_q <= 3'b000;
                    sum_funct3_q <= 3'b000;
                    operand_negate_q <= 1'b0;
                    partial_negate_q <= 1'b0;
                    sum_negate_q <= 1'b0;
                    operand_a_mag_q <= 64'h0000_0000_0000_0000;
                    operand_b_mag_q <= 64'h0000_0000_0000_0000;
                    partial_ll_q <= 64'h0000_0000_0000_0000;
                    partial_lh_q <= 64'h0000_0000_0000_0000;
                    partial_hl_q <= 64'h0000_0000_0000_0000;
                    partial_hh_q <= 64'h0000_0000_0000_0000;
                    product_low_unsigned_q <= 64'h0000_0000_0000_0000;
                    product_high_unsigned_q <= 64'h0000_0000_0000_0000;
                    valid_pipe <= {MUL_STAGES{1'b0}};
                    for (i = 0; i < MUL_STAGES; i = i + 1) begin
                        result_pipe[i] <= 64'h0000_0000_0000_0000;
                    end
                end else begin
                    operand_valid <= start_i;
                    if (start_i) begin
                        operand_funct3_q <= funct3_i;
                        operand_negate_q <= operand_a_neg ^ operand_b_neg;
                        operand_a_mag_q <= operand_a_mag;
                        operand_b_mag_q <= operand_b_mag;
                    end

                    partial_valid <= operand_valid;
                    if (operand_valid) begin
                        partial_funct3_q <= operand_funct3_q;
                        partial_negate_q <= operand_negate_q;
                        partial_ll_q <= product_ll;
                        partial_lh_q <= product_lh;
                        partial_hl_q <= product_hl;
                        partial_hh_q <= product_hh;
                    end

                    sum_valid <= partial_valid;
                    if (partial_valid) begin
                        sum_funct3_q <= partial_funct3_q;
                        sum_negate_q <= partial_negate_q;
                        product_low_unsigned_q <= product_low_unsigned;
                        product_high_unsigned_q <= product_high_unsigned;
                    end

                    valid_pipe[0] <= sum_valid;
                    result_pipe[0] <= result_next;
                    for (i = 1; i < MUL_STAGES; i = i + 1) begin
                        valid_pipe[i] <= valid_pipe[i-1];
                        result_pipe[i] <= result_pipe[i-1];
                    end
                end
            end
        end else begin : gen_direct_product_pipeline
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

            wire signed [(2*XLEN)-1:0] direct_product_ss = $signed(a_q) * $signed(b_q);
            wire [(2*XLEN)-1:0] direct_product_uu = a_q * b_q;
            wire signed [(2*XLEN):0] direct_product_su = $signed({a_q[XLEN-1], a_q}) *
                                                         $signed({1'b0, b_q});

            reg [XLEN-1:0] result_next;

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
                        product_ss_q <= direct_product_ss;
                        product_uu_q <= direct_product_uu;
                        product_su_q <= direct_product_su;
                    end

                    valid_pipe[0] <= product_valid;
                    result_pipe[0] <= result_next;
                    for (i = 1; i < MUL_STAGES; i = i + 1) begin
                        valid_pipe[i] <= valid_pipe[i-1];
                        result_pipe[i] <= result_pipe[i-1];
                    end
                end
            end
        end
    endgenerate
endmodule
