`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_trap_mret;
    reg clk;
    reg rst;
    reg retire_i;
    reg [1:0] retire_count_i;
    reg csr_read_valid_i;
    reg [2:0] csr_read_op_i;
    reg [11:0] csr_read_addr_i;
    reg [31:0] csr_read_wdata_i;
    reg csr_read_rd_zero_i;
    wire [31:0] csr_read_data_o;
    wire csr_read_illegal_o;
    reg csr_commit_valid_i;
    reg [2:0] csr_commit_op_i;
    reg [11:0] csr_commit_addr_i;
    reg [31:0] csr_commit_wdata_i;
    reg csr_commit_rd_zero_i;
    reg trap_commit_valid_i;
    reg [31:0] trap_mepc_i;
    reg [31:0] trap_mcause_i;
    reg [31:0] trap_mtval_i;
    reg mret_commit_valid_i;
    wire [31:0] trap_pc_o;
    wire [31:0] mret_pc_o;
    wire [31:0] mcycle_o;
    wire [31:0] minstret_o;

    csr_unit #(.XLEN(32), .HART_ID(0), .SUPPORT_C(0)) dut (
        .clk(clk),
        .rst(rst),
        .retire_i(retire_i),
        .retire_count_i(retire_count_i),
        .csr_read_valid_i(csr_read_valid_i),
        .csr_read_op_i(csr_read_op_i),
        .csr_read_addr_i(csr_read_addr_i),
        .csr_read_wdata_i(csr_read_wdata_i),
        .csr_read_rd_zero_i(csr_read_rd_zero_i),
        .csr_read_data_o(csr_read_data_o),
        .csr_read_illegal_o(csr_read_illegal_o),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_commit_op_i(csr_commit_op_i),
        .csr_commit_addr_i(csr_commit_addr_i),
        .csr_commit_wdata_i(csr_commit_wdata_i),
        .csr_commit_rd_zero_i(csr_commit_rd_zero_i),
        .trap_commit_valid_i(trap_commit_valid_i),
        .trap_mepc_i(trap_mepc_i),
        .trap_mcause_i(trap_mcause_i),
        .trap_mtval_i(trap_mtval_i),
        .mret_commit_valid_i(mret_commit_valid_i),
        .trap_pc_o(trap_pc_o),
        .mret_pc_o(mret_pc_o),
        .mcycle_o(mcycle_o),
        .minstret_o(minstret_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task clear_req;
        begin
            retire_i = 1'b0;
            retire_count_i = 2'd0;
            csr_read_valid_i = 1'b0;
            csr_read_op_i = `CSR_OP_NONE;
            csr_read_addr_i = 12'h000;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            csr_commit_valid_i = 1'b0;
            csr_commit_op_i = `CSR_OP_NONE;
            csr_commit_addr_i = 12'h000;
            csr_commit_wdata_i = 32'h00000000;
            csr_commit_rd_zero_i = 1'b0;
            trap_commit_valid_i = 1'b0;
            trap_mepc_i = 32'h00000000;
            trap_mcause_i = 32'h00000000;
            trap_mtval_i = 32'h00000000;
            mret_commit_valid_i = 1'b0;
        end
    endtask

    task csr_commit;
        input [2:0] op;
        input [11:0] addr;
        input [31:0] data;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = op;
            csr_read_addr_i = addr;
            csr_read_wdata_i = data;
            csr_read_rd_zero_i = 1'b0;
            #1;
            if (csr_read_illegal_o) begin
                $display("FAIL unexpected illegal CSR addr=%03x op=%0d", addr, op);
                $finish;
            end
            csr_commit_valid_i = 1'b1;
            csr_commit_op_i = op;
            csr_commit_addr_i = addr;
            csr_commit_wdata_i = data;
            csr_commit_rd_zero_i = 1'b0;
            @(posedge clk);
            #1;
            clear_req();
        end
    endtask

    task csr_read_expect;
        input [11:0] addr;
        input [31:0] expected;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = `CSR_OP_RS;
            csr_read_addr_i = addr;
            csr_read_wdata_i = 32'h00000000;
            csr_read_rd_zero_i = 1'b0;
            #1;
            if (csr_read_illegal_o || csr_read_data_o !== expected) begin
                $display("FAIL csr_read addr=%03x expected=%08x got=%08x illegal=%b",
                    addr, expected, csr_read_data_o, csr_read_illegal_o);
                $finish;
            end
            clear_req();
        end
    endtask

    initial begin
        clear_req();
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        csr_commit(`CSR_OP_RW, `CSR_MTVEC, 32'h80000103);
        csr_read_expect(`CSR_MTVEC, 32'h80000101);
        #1;
        if (trap_pc_o !== 32'h80000100) begin
            $display("FAIL trap_pc BASE expected=80000100 got=%08x", trap_pc_o);
            $finish;
        end

        csr_commit(`CSR_OP_RW, `CSR_MSTATUS, 32'h00000008);
        csr_read_expect(`CSR_MSTATUS, 32'h00001808);
        trap_commit_valid_i = 1'b1;
        trap_mepc_i = 32'h00000123;
        trap_mcause_i = `CAUSE_ILLEGAL_INSTRUCTION;
        trap_mtval_i = 32'hdeadbeef;
        @(posedge clk);
        #1;
        clear_req();

        csr_read_expect(`CSR_MEPC, 32'h00000120);
        csr_read_expect(`CSR_MCAUSE, `CAUSE_ILLEGAL_INSTRUCTION);
        csr_read_expect(`CSR_MTVAL, 32'hdeadbeef);
        csr_read_expect(`CSR_MSTATUS, 32'h00001880);

        if (mret_pc_o !== 32'h00000120) begin
            $display("FAIL mret_pc expected=00000120 got=%08x", mret_pc_o);
            $finish;
        end

        mret_commit_valid_i = 1'b1;
        @(posedge clk);
        #1;
        clear_req();

        csr_read_expect(`CSR_MSTATUS, 32'h00001888);

        $display("PASS csr_unit trap/mret regression completed");
        $finish;
    end
endmodule
