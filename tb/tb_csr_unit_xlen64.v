`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_xlen64;
    reg clk;
    reg rst;
    reg retire_i;
    reg [1:0] retire_count_i;
    reg csr_read_valid_i;
    reg [2:0] csr_read_op_i;
    reg [11:0] csr_read_addr_i;
    reg [63:0] csr_read_wdata_i;
    reg csr_read_rd_zero_i;
    wire [63:0] csr_read_data_o;
    wire csr_read_illegal_o;
    reg csr_commit_valid_i;
    reg [2:0] csr_commit_op_i;
    reg [11:0] csr_commit_addr_i;
    reg [63:0] csr_commit_wdata_i;
    reg csr_commit_rd_zero_i;
    reg trap_commit_valid_i;
    reg [63:0] trap_mepc_i;
    reg [63:0] trap_mcause_i;
    reg [63:0] trap_mtval_i;
    reg mret_commit_valid_i;
    wire [63:0] trap_pc_o;
    wire [63:0] mret_pc_o;
    wire [63:0] mcycle_o;
    wire [63:0] minstret_o;

    csr_unit #(.XLEN(64), .HART_ID(5)) dut (
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
            csr_read_wdata_i = 64'h0000000000000000;
            csr_read_rd_zero_i = 1'b0;
            csr_commit_valid_i = 1'b0;
            csr_commit_op_i = `CSR_OP_NONE;
            csr_commit_addr_i = 12'h000;
            csr_commit_wdata_i = 64'h0000000000000000;
            csr_commit_rd_zero_i = 1'b0;
            trap_commit_valid_i = 1'b0;
            trap_mepc_i = 64'h0000000000000000;
            trap_mcause_i = 64'h0000000000000000;
            trap_mtval_i = 64'h0000000000000000;
            mret_commit_valid_i = 1'b0;
        end
    endtask

    task csr_commit;
        input [2:0] op;
        input [11:0] addr;
        input [63:0] data;
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
        input [63:0] expected;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = `CSR_OP_RS;
            csr_read_addr_i = addr;
            csr_read_wdata_i = 64'h0000000000000000;
            csr_read_rd_zero_i = 1'b0;
            #1;
            if (csr_read_illegal_o || csr_read_data_o !== expected) begin
                $display("FAIL csr_read addr=%03x expected=%016x got=%016x illegal=%b",
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

        csr_read_expect(`CSR_MISA, 64'h8000000000001100);
        csr_read_expect(`CSR_MHARTID, 64'h0000000000000005);

        csr_read_valid_i = 1'b1;
        csr_read_op_i = `CSR_OP_RS;
        csr_read_addr_i = `CSR_MCYCLEH;
        csr_read_wdata_i = 64'h0000000000000000;
        csr_read_rd_zero_i = 1'b0;
        #1;
        if (!csr_read_illegal_o) begin
            $display("FAIL RV64 mcycleh read was not illegal");
            $finish;
        end
        clear_req();

        csr_commit(`CSR_OP_RW, `CSR_MSCRATCH, 64'hfedcba9876543210);
        csr_read_expect(`CSR_MSCRATCH, 64'hfedcba9876543210);

        $display("PASS csr_unit xlen64 regression completed");
        $finish;
    end
endmodule
