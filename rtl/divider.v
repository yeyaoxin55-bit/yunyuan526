module divider #(
    parameter XLEN = 32
) (
    input wire clk,
    input wire rst,
    input wire start_i,
    input wire signed_i,
    input wire rem_i,
    input wire [XLEN-1:0] dividend_i,
    input wire [XLEN-1:0] divisor_i,
    output reg busy_o,
    output reg valid_o,
    output reg [XLEN-1:0] result_o
);
    localparam COUNT_W = $clog2(XLEN + 1);
    localparam [COUNT_W-1:0] XLEN_COUNT = XLEN;

    reg [COUNT_W-1:0] count;
    reg [XLEN-1:0] dividend_shift;
    reg [XLEN-1:0] divisor_abs_reg;
    reg [XLEN-1:0] quotient;
    reg [XLEN:0] remainder;
    reg result_neg;
    reg rem_neg;
    reg rem_mode;

    reg [XLEN:0] trial_remainder;
    reg [XLEN:0] remainder_next;
    reg [XLEN-1:0] quotient_next;
    reg [XLEN-1:0] result_next;

    wire div_by_zero = (divisor_i == {XLEN{1'b0}});
    wire overflow = (dividend_i == {1'b1, {(XLEN-1){1'b0}}}) && (divisor_i == {XLEN{1'b1}});
    wire dividend_negative = signed_i && dividend_i[XLEN-1];
    wire divisor_negative = signed_i && divisor_i[XLEN-1];
    wire [XLEN-1:0] dividend_abs = dividend_negative ? (~dividend_i + {{(XLEN-1){1'b0}}, 1'b1}) : dividend_i;
    wire [XLEN-1:0] divisor_abs = divisor_negative ? (~divisor_i + {{(XLEN-1){1'b0}}, 1'b1}) : divisor_i;

    always @(*) begin
        trial_remainder = {remainder[XLEN-1:0], dividend_shift[XLEN-1]};
        if (trial_remainder >= {1'b0, divisor_abs_reg}) begin
            remainder_next = trial_remainder - {1'b0, divisor_abs_reg};
            quotient_next = {quotient[XLEN-2:0], 1'b1};
        end else begin
            remainder_next = trial_remainder;
            quotient_next = {quotient[XLEN-2:0], 1'b0};
        end

        if (rem_mode) begin
            result_next = rem_neg ? (~remainder_next[XLEN-1:0] + {{(XLEN-1){1'b0}}, 1'b1}) :
                                    remainder_next[XLEN-1:0];
        end else begin
            result_next = result_neg ? (~quotient_next + {{(XLEN-1){1'b0}}, 1'b1}) :
                                      quotient_next;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            busy_o <= 1'b0;
            valid_o <= 1'b0;
            result_o <= {XLEN{1'b0}};
            count <= {COUNT_W{1'b0}};
            dividend_shift <= {XLEN{1'b0}};
            divisor_abs_reg <= {XLEN{1'b0}};
            quotient <= {XLEN{1'b0}};
            remainder <= {(XLEN+1){1'b0}};
            result_neg <= 1'b0;
            rem_neg <= 1'b0;
            rem_mode <= 1'b0;
        end else begin
            valid_o <= 1'b0;
            if (start_i && !busy_o) begin
                if (div_by_zero) begin
                    busy_o <= 1'b0;
                    valid_o <= 1'b1;
                    result_o <= rem_i ? dividend_i : {XLEN{1'b1}};
                    count <= {COUNT_W{1'b0}};
                end else if (signed_i && overflow) begin
                    busy_o <= 1'b0;
                    valid_o <= 1'b1;
                    result_o <= rem_i ? {XLEN{1'b0}} : {1'b1, {(XLEN-1){1'b0}}};
                    count <= {COUNT_W{1'b0}};
                end else begin
                    busy_o <= 1'b1;
                    count <= XLEN_COUNT;
                    dividend_shift <= dividend_abs;
                    divisor_abs_reg <= divisor_abs;
                    quotient <= {XLEN{1'b0}};
                    remainder <= {(XLEN+1){1'b0}};
                    result_neg <= signed_i && !rem_i && (dividend_i[XLEN-1] ^ divisor_i[XLEN-1]);
                    rem_neg <= signed_i && rem_i && dividend_i[XLEN-1];
                    rem_mode <= rem_i;
                end
            end else if (busy_o) begin
                dividend_shift <= {dividend_shift[XLEN-2:0], 1'b0};
                quotient <= quotient_next;
                remainder <= remainder_next;
                if (count <= {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                    busy_o <= 1'b0;
                    valid_o <= 1'b1;
                    count <= {COUNT_W{1'b0}};
                    result_o <= result_next;
                end else begin
                    count <= count - {{(COUNT_W-1){1'b0}}, 1'b1};
                end
            end
        end
    end
endmodule
