module hazard_unit #(
    parameter ENABLE_LOAD_USE_STALL = 0,
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 1,
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0,
    parameter ENABLE_ID_LOAD_EARLY_READ = 0
) (
    input wire id_ex_mem_read,
    input wire id_ex_load_early_valid,
    input wire [4:0] id_ex_rd,
    input wire [4:0] if_id_rs1,
    input wire [4:0] if_id_rs2,
    input wire if_id_conservative_load_use,
    input wire if_id_control_load_replay,
    input wire if_id_control_load_early_replay,
    input wire if_id_mul_src_dep_i,
    input wire if_id_mul_waw_dep_i,
    input wire if_id_mul_order_dep_i,
    input wire if_id_mul_struct_dep_i,
    input wire ex_mem_mem_read,
    input wire [4:0] ex_mem_rd,
    input wire load_resp_reg_write,
    input wire [4:0] load_resp_rd,
    input wire [1:0] id_ex_forward_a_i,
    input wire [1:0] id_ex_forward_b_i,
    output wire stall,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);
    wire id_ex_load_use = id_ex_mem_read &&
                          (id_ex_rd != 5'd0) &&
                          ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
    wire ex_mem_load_use = ex_mem_mem_read &&
                           (ex_mem_rd != 5'd0) &&
                           ((ex_mem_rd == if_id_rs1) || (ex_mem_rd == if_id_rs2));

    wire if_id_needs_ex_mem_load_stall = if_id_conservative_load_use ||
                                         ((ENABLE_LOAD_RESP_EX_FORWARD == 0) && !if_id_control_load_replay);
    wire load_resp_decode_use = load_resp_reg_write &&
                                (load_resp_rd != 5'd0) &&
                                ((load_resp_rd == if_id_rs1) ||
                                 (load_resp_rd == if_id_rs2));
    wire load_resp_rf_bypass_stall = (ENABLE_LOAD_RESP_EX_FORWARD == 0) &&
                                     load_resp_decode_use;
    wire id_ex_load_use_stall = id_ex_load_use &&
                                !((ENABLE_ID_LOAD_EARLY_READ != 0) &&
                                  id_ex_load_early_valid) &&
                                !((ENABLE_LOAD_CONTROL_EARLY_REPLAY != 0) &&
                                  if_id_control_load_early_replay);
    wire if_id_mul_src_dep = if_id_mul_src_dep_i;
    wire if_id_mul_waw_dep = if_id_mul_waw_dep_i;
    wire if_id_mul_order_dep = if_id_mul_order_dep_i;
    wire if_id_mul_struct_dep = if_id_mul_struct_dep_i;

    assign stall = ENABLE_LOAD_USE_STALL && (id_ex_load_use_stall ||
                                             (if_id_needs_ex_mem_load_stall && ex_mem_load_use) ||
                                             load_resp_rf_bypass_stall) ||
                    if_id_mul_src_dep ||
                    if_id_mul_waw_dep ||
                    if_id_mul_order_dep ||
                    if_id_mul_struct_dep;

    always @(*) begin
        forward_a = id_ex_forward_a_i;
        forward_b = id_ex_forward_b_i;
    end
endmodule
