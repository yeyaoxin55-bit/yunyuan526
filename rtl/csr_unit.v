module csr_unit #(
    parameter XLEN = 32,
    parameter HART_ID = 0
) (
    input wire clk,
    input wire rst,
    input wire retire_i,
    input wire [1:0] retire_count_i,
    output reg [XLEN-1:0] mcycle_o,
    output reg [XLEN-1:0] minstret_o
);
    always @(posedge clk) begin
        if (rst) begin
            mcycle_o <= {XLEN{1'b0}};
            minstret_o <= {XLEN{1'b0}};
        end else begin
            mcycle_o <= mcycle_o + {{(XLEN-1){1'b0}}, 1'b1};
            if (retire_i) begin
                minstret_o <= minstret_o + {{(XLEN-2){1'b0}}, retire_count_i};
            end
        end
    end
endmodule
