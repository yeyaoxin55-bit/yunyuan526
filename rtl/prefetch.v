module prefetch #(
    parameter DEPTH = 4
) (
    input wire clk,
    input wire rst,
    input wire flush_i,
    input wire stall_i,
    input wire fetch_valid_i,
    input wire [31:0] fetch_pc_i,
    input wire [31:0] fetch_instr_i,
    input wire fetch_pred_taken_i,
    input wire [31:0] fetch_pred_target_i,
    output reg [31:0] pc_o,
    output reg [31:0] instr_o,
    output reg pred_taken_o,
    output reg [31:0] pred_target_o,
    output reg valid_o
);
    reg [31:0] current_pc;
    reg [31:0] current_instr;
    reg current_pred_taken;
    reg [31:0] current_pred_target;
    reg current_valid;
    reg [31:0] skid_pc;
    reg [31:0] skid_instr;
    reg skid_pred_taken;
    reg [31:0] skid_pred_target;
    reg skid_valid;

    always @(*) begin
        pc_o = current_pc;
        instr_o = current_instr;
        pred_taken_o = current_pred_taken;
        pred_target_o = current_pred_target;
        valid_o = current_valid;
    end

    always @(posedge clk) begin
        if (rst) begin
            current_pc <= 32'h00000000;
            current_instr <= 32'h00000013;
            current_pred_taken <= 1'b0;
            current_pred_target <= 32'h00000004;
            current_valid <= 1'b0;
            skid_pc <= 32'h00000000;
            skid_instr <= 32'h00000013;
            skid_pred_taken <= 1'b0;
            skid_pred_target <= 32'h00000004;
            skid_valid <= 1'b0;
        end else if (flush_i) begin
            current_pc <= 32'h00000000;
            current_instr <= 32'h00000013;
            current_pred_taken <= 1'b0;
            current_pred_target <= 32'h00000004;
            current_valid <= 1'b0;
            skid_pc <= 32'h00000000;
            skid_instr <= 32'h00000013;
            skid_pred_taken <= 1'b0;
            skid_pred_target <= 32'h00000004;
            skid_valid <= 1'b0;
        end else if (stall_i) begin
            if (fetch_valid_i && !skid_valid) begin
                skid_pc <= fetch_pc_i;
                skid_instr <= fetch_instr_i;
                skid_pred_taken <= fetch_pred_taken_i;
                skid_pred_target <= fetch_pred_target_i;
                skid_valid <= 1'b1;
            end
        end else if (skid_valid) begin
            current_pc <= skid_pc;
            current_instr <= skid_instr;
            current_pred_taken <= skid_pred_taken;
            current_pred_target <= skid_pred_target;
            current_valid <= 1'b1;
            skid_valid <= 1'b0;
        end else begin
            current_pc <= fetch_pc_i;
            current_instr <= fetch_valid_i ? fetch_instr_i : 32'h00000013;
            current_pred_taken <= fetch_valid_i ? fetch_pred_taken_i : 1'b0;
            current_pred_target <= fetch_valid_i ? fetch_pred_target_i : (fetch_pc_i + 32'd4);
            current_valid <= fetch_valid_i;
        end
    end
endmodule
