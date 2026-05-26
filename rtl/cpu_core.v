`include "defines.vh"

module cpu_core #(
    parameter XLEN = 32,
    parameter ENABLE_LOAD_USE_STALL = 1,
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 1,
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0,
    parameter ENABLE_ID_LOAD_EARLY_READ = 0,
    parameter MUL_STAGES = 1,
    parameter FAST_MUL = 1,
    parameter BP_BHT_DEPTH = 128,
    parameter BP_BHR_WIDTH = 3,
    parameter BP_BTB_DEPTH = 64,
    parameter BP_LOCAL_HISTORY = 1,
    parameter BP_INIT_TAKEN = 0
) (
    input wire clk,
    input wire rst,
    output reg [31:0] imem_addr,
    input wire [31:0] imem_rdata,
    output reg dmem_read,
    output reg dmem_read_early,
    output reg dmem_write,
    output reg [(XLEN/8)-1:0] dmem_byte_en,
    output reg [31:0] dmem_addr,
    output reg [XLEN-1:0] dmem_wdata,
    input wire [XLEN-1:0] dmem_rdata
);
    localparam DMEM_BYTES = XLEN / 8;
    localparam MUL_META_DEPTH = MUL_STAGES + 2;
    localparam MUL_FORWARD_STAGE = MUL_META_DEPTH - 2;
    localparam MUL_FIFO_DEPTH = 8;
    localparam [3:0] MUL_FIFO_DEPTH_COUNT = MUL_FIFO_DEPTH;
    localparam [4:0] MUL_FIFO_DEPTH_EXT = MUL_FIFO_DEPTH;

    function [XLEN-1:0] sign_extend_word;
        input [31:0] value;
        begin
            if (XLEN == 32) begin
                sign_extend_word = value;
            end else begin
                sign_extend_word = {{(XLEN-32){value[31]}}, value};
            end
        end
    endfunction

    function [XLEN-1:0] zero_extend_word;
        input [31:0] value;
        begin
            if (XLEN == 32) begin
                zero_extend_word = value;
            end else begin
                zero_extend_word = {{(XLEN-32){1'b0}}, value};
            end
        end
    endfunction

    function [XLEN-1:0] format_load_data;
        input [2:0] funct3;
        input [XLEN-1:0] raw_data;
        begin
            case (funct3)
                3'b000: format_load_data = {{(XLEN-8){raw_data[7]}}, raw_data[7:0]};
                3'b001: format_load_data = {{(XLEN-16){raw_data[15]}}, raw_data[15:0]};
                3'b010: format_load_data = sign_extend_word(raw_data[31:0]);
                3'b011: format_load_data = raw_data;
                3'b100: format_load_data = {{(XLEN-8){1'b0}}, raw_data[7:0]};
                3'b101: format_load_data = {{(XLEN-16){1'b0}}, raw_data[15:0]};
                3'b110: format_load_data = zero_extend_word(raw_data[31:0]);
                default: format_load_data = raw_data;
            endcase
        end
    endfunction

    reg [31:0] pc;
    reg [31:0] fetch_pc_q;
    reg fetch_valid_q;
    reg fetch_pred_taken_q;
    reg [31:0] fetch_pred_target_q;

    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg if_id_pred_taken;
    reg [31:0] if_id_pred_target;
    reg if_id_valid;
    reg if_id_mem_read_q;
    reg [4:0] if_id_load_rs1_q;
    reg if_id_load_rs1_nonzero_q;
    reg [XLEN-1:0] if_id_load_imm_q;

    reg id_ex_valid;
    reg [31:0] id_ex_pc;
    reg [XLEN-1:0] id_ex_imm;
    reg [XLEN-1:0] id_ex_rs1_data;
    reg [XLEN-1:0] id_ex_rs2_data;
    reg [4:0] id_ex_rs1;
    reg [4:0] id_ex_rs2;
    reg [4:0] id_ex_rd;
    reg [2:0] id_ex_funct3;
    reg [4:0] id_ex_alu_op;
    reg id_ex_alu_src_imm;
    reg id_ex_reg_write;
    reg id_ex_mem_read;
    reg id_ex_mem_write;
    reg [1:0] id_ex_wb_sel;
    reg id_ex_branch;
    reg id_ex_jump;
    reg id_ex_jalr;
    reg id_ex_jump_early_redirect;
    reg id_ex_csr_instr;
    reg [11:0] id_ex_csr_addr;
    reg id_ex_m_ext;
    reg id_ex_word_op;
    reg id_ex_pred_taken;
    reg [31:0] id_ex_pred_target;
    reg id_ex_load_early_valid;

    reg ex_mem_valid;
    reg [XLEN-1:0] ex_mem_alu_result;
    reg [XLEN-1:0] ex_mem_rs2_data;
    reg [31:0] ex_mem_pc4;
    reg [4:0] ex_mem_rd;
    reg [2:0] ex_mem_funct3;
    reg ex_mem_reg_write;
    reg ex_mem_mem_read;
    reg ex_mem_mem_write;
    reg [1:0] ex_mem_wb_sel;
    reg ex_mem_load_early_valid;
    reg [XLEN-1:0] ex_mem_load_early_data;

    reg mem_wb_valid;
    reg [XLEN-1:0] mem_wb_alu_result;
    reg [XLEN-1:0] mem_wb_mem_data;
    reg [31:0] mem_wb_pc4;
    reg [4:0] mem_wb_rd;
    reg mem_wb_reg_write;
    reg [1:0] mem_wb_wb_sel;
    reg load_resp_valid;
    reg [4:0] load_resp_rd;
    reg [2:0] load_resp_funct3;
    reg load_resp_reg_write;
    reg load_resp_early_valid;
    reg [XLEN-1:0] load_resp_early_data;
    reg [MUL_META_DEPTH-1:0] mul_meta_valid_pipe;
    reg [4:0] mul_meta_rd_pipe [0:MUL_META_DEPTH-1];
    reg mul_meta_reg_write_pipe [0:MUL_META_DEPTH-1];
    reg [4:0] mul_fifo_rd [0:MUL_FIFO_DEPTH-1];
    reg [XLEN-1:0] mul_fifo_data [0:MUL_FIFO_DEPTH-1];
    reg mul_fifo_reg_write [0:MUL_FIFO_DEPTH-1];
    reg [MUL_FIFO_DEPTH-1:0] mul_fifo_valid;
    reg [2:0] mul_fifo_head;
    reg [2:0] mul_fifo_tail;
    reg [3:0] mul_fifo_count;
    reg div_cmd_valid;
    reg [XLEN-1:0] div_cmd_rs1_data;
    reg [XLEN-1:0] div_cmd_rs2_data;
    reg [2:0] div_cmd_funct3;
    reg div_cmd_word_op;
    reg if_id_load_base_mul_pending_dep_q;
    reg [XLEN-1:0] if_id_rs1_raw_data_q;
    reg redirect_valid;
    reg [31:0] redirect_pc_q;
    reg [31:0] redirect_fallthrough_pc_q;
    reg redirect_taken_q;
    reg redirect_branch_mispredict;
    reg redirect_jump_flush;
    reg redirect_from_replay;
    reg ctrl_replay_valid;
    reg ctrl_replay_branch;
    reg ctrl_replay_jump;
    reg ctrl_replay_jalr;
    reg [31:0] ctrl_replay_pc;
    reg [XLEN-1:0] ctrl_replay_imm;
    reg [XLEN-1:0] ctrl_replay_rs1_data;
    reg [XLEN-1:0] ctrl_replay_rs2_data;
    reg [2:0] ctrl_replay_funct3;
    reg ctrl_replay_pred_taken;
    reg [31:0] ctrl_replay_pred_target;
    reg ctrl_load_pending_valid;
    reg ctrl_load_pending_branch;
    reg ctrl_load_pending_jump;
    reg ctrl_load_pending_jalr;
    reg [31:0] ctrl_load_pending_pc;
    reg [XLEN-1:0] ctrl_load_pending_imm;
    reg [XLEN-1:0] ctrl_load_pending_rs1_data;
    reg [XLEN-1:0] ctrl_load_pending_rs2_data;
    reg [2:0] ctrl_load_pending_funct3;
    reg ctrl_load_pending_pred_taken;
    reg [31:0] ctrl_load_pending_pred_target;
    reg ctrl_load_pending_rs1_from_load;
    reg ctrl_load_pending_rs2_from_load;
    reg [4:0] ctrl_load_pending_load_rd;
    reg ctrl_load_pending_wait_resp;
    reg [31:0] ras_stack [0:7];
    reg [3:0] ras_count;
    integer ras_i;
    integer mul_comb_i;
    integer mul_seq_i;
    wire replay_flush;

    wire [6:0] dec_opcode;
    wire [4:0] dec_rd;
    wire [2:0] dec_funct3;
    wire [4:0] dec_rs1;
    wire [4:0] dec_rs2;
    wire [6:0] dec_funct7;
    wire [XLEN-1:0] dec_imm;
    wire [4:0] dec_alu_op;
    wire dec_alu_src_imm;
    wire dec_reg_write;
    wire dec_mem_read;
    wire dec_mem_write;
    wire [1:0] dec_wb_sel;
    wire dec_branch;
    wire dec_jump;
    wire dec_jalr;
    wire dec_csr_instr;
    wire dec_m_ext;
    wire dec_word_op;

    wire [XLEN-1:0] rf_rs1_data;
    wire [XLEN-1:0] rf_rs2_data;
    wire [XLEN-1:0] rf_rs1_raw_data;
    wire [XLEN-1:0] rf_rs2_raw_data;
    wire [31:0] prefetch_pc;
    wire [31:0] prefetch_instr;
    wire prefetch_pred_taken;
    wire [31:0] prefetch_pred_target;
    wire prefetch_valid;
    wire [4:0] prefetch_rs1 = prefetch_instr[19:15];
    wire prefetch_mem_read = (prefetch_instr[6:0] == `OPCODE_LOAD);
    wire [XLEN-1:0] prefetch_load_imm = {{(XLEN-12){prefetch_instr[31]}}, prefetch_instr[31:20]};
    wire [XLEN-1:0] rf_prefetch_rs1_data;
    wire [XLEN-1:0] wb_data = (mem_wb_wb_sel == 2'd1) ? mem_wb_mem_data :
                          (mem_wb_wb_sel == 2'd2) ? mem_wb_pc4 :
                          mem_wb_alu_result;
    wire mem_wb_retire_valid = mem_wb_valid && !replay_flush;
    wire mem_wb_write_en = mem_wb_retire_valid && mem_wb_reg_write;
    wire [XLEN-1:0] load_resp_mem_data = format_load_data(load_resp_funct3, dmem_rdata);
    wire [XLEN-1:0] load_resp_data = load_resp_early_valid ? load_resp_early_data :
                                     load_resp_mem_data;
    (* keep = "true" *) wire [XLEN-1:0] load_resp_forward_mem_data =
                                      format_load_data(load_resp_funct3, dmem_rdata);
    (* keep = "true" *) wire [XLEN-1:0] load_resp_forward_data =
                                      load_resp_early_valid ? load_resp_early_data :
                                      load_resp_forward_mem_data;
    wire [XLEN-1:0] id_ex_early_load_data = format_load_data(id_ex_funct3, dmem_rdata);
    wire load_resp_retire_valid = load_resp_valid && !replay_flush;
    wire load_wb_write_en = load_resp_retire_valid && load_resp_reg_write;
    wire mul_busy;
    wire mul_early_valid;
    wire [XLEN-1:0] mul_early_result;
    wire mul_valid;
    wire [XLEN-1:0] mul_result;
    wire mul_complete_valid;
    wire mul_resp_ready_valid;
    wire [4:0] mul_resp_ready_rd;
    wire [XLEN-1:0] mul_resp_ready_data;
    wire mul_resp_ready_reg_write;
    wire mul_retire_valid;
    wire mul_resp_write_en;
    wire shared_wb2_is_load = load_wb_write_en;
    wire shared_wb2_we = load_wb_write_en || mul_resp_write_en;
    wire [4:0] shared_wb2_rd = shared_wb2_is_load ? load_resp_rd : mul_resp_ready_rd;
    wire [XLEN-1:0] shared_wb2_data = shared_wb2_is_load ? load_resp_data : mul_resp_ready_data;
    wire if_id_rs1_raw_mem_wb_update = (dec_rs1 != 5'd0) &&
                                        mem_wb_write_en &&
                                        (mem_wb_rd == dec_rs1);
    wire if_id_rs1_raw_shared_wb_update = (dec_rs1 != 5'd0) &&
                                           shared_wb2_we &&
                                           (shared_wb2_rd == dec_rs1);
    wire [XLEN-1:0] if_id_rs1_raw_hold_data = if_id_rs1_raw_mem_wb_update ? wb_data :
                                           if_id_rs1_raw_shared_wb_update ? shared_wb2_data :
                                           if_id_rs1_raw_data_q;
    wire [1:0] retire_count = {1'b0, mem_wb_retire_valid} +
                               {1'b0, load_resp_retire_valid} +
                               {1'b0, mul_retire_valid};
    wire retire_valid = |retire_count;

    decoder #(.XLEN(XLEN)) u_decoder (
        .instr(if_id_instr),
        .opcode(dec_opcode),
        .rd(dec_rd),
        .funct3(dec_funct3),
        .rs1(dec_rs1),
        .rs2(dec_rs2),
        .funct7(dec_funct7),
        .imm(dec_imm),
        .alu_op(dec_alu_op),
        .alu_src_imm(dec_alu_src_imm),
        .reg_write(dec_reg_write),
        .mem_read(dec_mem_read),
        .mem_write(dec_mem_write),
        .wb_sel(dec_wb_sel),
        .branch(dec_branch),
        .jump(dec_jump),
        .jalr(dec_jalr),
        .csr_instr(dec_csr_instr),
        .m_ext(dec_m_ext),
        .word_op(dec_word_op)
    );

    wire [XLEN-1:0] csr_mcycle;
    wire [XLEN-1:0] csr_minstret;
    reg [XLEN-1:0] csr_rdata;

    csr_unit #(
        .XLEN(XLEN),
        .HART_ID(0)
    ) u_csr (
        .clk(clk),
        .rst(rst),
        .retire_i(retire_valid),
        .retire_count_i(retire_count),
        .mcycle_o(csr_mcycle),
        .minstret_o(csr_minstret)
    );

    always @(*) begin
        case (id_ex_csr_addr)
            12'hB00: csr_rdata = csr_mcycle;
            12'hB02: csr_rdata = csr_minstret;
            default: csr_rdata = {XLEN{1'b0}};
        endcase
    end

    regfile #(.XLEN(XLEN)) u_regfile (
        .clk(clk),
        .rst(rst),
        .we(mem_wb_write_en),
        .waddr(mem_wb_rd),
        .wdata(wb_data),
        .we2(shared_wb2_we),
        .waddr2(shared_wb2_rd),
        .wdata2(shared_wb2_data),
        .raddr1(dec_rs1),
        .rraw1(rf_rs1_raw_data),
        .rdata1(rf_rs1_data),
        .raddr2(dec_rs2),
        .rraw2(rf_rs2_raw_data),
        .rdata2(rf_rs2_data),
        .raddr3(prefetch_rs1),
        .rdata3(rf_prefetch_rs1_data)
    );

    wire hazard_stall;
    wire [1:0] forward_a_sel;
    wire [1:0] forward_b_sel;
    wire if_id_is_mul = if_id_valid && dec_m_ext && !dec_funct3[2];
    wire id_ex_is_mul = id_ex_valid && id_ex_m_ext && !id_ex_funct3[2];
    wire dec_uses_rs1 = (dec_opcode == `OPCODE_JALR) ||
                        (dec_opcode == `OPCODE_BRANCH) ||
                        (dec_opcode == `OPCODE_LOAD) ||
                        (dec_opcode == `OPCODE_STORE) ||
                        (dec_opcode == `OPCODE_OP_IMM) ||
                        (dec_opcode == `OPCODE_OP_IMM_32) ||
                        (dec_opcode == `OPCODE_OP) ||
                        (dec_opcode == `OPCODE_OP_32) ||
                        ((dec_opcode == `OPCODE_SYSTEM) &&
                         (dec_funct3 != 3'b000) &&
                         !dec_funct3[2]);
    wire dec_uses_rs2 = (dec_opcode == `OPCODE_BRANCH) ||
                        (dec_opcode == `OPCODE_STORE) ||
                        (dec_opcode == `OPCODE_OP) ||
                        (dec_opcode == `OPCODE_OP_32);
    wire [4:0] dec_hazard_rs1 = dec_uses_rs1 ? dec_rs1 : 5'd0;
    wire [4:0] dec_hazard_rs2 = dec_uses_rs2 ? dec_rs2 : 5'd0;
    wire mul_fifo_empty = (mul_fifo_count == 4'd0);
    wire mul_fifo_full = (mul_fifo_count == MUL_FIFO_DEPTH_COUNT);
    wire [4:0] mul_complete_rd = mul_meta_rd_pipe[MUL_META_DEPTH-1];
    wire mul_complete_reg_write = mul_meta_reg_write_pipe[MUL_META_DEPTH-1];
    wire mul_complete_to_wb = mul_complete_valid && mul_fifo_empty;
    wire mul_issue_ready;
    wire mul_start;
    reg [4:0] mul_outstanding_count;
    reg if_id_rs1_mul_pending_dep_r;
    reg if_id_rs2_mul_pending_dep_r;
    reg if_id_mul_waw_dep_r;
    reg if_id_mul_order_dep_r;

    always @(*) begin
        mul_outstanding_count = {1'b0, mul_fifo_count};
        if_id_rs1_mul_pending_dep_r = 1'b0;
        if_id_rs2_mul_pending_dep_r = 1'b0;
        if_id_mul_waw_dep_r = 1'b0;
        if_id_mul_order_dep_r = 1'b0;

        for (mul_comb_i = 0; mul_comb_i < MUL_META_DEPTH; mul_comb_i = mul_comb_i + 1) begin
            if (mul_meta_valid_pipe[mul_comb_i]) begin
                mul_outstanding_count = mul_outstanding_count + 5'd1;
                if (!((mul_comb_i == (MUL_META_DEPTH - 1)) && mul_complete_to_wb && mul_retire_valid)) begin
                    if (mul_meta_rd_pipe[mul_comb_i] != 5'd0) begin
                        if (!((!dec_branch && !dec_jump) &&
                              ((mul_comb_i == MUL_FORWARD_STAGE) ||
                               ((MUL_STAGES == 1) && (mul_comb_i == 0)))) &&
                            (mul_meta_rd_pipe[mul_comb_i] == dec_hazard_rs1)) begin
                            if_id_rs1_mul_pending_dep_r = 1'b1;
                        end
                        if (!((!dec_branch && !dec_jump) &&
                              ((mul_comb_i == MUL_FORWARD_STAGE) ||
                               ((MUL_STAGES == 1) && (mul_comb_i == 0)))) &&
                            (mul_meta_rd_pipe[mul_comb_i] == dec_hazard_rs2)) begin
                            if_id_rs2_mul_pending_dep_r = 1'b1;
                        end
                        if (if_id_valid && dec_reg_write && (mul_meta_rd_pipe[mul_comb_i] == dec_rd)) begin
                            if_id_mul_waw_dep_r = 1'b1;
                        end
                    end
                    if_id_mul_order_dep_r = if_id_mul_order_dep_r || (if_id_valid && dec_csr_instr);
                end
            end
        end

        for (mul_comb_i = 0; mul_comb_i < MUL_FIFO_DEPTH; mul_comb_i = mul_comb_i + 1) begin
            if (mul_fifo_valid[mul_comb_i] && !((mul_comb_i[2:0] == mul_fifo_head) && mul_retire_valid)) begin
                if (mul_fifo_rd[mul_comb_i] != 5'd0) begin
                    if (mul_fifo_rd[mul_comb_i] == dec_hazard_rs1) begin
                        if_id_rs1_mul_pending_dep_r = 1'b1;
                    end
                    if (mul_fifo_rd[mul_comb_i] == dec_hazard_rs2) begin
                        if_id_rs2_mul_pending_dep_r = 1'b1;
                    end
                    if (if_id_valid && dec_reg_write && (mul_fifo_rd[mul_comb_i] == dec_rd)) begin
                        if_id_mul_waw_dep_r = 1'b1;
                    end
                end
                if_id_mul_order_dep_r = if_id_mul_order_dep_r || (if_id_valid && dec_csr_instr);
            end
        end

        if (mul_start) begin
            if (id_ex_rd != 5'd0) begin
                if (id_ex_rd == dec_hazard_rs1) begin
                    if_id_rs1_mul_pending_dep_r = 1'b1;
                end
                if (id_ex_rd == dec_hazard_rs2) begin
                    if_id_rs2_mul_pending_dep_r = 1'b1;
                end
                if (if_id_valid && dec_reg_write && (id_ex_rd == dec_rd)) begin
                    if_id_mul_waw_dep_r = 1'b1;
                end
            end
            if_id_mul_order_dep_r = if_id_mul_order_dep_r || (if_id_valid && dec_csr_instr);
        end
    end

    assign mul_issue_ready = (mul_outstanding_count < MUL_FIFO_DEPTH_EXT) || mul_retire_valid;
    assign mul_start = (FAST_MUL == 0) && id_ex_is_mul &&
                       mul_issue_ready && !redirect_valid;
    wire mul_decode_pipeline_busy = (FAST_MUL == 0) &&
                                    ((mul_outstanding_count + (mul_start ? 5'd1 : 5'd0)) >= MUL_FIFO_DEPTH_EXT);
    wire if_id_control_load_replay = dec_branch || (dec_jump && dec_jalr);
    wire if_id_control_load_early_rs1_dep = if_id_valid &&
                                            id_ex_valid &&
                                            id_ex_mem_read &&
                                            (id_ex_rd != 5'd0) &&
                                            (id_ex_rd == dec_hazard_rs1);
    wire if_id_control_load_early_rs2_dep = if_id_valid &&
                                            dec_branch &&
                                            id_ex_valid &&
                                            id_ex_mem_read &&
                                            (id_ex_rd != 5'd0) &&
                                            (id_ex_rd == dec_hazard_rs2);
    wire if_id_control_load_early_dep = if_id_control_load_replay &&
                                        (if_id_control_load_early_rs1_dep ||
                                         if_id_control_load_early_rs2_dep);
    wire if_id_rs1_ex_mem_dep = (dec_hazard_rs1 != 5'd0) &&
                                ex_mem_valid &&
                                ex_mem_reg_write &&
                                (ex_mem_rd == dec_hazard_rs1);
    wire if_id_rs2_ex_mem_dep = (dec_hazard_rs2 != 5'd0) &&
                                ex_mem_valid &&
                                ex_mem_reg_write &&
                                (ex_mem_rd == dec_hazard_rs2);
    wire if_id_rs1_mul_pending_dep = (FAST_MUL == 0) &&
                                     if_id_rs1_mul_pending_dep_r;
    wire if_id_rs2_mul_pending_dep = (FAST_MUL == 0) &&
                                     if_id_rs2_mul_pending_dep_r;
    wire if_id_load_base_id_ex_dep = if_id_load_rs1_nonzero_q &&
                                     id_ex_valid &&
                                     id_ex_reg_write &&
                                     (id_ex_rd == if_id_load_rs1_q);
    wire if_id_load_base_id_ex_early_dep = if_id_load_base_id_ex_dep &&
                                           id_ex_mem_read &&
                                           id_ex_load_early_valid;
    wire if_id_load_base_ex_mem_dep = if_id_load_rs1_nonzero_q &&
                                      ex_mem_valid &&
                                      ex_mem_reg_write &&
                                      (ex_mem_rd == if_id_load_rs1_q);
    wire if_id_load_base_ex_mem_early_dep = if_id_load_base_ex_mem_dep &&
                                            ex_mem_mem_read &&
                                            ex_mem_load_early_valid;
    wire if_id_load_base_inflight_dep = if_id_load_base_id_ex_dep ||
                                        (if_id_load_base_ex_mem_dep &&
                                         !if_id_load_base_ex_mem_early_dep);
    wire if_id_load_base_load_resp_dep = if_id_load_rs1_nonzero_q &&
                                         load_wb_write_en &&
                                         (load_resp_rd == if_id_load_rs1_q);
    wire if_id_load_base_mem_wb_dep = if_id_load_rs1_nonzero_q &&
                                      mem_wb_write_en &&
                                      (mem_wb_rd == if_id_load_rs1_q);
    wire if_id_load_base_mul_resp_dep = if_id_load_rs1_nonzero_q &&
                                        mul_resp_write_en &&
                                        (mul_resp_ready_rd == if_id_load_rs1_q);
    wire ex_mem_dmem_port_busy = ex_mem_valid &&
                                 ((ex_mem_mem_read && !ex_mem_load_early_valid) ||
                                  ex_mem_mem_write);
    wire dmem_port_busy = (id_ex_valid && (id_ex_mem_read || id_ex_mem_write)) ||
                          ex_mem_dmem_port_busy;
    wire if_id_control_load_early_other_rs1_dep = !if_id_control_load_early_rs1_dep &&
                                                  (if_id_rs1_ex_mem_dep ||
                                                   if_id_rs1_mul_pending_dep);
    wire if_id_control_load_early_other_rs2_dep = dec_branch &&
                                                  !if_id_control_load_early_rs2_dep &&
                                                  (if_id_rs2_ex_mem_dep ||
                                                   if_id_rs2_mul_pending_dep);
    wire if_id_control_load_early_replay = (ENABLE_LOAD_CONTROL_EARLY_REPLAY != 0) &&
                                           if_id_control_load_early_dep &&
                                           !if_id_control_load_early_other_rs1_dep &&
                                           !if_id_control_load_early_other_rs2_dep &&
                                           !ctrl_load_pending_valid &&
                                           !ctrl_replay_valid &&
                                           !redirect_valid;

    hazard_unit #(
        .ENABLE_LOAD_USE_STALL(ENABLE_LOAD_USE_STALL),
        .ENABLE_LOAD_RESP_EX_FORWARD(ENABLE_LOAD_RESP_EX_FORWARD),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(ENABLE_LOAD_CONTROL_EARLY_REPLAY),
        .ENABLE_ID_LOAD_EARLY_READ(ENABLE_ID_LOAD_EARLY_READ)
    ) u_hazard (
        .id_ex_mem_read(id_ex_valid && id_ex_mem_read),
        .id_ex_load_early_valid(id_ex_load_early_valid),
        .id_ex_rd(id_ex_rd),
        .if_id_rs1(dec_hazard_rs1),
        .if_id_rs2(dec_hazard_rs2),
        .if_id_reg_write(if_id_valid && dec_reg_write),
        .if_id_rd(dec_rd),
        .if_id_csr_instr(if_id_valid && dec_csr_instr),
        .if_id_is_mul(if_id_is_mul),
        .if_id_conservative_load_use(dec_m_ext && (FAST_MUL != 0)),
        .if_id_control_load_replay(if_id_control_load_replay),
        .if_id_control_load_early_replay(if_id_control_load_early_replay),
        .if_id_mul_src_dep_i(if_id_rs1_mul_pending_dep || if_id_rs2_mul_pending_dep),
        .if_id_mul_waw_dep_i((FAST_MUL == 0) && if_id_mul_waw_dep_r),
        .if_id_mul_order_dep_i((FAST_MUL == 0) && if_id_mul_order_dep_r),
        .if_id_mul_struct_dep_i(mul_decode_pipeline_busy && if_id_is_mul),
        .ex_mem_reg_write(ex_mem_valid && ex_mem_reg_write &&
                          !((ENABLE_LOAD_USE_STALL != 0) &&
                            ex_mem_mem_read &&
                            !ex_mem_load_early_valid)),
        .ex_mem_mem_read(ex_mem_valid && ex_mem_mem_read),
        .ex_mem_rd(ex_mem_rd),
        .mem_wb_reg_write(mem_wb_write_en),
        .mem_wb_rd(mem_wb_rd),
        .load_resp_reg_write(load_wb_write_en),
        .load_resp_rd(load_resp_rd),
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .stall(hazard_stall),
        .forward_a(forward_a_sel),
        .forward_b(forward_b_sel)
    );

    wire [XLEN-1:0] mem_load_data = format_load_data(ex_mem_funct3, dmem_rdata);
    wire [XLEN-1:0] alu_y;
    wire [XLEN-1:0] ex_result;
    wire [XLEN-1:0] ex_mem_forward_data = (ex_mem_mem_read && ex_mem_load_early_valid) ? ex_mem_load_early_data :
                                      ((ENABLE_LOAD_USE_STALL == 0) && ex_mem_mem_read) ? mem_load_data :
                                      ex_mem_alu_result;
    wire if_id_m_ext_load_resp_dep = if_id_valid &&
                                     dec_m_ext &&
                                     load_wb_write_en &&
                                     (load_resp_rd != 5'd0) &&
                                     ((load_resp_rd == dec_hazard_rs1) ||
                                      (load_resp_rd == dec_hazard_rs2));
    wire m_ext_load_resp_forward_en = (FAST_MUL == 0);
    wire ex_load_resp_forward_en = (ENABLE_LOAD_RESP_EX_FORWARD != 0) &&
                                   (!id_ex_m_ext || m_ext_load_resp_forward_en);
    wire mul_complete_forward_valid = (FAST_MUL == 0) &&
                                      mul_complete_valid &&
                                      mul_complete_reg_write &&
                                      (mul_complete_rd != 5'd0);
    wire mul_early_forward_valid = (FAST_MUL == 0) &&
                                   (MUL_STAGES == 1) &&
                                   mul_early_valid &&
                                   mul_meta_valid_pipe[1] &&
                                   mul_meta_reg_write_pipe[1] &&
                                   (mul_meta_rd_pipe[1] != 5'd0);
    wire [4:0] mul_early_forward_rd = mul_meta_rd_pipe[1];
    wire mul_early_forward_a = mul_early_forward_valid &&
                               (mul_early_forward_rd == id_ex_rs1);
    wire mul_early_forward_b = mul_early_forward_valid &&
                               (mul_early_forward_rd == id_ex_rs2);
    wire mul_complete_forward_a = mul_complete_forward_valid &&
                                  (mul_complete_rd == id_ex_rs1);
    wire mul_complete_forward_b = mul_complete_forward_valid &&
                                  (mul_complete_rd == id_ex_rs2);
    wire [XLEN-1:0] replay_forward_a_data = (forward_a_sel == 2'd1) ? ex_mem_forward_data :
                                        (forward_a_sel == 2'd2) ? wb_data :
                                        (forward_a_sel == 2'd3) ? load_resp_forward_data :
                                        id_ex_rs1_data;
    wire [XLEN-1:0] replay_forward_b_data = (forward_b_sel == 2'd1) ? ex_mem_forward_data :
                                        (forward_b_sel == 2'd2) ? wb_data :
                                        (forward_b_sel == 2'd3) ? load_resp_forward_data :
                                        id_ex_rs2_data;
    wire [XLEN-1:0] forward_a_data = (forward_a_sel == 2'd1) ? ex_mem_forward_data :
                                 (forward_a_sel == 2'd2) ? wb_data :
                                 ((forward_a_sel == 2'd3) && ex_load_resp_forward_en) ? load_resp_forward_data :
                                 mul_early_forward_a ? mul_early_result :
                                 mul_complete_forward_a ? mul_result :
                                 id_ex_rs1_data;
    wire [XLEN-1:0] forward_b_data = (forward_b_sel == 2'd1) ? ex_mem_forward_data :
                                 (forward_b_sel == 2'd2) ? wb_data :
                                 ((forward_b_sel == 2'd3) && ex_load_resp_forward_en) ? load_resp_forward_data :
                                 mul_early_forward_b ? mul_early_result :
                                 mul_complete_forward_b ? mul_result :
                                 id_ex_rs2_data;
    wire [XLEN-1:0] m_ext_forward_a_raw = (forward_a_sel == 2'd1) ? ex_mem_forward_data :
                                       (forward_a_sel == 2'd2) ? wb_data :
                                       ((forward_a_sel == 2'd3) && m_ext_load_resp_forward_en) ? load_resp_forward_data :
                                       mul_early_forward_a ? mul_early_result :
                                       mul_complete_forward_a ? mul_result :
                                       id_ex_rs1_data;
    wire [XLEN-1:0] m_ext_forward_b_raw = (forward_b_sel == 2'd1) ? ex_mem_forward_data :
                                       (forward_b_sel == 2'd2) ? wb_data :
                                       ((forward_b_sel == 2'd3) && m_ext_load_resp_forward_en) ? load_resp_forward_data :
                                       mul_early_forward_b ? mul_early_result :
                                       mul_complete_forward_b ? mul_result :
                                       id_ex_rs2_data;
    wire [XLEN-1:0] m_ext_forward_a_data = id_ex_word_op ? sign_extend_word(m_ext_forward_a_raw[31:0]) :
                                           m_ext_forward_a_raw;
    wire [XLEN-1:0] m_ext_forward_b_data = id_ex_word_op ? sign_extend_word(m_ext_forward_b_raw[31:0]) :
                                           m_ext_forward_b_raw;
    wire [XLEN-1:0] alu_b = id_ex_alu_src_imm ? id_ex_imm : forward_b_data;
    wire control_load_resp_forward_en = (ENABLE_LOAD_RESP_EX_FORWARD != 0);
    wire [XLEN-1:0] control_forward_a_data = (forward_a_sel == 2'd1) ? ex_mem_forward_data :
                                         (forward_a_sel == 2'd2) ? wb_data :
                                         ((forward_a_sel == 2'd3) && control_load_resp_forward_en) ? load_resp_forward_data :
                                         id_ex_rs1_data;
    wire [XLEN-1:0] control_forward_b_data = (forward_b_sel == 2'd1) ? ex_mem_forward_data :
                                         (forward_b_sel == 2'd2) ? wb_data :
                                         ((forward_b_sel == 2'd3) && control_load_resp_forward_en) ? load_resp_forward_data :
                                         id_ex_rs2_data;
    alu #(.XLEN(XLEN)) u_alu (
        .a(forward_a_data),
        .b(alu_b),
        .op(id_ex_alu_op),
        .word_op(id_ex_word_op),
        .y(alu_y)
    );

    wire mul_wait = (FAST_MUL == 0) && id_ex_is_mul && !mul_start;
    assign mul_complete_valid = (FAST_MUL == 0) &&
                                mul_valid &&
                                mul_meta_valid_pipe[MUL_META_DEPTH-1];
    assign mul_resp_ready_valid = !mul_fifo_empty || mul_complete_valid;
    assign mul_resp_ready_rd = !mul_fifo_empty ? mul_fifo_rd[mul_fifo_head] : mul_complete_rd;
    assign mul_resp_ready_data = !mul_fifo_empty ? mul_fifo_data[mul_fifo_head] : mul_result;
    assign mul_resp_ready_reg_write = !mul_fifo_empty ? mul_fifo_reg_write[mul_fifo_head] :
                                      mul_complete_reg_write;
    assign mul_retire_valid = mul_resp_ready_valid && !load_wb_write_en;
    assign mul_resp_write_en = mul_retire_valid &&
                               mul_resp_ready_reg_write &&
                               (mul_resp_ready_rd != 5'd0);
    wire mul_complete_bypass = mul_complete_valid && mul_fifo_empty && mul_retire_valid;
    wire mul_fifo_pop = mul_retire_valid && !mul_fifo_empty;
    wire mul_fifo_push = mul_complete_valid && !mul_complete_bypass;
    wire id_ex_is_div = id_ex_valid && id_ex_m_ext && id_ex_funct3[2];
    wire div_busy;
    wire div_valid;
    wire [XLEN-1:0] div_result;
    wire div_launch = id_ex_is_div && !div_cmd_valid && !div_busy && !div_valid;
    wire div_start = div_cmd_valid && !div_busy && !div_valid;
    wire div_wait = id_ex_is_div && !div_valid;
    wire exec_wait = mul_wait || div_wait;

    multiplier #(
        .XLEN(XLEN),
        .MUL_STAGES(MUL_STAGES)
    ) u_multiplier (
        .clk(clk),
        .rst(rst),
        .start_i(mul_start),
        .funct3_i(id_ex_funct3),
        .a_i(m_ext_forward_a_data),
        .b_i(m_ext_forward_b_data),
        .busy_o(mul_busy),
        .early_valid_o(mul_early_valid),
        .early_result_o(mul_early_result),
        .valid_o(mul_valid),
        .result_o(mul_result)
    );

    divider #(.XLEN(XLEN)) u_divider (
        .clk(clk),
        .rst(rst),
        .start_i(div_start),
        .signed_i((div_cmd_funct3 == 3'b100) || (div_cmd_funct3 == 3'b110)),
        .rem_i(div_cmd_funct3[1]),
        .dividend_i(div_cmd_rs1_data),
        .divisor_i(div_cmd_rs2_data),
        .busy_o(div_busy),
        .valid_o(div_valid),
        .result_o(div_result)
    );

    wire [XLEN-1:0] fast_mul_result;
    generate
        if (FAST_MUL != 0) begin : gen_fast_mul_result
            wire signed [(2*XLEN)-1:0] fast_mul_product_ss = $signed(m_ext_forward_a_data) * $signed(m_ext_forward_b_data);
            wire [(2*XLEN)-1:0] fast_mul_product_uu = m_ext_forward_a_data * m_ext_forward_b_data;
            wire signed [(2*XLEN):0] fast_mul_product_su = $signed({m_ext_forward_a_data[XLEN-1], m_ext_forward_a_data}) *
                                                           $signed({1'b0, m_ext_forward_b_data});
            assign fast_mul_result = id_ex_word_op ? sign_extend_word(fast_mul_product_ss[31:0]) :
                                     (id_ex_funct3 == 3'b000) ? fast_mul_product_ss[XLEN-1:0] :
                                     (id_ex_funct3 == 3'b001) ? fast_mul_product_ss[(2*XLEN)-1:XLEN] :
                                     (id_ex_funct3 == 3'b010) ? fast_mul_product_su[(2*XLEN)-1:XLEN] :
                                     (id_ex_funct3 == 3'b011) ? fast_mul_product_uu[(2*XLEN)-1:XLEN] :
                                     {XLEN{1'b0}};
        end else begin : gen_no_fast_mul_result
            assign fast_mul_result = {XLEN{1'b0}};
        end
    endgenerate

    wire [XLEN-1:0] m_raw_result = (!id_ex_funct3[2]) ? ((FAST_MUL != 0) ? fast_mul_result : mul_result) :
                                   (id_ex_funct3[2]) ? div_result :
                                   alu_y;
    wire [XLEN-1:0] m_result = id_ex_word_op ? sign_extend_word(m_raw_result[31:0]) : m_raw_result;

    wire mem_wait = 1'b0;
    wire pipe_wait = exec_wait || mem_wait;
    wire load_control_early_capture = if_id_control_load_early_replay &&
                                      !pipe_wait &&
                                      !redirect_valid;
    wire ctrl_load_pending_to_replay = ctrl_load_pending_valid &&
                                       !ctrl_load_pending_wait_resp &&
                                       load_resp_valid &&
                                       (load_resp_rd == ctrl_load_pending_load_rd) &&
                                       !ctrl_replay_valid;
    wire control_load_resp_dep = id_ex_valid &&
                                 (id_ex_branch || (id_ex_jump && id_ex_jalr)) &&
                                 !control_load_resp_forward_en &&
                                 ((forward_a_sel == 2'd3) ||
                                  (id_ex_branch && (forward_b_sel == 2'd3)));
    wire control_replay_capture = control_load_resp_dep && !pipe_wait && !redirect_valid;
    wire ctrl_valid = ctrl_replay_valid || (id_ex_valid && !control_load_resp_dep);
    wire ctrl_branch = ctrl_replay_valid ? ctrl_replay_branch : id_ex_branch;
    wire ctrl_jump = ctrl_replay_valid ? ctrl_replay_jump : id_ex_jump;
    wire ctrl_jalr = ctrl_replay_valid ? ctrl_replay_jalr : id_ex_jalr;
    wire ctrl_jump_early_redirect = ctrl_replay_valid ? 1'b0 : id_ex_jump_early_redirect;
    wire [31:0] ctrl_pc = ctrl_replay_valid ? ctrl_replay_pc : id_ex_pc;
    wire [XLEN-1:0] ctrl_imm = ctrl_replay_valid ? ctrl_replay_imm : id_ex_imm;
    wire [2:0] ctrl_funct3 = ctrl_replay_valid ? ctrl_replay_funct3 : id_ex_funct3;
    wire ctrl_pred_taken = ctrl_replay_valid ? ctrl_replay_pred_taken : id_ex_pred_taken;
    wire [31:0] ctrl_pred_target = ctrl_replay_valid ? ctrl_replay_pred_target : id_ex_pred_target;
    wire [XLEN-1:0] ctrl_normal_rs1_data = control_load_resp_dep ? {XLEN{1'b0}} : control_forward_a_data;
    wire [XLEN-1:0] ctrl_normal_rs2_data = control_load_resp_dep ? {XLEN{1'b0}} : control_forward_b_data;
    wire [XLEN-1:0] ctrl_rs1_data = ctrl_replay_valid ? ctrl_replay_rs1_data : ctrl_normal_rs1_data;
    wire [XLEN-1:0] ctrl_rs2_data = ctrl_replay_valid ? ctrl_replay_rs2_data : ctrl_normal_rs2_data;

    reg branch_taken;
    always @(*) begin
        case (ctrl_funct3)
            3'b000: branch_taken = (ctrl_rs1_data == ctrl_rs2_data);
            3'b001: branch_taken = (ctrl_rs1_data != ctrl_rs2_data);
            3'b100: branch_taken = ($signed(ctrl_rs1_data) < $signed(ctrl_rs2_data));
            3'b101: branch_taken = ($signed(ctrl_rs1_data) >= $signed(ctrl_rs2_data));
            3'b110: branch_taken = (ctrl_rs1_data < ctrl_rs2_data);
            3'b111: branch_taken = (ctrl_rs1_data >= ctrl_rs2_data);
            default: branch_taken = 1'b0;
        endcase
    end

    wire take_branch = ctrl_valid && ctrl_branch && branch_taken;
    wire take_jump = ctrl_valid && ctrl_jump;
    wire [31:0] branch_target = ctrl_pc + ctrl_imm[31:0];
    wire [31:0] jalr_target = (ctrl_rs1_data[31:0] + ctrl_imm[31:0]) & 32'hffff_fffe;
    wire [31:0] redirect_target_pc = ctrl_jalr ? jalr_target : branch_target;
    wire [31:0] redirect_fallthrough_pc = ctrl_pc + 32'd4;
    wire [31:0] redirect_pc = redirect_jump_flush ? redirect_pc_q :
                                redirect_taken_q ? redirect_pc_q :
                                redirect_fallthrough_pc_q;
    wire ctrl_branch_target_mismatch = branch_target != ctrl_pred_target;
    wire jump_target_mismatch = redirect_target_pc != ctrl_pred_target;
    wire branch_mispredict_raw = ctrl_valid && ctrl_branch &&
                                 (branch_taken ? (!ctrl_pred_taken || ctrl_branch_target_mismatch) :
                                                 ctrl_pred_taken);
    wire jump_needs_flush_raw = take_jump &&
                                (ctrl_jalr ? (!ctrl_jump_early_redirect || jump_target_mismatch) :
                                             !ctrl_jump_early_redirect);
    wire branch_mispredict_detect = !redirect_valid && !pipe_wait && branch_mispredict_raw;
    wire jump_needs_flush_detect = !redirect_valid && !pipe_wait && jump_needs_flush_raw;
    wire redirect_detect = branch_mispredict_detect || jump_needs_flush_detect;
    wire redirect_candidate_valid = !redirect_valid && !pipe_wait && ctrl_valid && (ctrl_branch || ctrl_jump);
    wire branch_mispredict = redirect_valid && redirect_branch_mispredict;
    wire jump_needs_flush = redirect_valid && redirect_jump_flush;
    wire flush = branch_mispredict || jump_needs_flush;
    assign replay_flush = flush && redirect_from_replay;
    wire id_load_early_base_wait = if_id_valid &&
                                   if_id_mem_read_q &&
                                   if_id_load_base_id_ex_early_dep &&
                                   !redirect_valid;
    wire control_conflict_stall = ctrl_replay_valid && id_ex_valid && (id_ex_branch || id_ex_jump);
    wire ctrl_pending_conflict_stall = ctrl_load_pending_valid &&
                                       if_id_valid &&
                                       (dec_mem_write ||
                                        dec_csr_instr ||
                                        dec_m_ext ||
                                        dec_branch ||
                                        dec_jump);
    wire fetch_stall = pipe_wait || hazard_stall || id_load_early_base_wait ||
                       control_conflict_stall ||
                       ctrl_pending_conflict_stall;
    wire predict_taken;
    wire [31:0] predict_target;
    wire [31:0] predicted_next_pc = predict_taken ? predict_target : (pc + 32'd4);
    wire [31:0] id_jal_target = if_id_pc + dec_imm[31:0];
    wire id_jal_predicted_hit = if_id_valid && dec_jump && !dec_jalr &&
                                if_id_pred_taken &&
                                (if_id_pred_target == id_jal_target);
    wire ras_valid = ras_count != 4'd0;
    wire [2:0] ras_top_index = ras_count[2:0] - 3'd1;
    wire [31:0] ras_top_target = ras_stack[ras_top_index];
    wire dec_call = dec_jump && !dec_jalr &&
                    ((dec_rd == 5'd1) || (dec_rd == 5'd5));
    wire dec_return = dec_jump && dec_jalr &&
                      (dec_rd == 5'd0) &&
                      ((dec_rs1 == 5'd1) || (dec_rs1 == 5'd5)) &&
                      (dec_imm == 32'h00000000);
    wire id_jal_redirect = if_id_valid && dec_jump && !dec_jalr &&
                           !pipe_wait &&
                           !hazard_stall &&
                           !control_conflict_stall &&
                           !ctrl_pending_conflict_stall &&
                           !ctrl_load_pending_valid &&
                           !ctrl_replay_valid &&
                           !id_jal_predicted_hit &&
                           !flush;
    wire id_jalr_ras_redirect = if_id_valid && dec_return && ras_valid &&
                                !pipe_wait &&
                                !hazard_stall &&
                                !control_conflict_stall &&
                                !ctrl_pending_conflict_stall &&
                                !ctrl_load_pending_valid &&
                                !ctrl_replay_valid &&
                                !flush;
    wire id_jump_resolved_in_id = id_jal_redirect || id_jal_predicted_hit ||
                                  id_jalr_ras_redirect;
    wire frontend_flush = flush || id_jal_redirect || id_jalr_ras_redirect;
    wire id_stage_accept = if_id_valid &&
                           !flush &&
                           !pipe_wait &&
                           !load_control_early_capture &&
                           !hazard_stall &&
                           !id_load_early_base_wait &&
                           !control_conflict_stall &&
                           !ctrl_pending_conflict_stall &&
                           !ctrl_load_pending_valid &&
                           !ctrl_replay_valid;
    wire ras_push = id_stage_accept && dec_call;
    wire ras_pop = id_jalr_ras_redirect;
    wire id_load_early_read = (ENABLE_ID_LOAD_EARLY_READ != 0) &&
                              if_id_valid &&
                              if_id_mem_read_q &&
                              !if_id_load_base_inflight_dep &&
                              !if_id_load_base_load_resp_dep &&
                              !if_id_load_base_mem_wb_dep &&
                              !if_id_load_base_mul_resp_dep &&
                              !if_id_load_base_mul_pending_dep_q &&
                              !dmem_port_busy &&
                              !ctrl_load_pending_valid;
    wire [XLEN-1:0] id_load_early_base_data = !if_id_load_rs1_nonzero_q ? {XLEN{1'b0}} :
                                          if_id_load_base_ex_mem_early_dep ? ex_mem_load_early_data :
                                          if_id_rs1_raw_data_q;
    wire [31:0] id_load_early_addr = id_load_early_base_data[31:0] + if_id_load_imm_q[31:0];

    wire bp_branch_update = ctrl_valid && ctrl_branch && !pipe_wait;
    wire bp_jal_update = id_jal_redirect && !bp_branch_update;
    wire bp_update = bp_branch_update || bp_jal_update;
    wire [31:0] bp_update_pc = bp_branch_update ? ctrl_pc : if_id_pc;
    wire bp_update_taken = bp_branch_update ? take_branch : 1'b1;
    wire [31:0] bp_update_target = bp_branch_update ? branch_target : id_jal_target;

    branch_predictor #(
        .BHT_DEPTH(BP_BHT_DEPTH),
        .BHR_WIDTH(BP_BHR_WIDTH),
        .BTB_DEPTH(BP_BTB_DEPTH),
        .LOCAL_HISTORY(BP_LOCAL_HISTORY),
        .INIT_TAKEN(BP_INIT_TAKEN)
    ) u_branch_predictor (
        .clk(clk),
        .rst(rst),
        .pc_i(pc),
        .predict_taken_o(predict_taken),
        .predict_target_o(predict_target),
        .update_i(bp_update),
        .update_uncond_i(bp_jal_update),
        .update_pc_i(bp_update_pc),
        .actual_taken_i(bp_update_taken),
        .actual_target_i(bp_update_target)
    );

    prefetch #(.DEPTH(4)) u_prefetch (
        .clk(clk),
        .rst(rst),
        .flush_i(frontend_flush),
        .stall_i(fetch_stall),
        .fetch_valid_i(fetch_valid_q),
        .fetch_pc_i(fetch_pc_q),
        .fetch_instr_i(imem_rdata),
        .fetch_pred_taken_i(fetch_pred_taken_q),
        .fetch_pred_target_i(fetch_pred_target_q),
        .pc_o(prefetch_pc),
        .instr_o(prefetch_instr),
        .pred_taken_o(prefetch_pred_taken),
        .pred_target_o(prefetch_pred_target),
        .valid_o(prefetch_valid)
    );

    assign ex_result = id_ex_csr_instr ? csr_rdata :
                       id_ex_m_ext ? m_result :
                       (id_ex_wb_sel == 2'd3) ? (id_ex_pc + id_ex_imm) :
                       alu_y;

    reg [(XLEN/8)-1:0] store_byte_en;
    reg [XLEN-1:0] store_wdata;

    always @(*) begin
        store_byte_en = {DMEM_BYTES{1'b0}};
        store_wdata = ex_mem_rs2_data;
        if (ex_mem_valid && ex_mem_mem_write) begin
            case (ex_mem_funct3)
                3'b000: begin
                    store_byte_en = {{(DMEM_BYTES-1){1'b0}}, 1'b1};
                    store_wdata = {{(XLEN-8){1'b0}}, ex_mem_rs2_data[7:0]};
                end
                3'b001: begin
                    store_byte_en = {{(DMEM_BYTES-2){1'b0}}, 2'b11};
                    store_wdata = {{(XLEN-16){1'b0}}, ex_mem_rs2_data[15:0]};
                end
                3'b010: begin
                    store_byte_en = {{(DMEM_BYTES-4){1'b0}}, 4'b1111};
                    store_wdata = zero_extend_word(ex_mem_rs2_data[31:0]);
                end
                default: begin
                    store_byte_en = {DMEM_BYTES{1'b1}};
                    store_wdata = ex_mem_rs2_data;
                end
            endcase
        end

        imem_addr = pc;
        dmem_read = (ex_mem_valid && ex_mem_mem_read && !ex_mem_load_early_valid) ||
                    id_load_early_read;
        dmem_read_early = id_load_early_read;
        dmem_write = ex_mem_valid && ex_mem_mem_write && !replay_flush;
        dmem_addr = ex_mem_dmem_port_busy ? ex_mem_alu_result[31:0] :
                    id_load_early_read ? id_load_early_addr : 32'h00000000;
        dmem_wdata = store_wdata;
        dmem_byte_en = store_byte_en;
    end

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'h00000000;
            fetch_pc_q <= 32'h00000000;
            fetch_valid_q <= 1'b0;
            fetch_pred_taken_q <= 1'b0;
            fetch_pred_target_q <= 32'h00000004;
            if_id_pc <= 32'h00000000;
            if_id_instr <= 32'h00000013;
            if_id_pred_taken <= 1'b0;
            if_id_pred_target <= 32'h00000004;
            if_id_valid <= 1'b0;
            if_id_mem_read_q <= 1'b0;
            if_id_load_rs1_q <= 5'd0;
            if_id_load_rs1_nonzero_q <= 1'b0;
            if_id_load_imm_q <= 32'h00000000;
            id_ex_valid <= 1'b0;
            id_ex_pc <= 32'h00000000;
            id_ex_imm <= 32'h00000000;
            id_ex_rs1_data <= 32'h00000000;
            id_ex_rs2_data <= 32'h00000000;
            id_ex_rs1 <= 5'd0;
            id_ex_rs2 <= 5'd0;
            id_ex_rd <= 5'd0;
            id_ex_funct3 <= 3'd0;
            id_ex_alu_op <= `ALU_ADD;
            id_ex_alu_src_imm <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_wb_sel <= 2'd0;
            id_ex_branch <= 1'b0;
            id_ex_jump <= 1'b0;
            id_ex_jalr <= 1'b0;
            id_ex_jump_early_redirect <= 1'b0;
            id_ex_csr_instr <= 1'b0;
            id_ex_csr_addr <= 12'h000;
            id_ex_m_ext <= 1'b0;
            id_ex_word_op <= 1'b0;
            id_ex_pred_taken <= 1'b0;
            id_ex_pred_target <= 32'h00000004;
            id_ex_load_early_valid <= 1'b0;
            ex_mem_valid <= 1'b0;
            ex_mem_alu_result <= 32'h00000000;
            ex_mem_rs2_data <= 32'h00000000;
            ex_mem_pc4 <= 32'h00000000;
            ex_mem_rd <= 5'd0;
            ex_mem_funct3 <= 3'd0;
            ex_mem_reg_write <= 1'b0;
            ex_mem_mem_read <= 1'b0;
            ex_mem_mem_write <= 1'b0;
            ex_mem_wb_sel <= 2'd0;
            ex_mem_load_early_valid <= 1'b0;
            ex_mem_load_early_data <= 32'h00000000;
            mem_wb_valid <= 1'b0;
            mem_wb_alu_result <= 32'h00000000;
            mem_wb_mem_data <= 32'h00000000;
            mem_wb_pc4 <= 32'h00000000;
            mem_wb_rd <= 5'd0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_wb_sel <= 2'd0;
            load_resp_valid <= 1'b0;
            load_resp_rd <= 5'd0;
            load_resp_funct3 <= 3'd0;
            load_resp_reg_write <= 1'b0;
            load_resp_early_valid <= 1'b0;
            load_resp_early_data <= 32'h00000000;
            mul_meta_valid_pipe <= {MUL_META_DEPTH{1'b0}};
            for (mul_seq_i = 0; mul_seq_i < MUL_META_DEPTH; mul_seq_i = mul_seq_i + 1) begin
                mul_meta_rd_pipe[mul_seq_i] <= 5'd0;
                mul_meta_reg_write_pipe[mul_seq_i] <= 1'b0;
            end
            mul_fifo_valid <= {MUL_FIFO_DEPTH{1'b0}};
            mul_fifo_head <= 3'd0;
            mul_fifo_tail <= 3'd0;
            mul_fifo_count <= 4'd0;
            for (mul_seq_i = 0; mul_seq_i < MUL_FIFO_DEPTH; mul_seq_i = mul_seq_i + 1) begin
                mul_fifo_rd[mul_seq_i] <= 5'd0;
                mul_fifo_data[mul_seq_i] <= 32'h00000000;
                mul_fifo_reg_write[mul_seq_i] <= 1'b0;
            end
            div_cmd_valid <= 1'b0;
            div_cmd_rs1_data <= 32'h00000000;
            div_cmd_rs2_data <= 32'h00000000;
            div_cmd_funct3 <= 3'd0;
            div_cmd_word_op <= 1'b0;
            if_id_load_base_mul_pending_dep_q <= 1'b0;
            if_id_rs1_raw_data_q <= 32'h00000000;
            redirect_valid <= 1'b0;
            redirect_pc_q <= 32'h00000000;
            redirect_fallthrough_pc_q <= 32'h00000004;
            redirect_taken_q <= 1'b0;
            redirect_branch_mispredict <= 1'b0;
            redirect_jump_flush <= 1'b0;
            redirect_from_replay <= 1'b0;
            ctrl_replay_valid <= 1'b0;
            ctrl_replay_branch <= 1'b0;
            ctrl_replay_jump <= 1'b0;
            ctrl_replay_jalr <= 1'b0;
            ctrl_replay_pc <= 32'h00000000;
            ctrl_replay_imm <= 32'h00000000;
            ctrl_replay_rs1_data <= 32'h00000000;
            ctrl_replay_rs2_data <= 32'h00000000;
            ctrl_replay_funct3 <= 3'd0;
            ctrl_replay_pred_taken <= 1'b0;
            ctrl_replay_pred_target <= 32'h00000004;
            ctrl_load_pending_valid <= 1'b0;
            ctrl_load_pending_branch <= 1'b0;
            ctrl_load_pending_jump <= 1'b0;
            ctrl_load_pending_jalr <= 1'b0;
            ctrl_load_pending_pc <= 32'h00000000;
            ctrl_load_pending_imm <= 32'h00000000;
            ctrl_load_pending_rs1_data <= 32'h00000000;
            ctrl_load_pending_rs2_data <= 32'h00000000;
            ctrl_load_pending_funct3 <= 3'd0;
            ctrl_load_pending_pred_taken <= 1'b0;
            ctrl_load_pending_pred_target <= 32'h00000004;
            ctrl_load_pending_rs1_from_load <= 1'b0;
            ctrl_load_pending_rs2_from_load <= 1'b0;
            ctrl_load_pending_load_rd <= 5'd0;
            ctrl_load_pending_wait_resp <= 1'b0;
            ras_count <= 4'd0;
            for (ras_i = 0; ras_i < 8; ras_i = ras_i + 1) begin
                ras_stack[ras_i] <= 32'h00000000;
            end
        end else begin
            if_id_load_base_mul_pending_dep_q <= if_id_rs1_mul_pending_dep;

            if (ras_pop) begin
                ras_count <= ras_count - 4'd1;
            end else if (ras_push) begin
                if (ras_count != 4'd8) begin
                    ras_stack[ras_count[2:0]] <= if_id_pc + 32'd4;
                    ras_count <= ras_count + 4'd1;
                end else begin
                    ras_stack[3'd7] <= if_id_pc + 32'd4;
                end
            end

            mul_meta_valid_pipe[0] <= mul_start;
            mul_meta_rd_pipe[0] <= id_ex_rd;
            mul_meta_reg_write_pipe[0] <= id_ex_reg_write;
            for (mul_seq_i = 1; mul_seq_i < MUL_META_DEPTH; mul_seq_i = mul_seq_i + 1) begin
                mul_meta_valid_pipe[mul_seq_i] <= mul_meta_valid_pipe[mul_seq_i-1];
                mul_meta_rd_pipe[mul_seq_i] <= mul_meta_rd_pipe[mul_seq_i-1];
                mul_meta_reg_write_pipe[mul_seq_i] <= mul_meta_reg_write_pipe[mul_seq_i-1];
            end

            if (mul_fifo_pop) begin
                mul_fifo_valid[mul_fifo_head] <= 1'b0;
                mul_fifo_head <= mul_fifo_head + 3'd1;
            end
            if (mul_fifo_push) begin
                mul_fifo_valid[mul_fifo_tail] <= 1'b1;
                mul_fifo_rd[mul_fifo_tail] <= mul_complete_rd;
                mul_fifo_data[mul_fifo_tail] <= mul_result;
                mul_fifo_reg_write[mul_fifo_tail] <= mul_complete_reg_write;
                mul_fifo_tail <= mul_fifo_tail + 3'd1;
            end
            case ({mul_fifo_push, mul_fifo_pop})
                2'b10: mul_fifo_count <= mul_fifo_count + 4'd1;
                2'b01: mul_fifo_count <= mul_fifo_count - 4'd1;
                default: mul_fifo_count <= mul_fifo_count;
            endcase

            if (flush) begin
                div_cmd_valid <= 1'b0;
                div_cmd_rs1_data <= {XLEN{1'b0}};
                div_cmd_rs2_data <= {XLEN{1'b0}};
                div_cmd_funct3 <= 3'd0;
                div_cmd_word_op <= 1'b0;
            end else if (div_launch) begin
                div_cmd_valid <= 1'b1;
                div_cmd_rs1_data <= id_ex_word_op ?
                                    (((id_ex_funct3 == 3'b100) || (id_ex_funct3 == 3'b110)) ?
                                     sign_extend_word(m_ext_forward_a_raw[31:0]) :
                                     zero_extend_word(m_ext_forward_a_raw[31:0])) :
                                    m_ext_forward_a_data;
                div_cmd_rs2_data <= id_ex_word_op ?
                                    (((id_ex_funct3 == 3'b100) || (id_ex_funct3 == 3'b110)) ?
                                     sign_extend_word(m_ext_forward_b_raw[31:0]) :
                                     zero_extend_word(m_ext_forward_b_raw[31:0])) :
                                    m_ext_forward_b_data;
                div_cmd_funct3 <= id_ex_funct3;
                div_cmd_word_op <= id_ex_word_op;
            end else if (div_start) begin
                div_cmd_valid <= 1'b0;
            end

            if (flush) begin
                ctrl_replay_valid <= 1'b0;
                ctrl_load_pending_valid <= 1'b0;
                ctrl_load_pending_wait_resp <= 1'b0;
            end else begin
                if (ctrl_load_pending_valid && ctrl_load_pending_wait_resp) begin
                    ctrl_load_pending_wait_resp <= 1'b0;
                end
                if (ctrl_load_pending_to_replay) begin
                    ctrl_replay_valid <= 1'b1;
                    ctrl_replay_branch <= ctrl_load_pending_branch;
                    ctrl_replay_jump <= ctrl_load_pending_jump;
                    ctrl_replay_jalr <= ctrl_load_pending_jalr;
                    ctrl_replay_pc <= ctrl_load_pending_pc;
                    ctrl_replay_imm <= ctrl_load_pending_imm;
                    ctrl_replay_rs1_data <= ctrl_load_pending_rs1_from_load ? load_resp_data :
                                            ctrl_load_pending_rs1_data;
                    ctrl_replay_rs2_data <= ctrl_load_pending_rs2_from_load ? load_resp_data :
                                            ctrl_load_pending_rs2_data;
                    ctrl_replay_funct3 <= ctrl_load_pending_funct3;
                    ctrl_replay_pred_taken <= ctrl_load_pending_pred_taken;
                    ctrl_replay_pred_target <= ctrl_load_pending_pred_target;
                    ctrl_load_pending_valid <= 1'b0;
                    ctrl_load_pending_wait_resp <= 1'b0;
                end else if (control_replay_capture) begin
                    ctrl_replay_valid <= 1'b1;
                    ctrl_replay_branch <= id_ex_branch;
                    ctrl_replay_jump <= id_ex_jump;
                    ctrl_replay_jalr <= id_ex_jalr;
                    ctrl_replay_pc <= id_ex_pc;
                    ctrl_replay_imm <= id_ex_imm;
                    ctrl_replay_rs1_data <= replay_forward_a_data;
                    ctrl_replay_rs2_data <= replay_forward_b_data;
                    ctrl_replay_funct3 <= id_ex_funct3;
                    ctrl_replay_pred_taken <= id_ex_pred_taken;
                    ctrl_replay_pred_target <= id_ex_pred_target;
                end else if (ctrl_replay_valid && !pipe_wait) begin
                    ctrl_replay_valid <= 1'b0;
                end

                if (load_control_early_capture) begin
                    ctrl_load_pending_valid <= 1'b1;
                    ctrl_load_pending_branch <= dec_branch;
                    ctrl_load_pending_jump <= dec_jump;
                    ctrl_load_pending_jalr <= dec_jalr;
                    ctrl_load_pending_pc <= if_id_pc;
                    ctrl_load_pending_imm <= dec_imm;
                    ctrl_load_pending_rs1_data <= rf_rs1_data;
                    ctrl_load_pending_rs2_data <= rf_rs2_data;
                    ctrl_load_pending_funct3 <= dec_funct3;
                    ctrl_load_pending_pred_taken <= if_id_pred_taken && if_id_valid;
                    ctrl_load_pending_pred_target <= if_id_pred_target;
                    ctrl_load_pending_rs1_from_load <= if_id_control_load_early_rs1_dep;
                    ctrl_load_pending_rs2_from_load <= if_id_control_load_early_rs2_dep;
                    ctrl_load_pending_load_rd <= id_ex_rd;
                    ctrl_load_pending_wait_resp <= 1'b1;
                end
            end

            if (redirect_candidate_valid) begin
                redirect_pc_q <= redirect_target_pc;
                redirect_fallthrough_pc_q <= redirect_fallthrough_pc;
                redirect_taken_q <= take_branch;
            end
            redirect_valid <= redirect_detect;
            redirect_branch_mispredict <= redirect_detect && branch_mispredict_detect;
            redirect_jump_flush <= redirect_detect && jump_needs_flush_detect;
            redirect_from_replay <= ctrl_replay_valid && !pipe_wait;

            load_resp_valid <= !replay_flush && ex_mem_valid && ex_mem_mem_read;
            load_resp_rd <= ex_mem_rd;
            load_resp_funct3 <= ex_mem_funct3;
            load_resp_reg_write <= ex_mem_reg_write;
            load_resp_early_valid <= !replay_flush &&
                                     ex_mem_valid &&
                                     ex_mem_mem_read &&
                                     ex_mem_load_early_valid;
            load_resp_early_data <= ex_mem_load_early_data;

            mem_wb_valid <= !replay_flush && ex_mem_valid && !ex_mem_mem_read;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data <= mem_load_data;
            mem_wb_pc4 <= ex_mem_pc4;
            mem_wb_rd <= ex_mem_rd;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_wb_sel <= ex_mem_wb_sel;

            if (flush) begin
                ex_mem_valid <= 1'b0;
                ex_mem_rd <= 5'd0;
                ex_mem_funct3 <= 3'd0;
                ex_mem_reg_write <= 1'b0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_wb_sel <= 2'd0;
                ex_mem_load_early_valid <= 1'b0;
                ex_mem_load_early_data <= 32'h00000000;
            end else if (exec_wait || control_conflict_stall) begin
                ex_mem_valid <= 1'b0;
                ex_mem_rd <= 5'd0;
                ex_mem_funct3 <= 3'd0;
                ex_mem_reg_write <= 1'b0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_wb_sel <= 2'd0;
                ex_mem_load_early_valid <= 1'b0;
                ex_mem_load_early_data <= 32'h00000000;
            end else if (mul_start) begin
                ex_mem_valid <= 1'b0;
                ex_mem_rd <= 5'd0;
                ex_mem_funct3 <= 3'd0;
                ex_mem_reg_write <= 1'b0;
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_wb_sel <= 2'd0;
                ex_mem_load_early_valid <= 1'b0;
                ex_mem_load_early_data <= 32'h00000000;
            end else if (control_replay_capture) begin
                ex_mem_valid <= id_ex_valid;
                ex_mem_pc4 <= id_ex_pc + 32'd4;
                ex_mem_rd <= id_ex_rd;
                ex_mem_funct3 <= id_ex_funct3;
                ex_mem_reg_write <= id_ex_reg_write;
                ex_mem_mem_read <= 1'b0;
                ex_mem_mem_write <= 1'b0;
                ex_mem_wb_sel <= id_ex_wb_sel;
                ex_mem_load_early_valid <= 1'b0;
                ex_mem_load_early_data <= 32'h00000000;
            end else begin
                ex_mem_valid <= id_ex_valid;
                ex_mem_alu_result <= ex_result;
                ex_mem_rs2_data <= forward_b_data;
                ex_mem_pc4 <= id_ex_pc + 32'd4;
                ex_mem_rd <= id_ex_rd;
                ex_mem_funct3 <= id_ex_funct3;
                ex_mem_reg_write <= id_ex_reg_write;
                ex_mem_mem_read <= id_ex_mem_read;
                ex_mem_mem_write <= id_ex_mem_write;
                ex_mem_wb_sel <= id_ex_wb_sel;
                ex_mem_load_early_valid <= id_ex_valid && id_ex_mem_read && id_ex_load_early_valid;
                ex_mem_load_early_data <= id_ex_early_load_data;
            end

            if (flush) begin
                id_ex_valid <= 1'b0;
                id_ex_reg_write <= 1'b0;
                id_ex_mem_read <= 1'b0;
                id_ex_mem_write <= 1'b0;
                id_ex_branch <= 1'b0;
                id_ex_jump <= 1'b0;
                id_ex_jump_early_redirect <= 1'b0;
                id_ex_csr_instr <= 1'b0;
                id_ex_m_ext <= 1'b0;
                id_ex_word_op <= 1'b0;
                id_ex_pred_taken <= 1'b0;
                id_ex_pred_target <= 32'h00000004;
                id_ex_load_early_valid <= 1'b0;
            end else if (pipe_wait || control_conflict_stall) begin
                id_ex_valid <= id_ex_valid;
                id_ex_pc <= id_ex_pc;
                id_ex_rs1_data <= forward_a_data;
                id_ex_rs2_data <= forward_b_data;
                id_ex_load_early_valid <= id_ex_load_early_valid;
            end else if (load_control_early_capture || hazard_stall ||
                         id_load_early_base_wait ||
                         ctrl_pending_conflict_stall) begin
                id_ex_valid <= 1'b0;
                id_ex_reg_write <= 1'b0;
                id_ex_mem_read <= 1'b0;
                id_ex_mem_write <= 1'b0;
                id_ex_branch <= 1'b0;
                id_ex_jump <= 1'b0;
                id_ex_jump_early_redirect <= 1'b0;
                id_ex_csr_instr <= 1'b0;
                id_ex_m_ext <= 1'b0;
                id_ex_word_op <= 1'b0;
                id_ex_pred_taken <= 1'b0;
                id_ex_pred_target <= 32'h00000004;
                id_ex_load_early_valid <= 1'b0;
            end else begin
                id_ex_valid <= if_id_valid;
                id_ex_pc <= if_id_pc;
                id_ex_imm <= dec_imm;
                id_ex_rs1_data <= rf_rs1_data;
                id_ex_rs2_data <= rf_rs2_data;
                id_ex_rs1 <= dec_rs1;
                id_ex_rs2 <= dec_rs2;
                id_ex_rd <= dec_rd;
                id_ex_funct3 <= dec_funct3;
                id_ex_alu_op <= dec_alu_op;
                id_ex_alu_src_imm <= dec_alu_src_imm;
                id_ex_reg_write <= dec_reg_write && if_id_valid;
                id_ex_mem_read <= dec_mem_read && if_id_valid;
                id_ex_mem_write <= dec_mem_write && if_id_valid;
                id_ex_wb_sel <= dec_wb_sel;
                id_ex_branch <= dec_branch && if_id_valid;
                id_ex_jump <= dec_jump && if_id_valid;
                id_ex_jalr <= dec_jalr;
                id_ex_jump_early_redirect <= id_jump_resolved_in_id;
                id_ex_csr_instr <= dec_csr_instr && if_id_valid;
                id_ex_csr_addr <= if_id_instr[31:20];
                id_ex_m_ext <= dec_m_ext && if_id_valid;
                id_ex_word_op <= dec_word_op && if_id_valid;
                id_ex_pred_taken <= if_id_pred_taken && if_id_valid;
                id_ex_pred_target <= id_jalr_ras_redirect ? ras_top_target : if_id_pred_target;
                id_ex_load_early_valid <= id_load_early_read;
            end

            if (flush) begin
                pc <= redirect_pc;
                fetch_pc_q <= 32'h00000000;
                fetch_valid_q <= 1'b0;
                fetch_pred_taken_q <= 1'b0;
                fetch_pred_target_q <= 32'h00000004;
                if_id_pc <= 32'h00000000;
                if_id_instr <= 32'h00000013;
                if_id_pred_taken <= 1'b0;
                if_id_pred_target <= 32'h00000004;
                if_id_valid <= 1'b0;
                if_id_mem_read_q <= 1'b0;
                if_id_load_rs1_q <= 5'd0;
                if_id_load_rs1_nonzero_q <= 1'b0;
                if_id_load_imm_q <= 32'h00000000;
                if_id_rs1_raw_data_q <= 32'h00000000;
            end else if (pipe_wait || control_conflict_stall ||
                         ctrl_pending_conflict_stall ||
                         id_load_early_base_wait) begin
                pc <= pc;
                fetch_pc_q <= fetch_pc_q;
                fetch_valid_q <= fetch_valid_q;
                fetch_pred_taken_q <= fetch_pred_taken_q;
                fetch_pred_target_q <= fetch_pred_target_q;
                if_id_pc <= if_id_pc;
                if_id_instr <= if_id_instr;
                if_id_pred_taken <= if_id_pred_taken;
                if_id_pred_target <= if_id_pred_target;
                if_id_valid <= if_id_valid;
                if_id_mem_read_q <= if_id_mem_read_q;
                if_id_load_rs1_q <= if_id_load_rs1_q;
                if_id_load_rs1_nonzero_q <= if_id_load_rs1_nonzero_q;
                if_id_load_imm_q <= if_id_load_imm_q;
                if_id_rs1_raw_data_q <= if_id_rs1_raw_hold_data;
            end else if (id_jal_redirect || id_jalr_ras_redirect) begin
                pc <= id_jalr_ras_redirect ? ras_top_target : id_jal_target;
                fetch_pc_q <= 32'h00000000;
                fetch_valid_q <= 1'b0;
                fetch_pred_taken_q <= 1'b0;
                fetch_pred_target_q <= 32'h00000004;
                if_id_pc <= 32'h00000000;
                if_id_instr <= 32'h00000013;
                if_id_pred_taken <= 1'b0;
                if_id_pred_target <= 32'h00000004;
                if_id_valid <= 1'b0;
                if_id_mem_read_q <= 1'b0;
                if_id_load_rs1_q <= 5'd0;
                if_id_load_rs1_nonzero_q <= 1'b0;
                if_id_load_imm_q <= 32'h00000000;
                if_id_rs1_raw_data_q <= 32'h00000000;
            end else if (!hazard_stall) begin
                pc <= predicted_next_pc;
                fetch_pc_q <= pc;
                fetch_valid_q <= 1'b1;
                fetch_pred_taken_q <= predict_taken;
                fetch_pred_target_q <= predict_target;
                if_id_pc <= prefetch_pc;
                if_id_instr <= prefetch_valid ? prefetch_instr : 32'h00000013;
                if_id_pred_taken <= prefetch_valid ? prefetch_pred_taken : 1'b0;
                if_id_pred_target <= prefetch_valid ? prefetch_pred_target : (prefetch_pc + 32'd4);
                if_id_valid <= prefetch_valid;
                if_id_mem_read_q <= prefetch_valid && prefetch_mem_read;
                if_id_load_rs1_q <= (prefetch_valid && prefetch_mem_read) ? prefetch_rs1 : 5'd0;
                if_id_load_rs1_nonzero_q <= prefetch_valid && prefetch_mem_read && (prefetch_rs1 != 5'd0);
                if_id_load_imm_q <= (prefetch_valid && prefetch_mem_read) ? prefetch_load_imm : 32'h00000000;
                if_id_rs1_raw_data_q <= prefetch_valid ? rf_prefetch_rs1_data : 32'h00000000;
            end else begin
                if_id_mem_read_q <= if_id_mem_read_q;
                if_id_load_rs1_q <= if_id_load_rs1_q;
                if_id_load_rs1_nonzero_q <= if_id_load_rs1_nonzero_q;
                if_id_load_imm_q <= if_id_load_imm_q;
                if_id_rs1_raw_data_q <= if_id_rs1_raw_hold_data;
            end
        end
    end
endmodule
