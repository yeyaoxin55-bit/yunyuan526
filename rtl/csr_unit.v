`include "defines.vh"

module csr_unit #(
    parameter XLEN = 32,
    parameter HART_ID = 0,
    parameter SUPPORT_M = 1,
    parameter SUPPORT_ZICSR = 1,
    parameter SUPPORT_C = 0
) (
    input wire clk,
    input wire rst,

    input wire retire_i,
    input wire [1:0] retire_count_i,

    input wire csr_read_valid_i,
    input wire [2:0] csr_read_op_i,
    input wire [11:0] csr_read_addr_i,
    input wire [XLEN-1:0] csr_read_wdata_i,
    input wire csr_read_rd_zero_i,
    output reg [XLEN-1:0] csr_read_data_o,
    output reg csr_read_illegal_o,

    input wire csr_commit_valid_i,
    input wire [2:0] csr_commit_op_i,
    input wire [11:0] csr_commit_addr_i,
    input wire [XLEN-1:0] csr_commit_wdata_i,
    input wire csr_commit_rd_zero_i,

    input wire trap_commit_valid_i,
    input wire [XLEN-1:0] trap_mepc_i,
    input wire [XLEN-1:0] trap_mcause_i,
    input wire [XLEN-1:0] trap_mtval_i,

    input wire mret_commit_valid_i,

    output wire [XLEN-1:0] trap_pc_o,
    output wire [XLEN-1:0] mret_pc_o,
    output wire [XLEN-1:0] mcycle_o,
    output wire [XLEN-1:0] minstret_o
);
    localparam [XLEN-1:0] ZERO = {XLEN{1'b0}};
    localparam [XLEN-1:0] MSTATUS_MIE  = {{(XLEN-4){1'b0}}, 1'b1, 3'b000};
    localparam [XLEN-1:0] MSTATUS_MPIE = {{(XLEN-8){1'b0}}, 1'b1, 7'b0000000};
    localparam [XLEN-1:0] MSTATUS_MPP  = {{(XLEN-13){1'b0}}, 2'b11, 11'b00000000000};
    localparam [XLEN-1:0] MSTATUS_MASK = MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP;
    localparam MSTATUS_MIE_BIT = 3;
    localparam MSTATUS_MPIE_BIT = 7;
    localparam [XLEN-1:0] MIE_MIP_MASK = {{(XLEN-12){1'b0}}, 1'b1, 3'b000, 1'b1, 3'b000, 1'b1, 3'b000};
    localparam [XLEN-1:0] MHARTID_VALUE = HART_ID;

    reg [XLEN-1:0] mstatus_r;
    reg [XLEN-1:0] mie_r;
    reg [XLEN-1:0] mtvec_r;
    reg [XLEN-1:0] mscratch_r;
    reg [XLEN-1:0] mepc_r;
    reg [XLEN-1:0] mcause_r;
    reg [XLEN-1:0] mtval_r;
    reg [XLEN-1:0] mip_r;
    reg [63:0] mcycle_r;
    reg [63:0] minstret_r;

    wire [1:0] misa_mxl = (XLEN == 64) ? 2'b10 : 2'b01;
    wire [XLEN-1:0] misa_value =
        ({XLEN{1'b0}} |
         ({{(XLEN-2){1'b0}}, misa_mxl} << (XLEN - 2)) |
         ({{(XLEN-9){1'b0}}, 1'b1} << 8) |
         ({{(XLEN-13){1'b0}}, 1'b1} << 12));

    assign trap_pc_o = {mtvec_r[XLEN-1:2], 2'b00};
    assign mret_pc_o = mask_mepc(mepc_r);
    assign mcycle_o = mcycle_r[XLEN-1:0];
    assign minstret_o = minstret_r[XLEN-1:0];

    function [XLEN-1:0] mask_mepc;
        input [XLEN-1:0] value;
        begin
            mask_mepc = SUPPORT_C ? {value[XLEN-1:1], 1'b0} :
                                    {value[XLEN-1:2], 2'b00};
        end
    endfunction

    function [XLEN-1:0] mask_mstatus;
        input [XLEN-1:0] value;
        begin
            mask_mstatus = (value & MSTATUS_MASK) | MSTATUS_MPP;
        end
    endfunction

    function [XLEN-1:0] mask_mtvec;
        input [XLEN-1:0] value;
        begin
            mask_mtvec = {value[XLEN-1:2], 1'b0, value[0]};
        end
    endfunction

    function csr_is_read_only;
        input [11:0] addr;
        begin
            case (addr)
                `CSR_MISA,
                `CSR_MVENDORID,
                `CSR_MARCHID,
                `CSR_MIMPID,
                `CSR_MHARTID: csr_is_read_only = 1'b1;
                default: csr_is_read_only = (addr[11:10] == 2'b11);
            endcase
        end
    endfunction

    function csr_write_requested;
        input [2:0] op;
        input [XLEN-1:0] src;
        begin
            case (op)
                `CSR_OP_RW,
                `CSR_OP_RWI: csr_write_requested = 1'b1;
                `CSR_OP_RS,
                `CSR_OP_RC,
                `CSR_OP_RSI,
                `CSR_OP_RCI: csr_write_requested = |src;
                default: csr_write_requested = 1'b0;
            endcase
        end
    endfunction

    function csr_op_legal;
        input [2:0] op;
        begin
            case (op)
                `CSR_OP_RW,
                `CSR_OP_RS,
                `CSR_OP_RC,
                `CSR_OP_RWI,
                `CSR_OP_RSI,
                `CSR_OP_RCI: csr_op_legal = 1'b1;
                default: csr_op_legal = 1'b0;
            endcase
        end
    endfunction

    function csr_addr_supported;
        input [11:0] addr;
        begin
            case (addr)
                `CSR_MSTATUS,
                `CSR_MISA,
                `CSR_MIE,
                `CSR_MTVEC,
                `CSR_MSCRATCH,
                `CSR_MEPC,
                `CSR_MCAUSE,
                `CSR_MTVAL,
                `CSR_MIP,
                `CSR_MCYCLE,
                `CSR_MINSTRET,
                `CSR_MVENDORID,
                `CSR_MARCHID,
                `CSR_MIMPID,
                `CSR_MHARTID: csr_addr_supported = 1'b1;
                `CSR_MCYCLEH,
                `CSR_MINSTRETH: csr_addr_supported = (XLEN == 32);
                default: csr_addr_supported = 1'b0;
            endcase
        end
    endfunction

    function [XLEN-1:0] csr_value;
        input [11:0] addr;
        begin
            case (addr)
                `CSR_MSTATUS: csr_value = mstatus_r;
                `CSR_MISA: csr_value = misa_value;
                `CSR_MIE: csr_value = mie_r;
                `CSR_MTVEC: csr_value = mtvec_r;
                `CSR_MSCRATCH: csr_value = mscratch_r;
                `CSR_MEPC: csr_value = mepc_r;
                `CSR_MCAUSE: csr_value = mcause_r;
                `CSR_MTVAL: csr_value = mtval_r;
                `CSR_MIP: csr_value = mip_r;
                `CSR_MCYCLE: csr_value = mcycle_r[XLEN-1:0];
                `CSR_MINSTRET: csr_value = minstret_r[XLEN-1:0];
                `CSR_MCYCLEH: csr_value = (XLEN == 32) ? mcycle_r[63:32] : ZERO;
                `CSR_MINSTRETH: csr_value = (XLEN == 32) ? minstret_r[63:32] : ZERO;
                `CSR_MVENDORID: csr_value = ZERO;
                `CSR_MARCHID: csr_value = ZERO;
                `CSR_MIMPID: csr_value = ZERO;
                `CSR_MHARTID: csr_value = MHARTID_VALUE;
                default: csr_value = ZERO;
            endcase
        end
    endfunction

    function [XLEN-1:0] csr_apply_op;
        input [2:0] op;
        input [XLEN-1:0] old_value;
        input [XLEN-1:0] src;
        begin
            case (op)
                `CSR_OP_RW,
                `CSR_OP_RWI: csr_apply_op = src;
                `CSR_OP_RS,
                `CSR_OP_RSI: csr_apply_op = old_value | src;
                `CSR_OP_RC,
                `CSR_OP_RCI: csr_apply_op = old_value & ~src;
                default: csr_apply_op = old_value;
            endcase
        end
    endfunction

    wire [XLEN-1:0] csr_commit_next_value =
        csr_apply_op(csr_commit_op_i, csr_value(csr_commit_addr_i), csr_commit_wdata_i);

    always @(*) begin
        csr_read_data_o = csr_value(csr_read_addr_i);
        csr_read_illegal_o = 1'b0;

        if (csr_read_valid_i === 1'b1) begin
            csr_read_illegal_o = !SUPPORT_M || !SUPPORT_ZICSR ||
                                 !csr_op_legal(csr_read_op_i) ||
                                 !csr_addr_supported(csr_read_addr_i) ||
                                 (csr_write_requested(csr_read_op_i, csr_read_wdata_i) &&
                                  csr_is_read_only(csr_read_addr_i));
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            mcycle_r <= 64'h0000000000000000;
            minstret_r <= 64'h0000000000000000;
            mstatus_r <= {XLEN{1'b0}};
            mie_r <= {XLEN{1'b0}};
            mtvec_r <= {XLEN{1'b0}};
            mscratch_r <= {XLEN{1'b0}};
            mepc_r <= {XLEN{1'b0}};
            mcause_r <= {XLEN{1'b0}};
            mtval_r <= {XLEN{1'b0}};
            mip_r <= {XLEN{1'b0}};
        end else begin
            mcycle_r <= mcycle_r + 64'h0000000000000001;
            if (retire_i === 1'b1) begin
                minstret_r <= minstret_r + {62'h0000000000000000, retire_count_i};
            end

            if (trap_commit_valid_i === 1'b1) begin
                mepc_r <= mask_mepc(trap_mepc_i);
                mcause_r <= trap_mcause_i;
                mtval_r <= trap_mtval_i;
                mstatus_r <= (mstatus_r & ~(MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP)) |
                             (mstatus_r[MSTATUS_MIE_BIT] ? MSTATUS_MPIE : ZERO) |
                             MSTATUS_MPP;
            end

            if (mret_commit_valid_i === 1'b1) begin
                mstatus_r <= (mstatus_r & ~(MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP)) |
                             (mstatus_r[MSTATUS_MPIE_BIT] ? MSTATUS_MIE : ZERO) |
                             MSTATUS_MPIE |
                             MSTATUS_MPP;
            end

            if ((csr_commit_valid_i === 1'b1) &&
                csr_addr_supported(csr_commit_addr_i) &&
                !csr_is_read_only(csr_commit_addr_i) &&
                csr_write_requested(csr_commit_op_i, csr_commit_wdata_i)) begin
                case (csr_commit_addr_i)
                    `CSR_MSTATUS: mstatus_r <= mask_mstatus(csr_commit_next_value);
                    `CSR_MIE: mie_r <= csr_commit_next_value & MIE_MIP_MASK;
                    `CSR_MTVEC: mtvec_r <= mask_mtvec(csr_commit_next_value);
                    `CSR_MSCRATCH: mscratch_r <= csr_commit_next_value;
                    `CSR_MEPC: mepc_r <= mask_mepc(csr_commit_next_value);
                    `CSR_MCAUSE: mcause_r <= csr_commit_next_value;
                    `CSR_MTVAL: mtval_r <= csr_commit_next_value;
                    `CSR_MIP: mip_r <= csr_commit_next_value & MIE_MIP_MASK;
                    `CSR_MCYCLE: begin
                        if (XLEN == 32) begin
                            mcycle_r[31:0] <= csr_commit_next_value[31:0];
                        end else begin
                            mcycle_r <= csr_commit_next_value;
                        end
                    end
                    `CSR_MINSTRET: begin
                        if (XLEN == 32) begin
                            minstret_r[31:0] <= csr_commit_next_value[31:0];
                        end else begin
                            minstret_r <= csr_commit_next_value;
                        end
                    end
                    `CSR_MCYCLEH: begin
                        if (XLEN == 32) begin
                            mcycle_r[63:32] <= csr_commit_next_value[31:0];
                        end
                    end
                    `CSR_MINSTRETH: begin
                        if (XLEN == 32) begin
                            minstret_r[63:32] <= csr_commit_next_value[31:0];
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
