`timescale 1ns/1ps
`include "defines.vh"

module tb_csr_unit_zicsr;
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
    wire [31:0] disabled_read_data_o;
    wire disabled_read_illegal_o;
    wire [31:0] disabled_mcycle_o;
    wire [31:0] disabled_minstret_o;

    csr_unit #(.XLEN(32), .HART_ID(0)) dut (
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

    csr_unit #(.XLEN(32), .HART_ID(0), .SUPPORT_ZICSR(0)) disabled_dut (
        .clk(clk),
        .rst(rst),
        .retire_i(1'b0),
        .retire_count_i(2'd0),
        .csr_read_valid_i(csr_read_valid_i),
        .csr_read_op_i(csr_read_op_i),
        .csr_read_addr_i(csr_read_addr_i),
        .csr_read_wdata_i(csr_read_wdata_i),
        .csr_read_rd_zero_i(csr_read_rd_zero_i),
        .csr_read_data_o(disabled_read_data_o),
        .csr_read_illegal_o(disabled_read_illegal_o),
        .csr_commit_valid_i(csr_commit_valid_i),
        .csr_commit_op_i(csr_commit_op_i),
        .csr_commit_addr_i(csr_commit_addr_i),
        .csr_commit_wdata_i(csr_commit_wdata_i),
        .csr_commit_rd_zero_i(csr_commit_rd_zero_i),
        .trap_commit_valid_i(1'b0),
        .trap_mepc_i(32'h00000000),
        .trap_mcause_i(32'h00000000),
        .trap_mtval_i(32'h00000000),
        .mret_commit_valid_i(1'b0),
        .trap_pc_o(),
        .mret_pc_o(),
        .mcycle_o(disabled_mcycle_o),
        .minstret_o(disabled_minstret_o)
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
        input rd_zero;
        begin
            csr_read_valid_i = 1'b1;
            csr_read_op_i = op;
            csr_read_addr_i = addr;
            csr_read_wdata_i = data;
            csr_read_rd_zero_i = rd_zero;
            #1;
            if (csr_read_illegal_o) begin
                $display("FAIL unexpected illegal CSR addr=%03x op=%0d", addr, op);
                $finish;
            end
            csr_commit_valid_i = 1'b1;
            csr_commit_op_i = op;
            csr_commit_addr_i = addr;
            csr_commit_wdata_i = data;
            csr_commit_rd_zero_i = rd_zero;
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

    task csr_commit_with_retire;
        input [2:0] op;
        input [11:0] addr;
        input [31:0] data;
        input [1:0] count;
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
            retire_i = 1'b1;
            retire_count_i = count;
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

    initial begin
        clear_req();
        rst = 1'b1;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        csr_commit(`CSR_OP_RW, `CSR_MSCRATCH, 32'h12345678, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h12345678);

        csr_commit(`CSR_OP_RS, `CSR_MSCRATCH, 32'h0000ff00, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h1234ff78);

        csr_commit(`CSR_OP_RC, `CSR_MSCRATCH, 32'h00000078, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h1234ff00);

        csr_commit(`CSR_OP_RW, `CSR_MCYCLE, 32'h89abcdef, 1'b0);
        csr_read_expect(`CSR_MCYCLE, 32'h89abcdef);
        csr_commit(`CSR_OP_RW, `CSR_MCYCLEH, 32'h12345678, 1'b0);
        csr_read_expect(`CSR_MCYCLEH, 32'h12345678);

        csr_commit(`CSR_OP_RW, `CSR_MINSTRET, 32'h01020304, 1'b0);
        csr_read_expect(`CSR_MINSTRET, 32'h01020304);
        csr_commit(`CSR_OP_RW, `CSR_MINSTRETH, 32'h11223344, 1'b0);
        csr_read_expect(`CSR_MINSTRETH, 32'h11223344);

        csr_commit(`CSR_OP_RW, `CSR_MCYCLEH, 32'h00000000, 1'b0);
        csr_commit(`CSR_OP_RW, `CSR_MCYCLE, 32'hffffffff, 1'b0);
        csr_commit(`CSR_OP_RW, `CSR_MCYCLE, 32'h00000010, 1'b0);
        csr_read_expect(`CSR_MCYCLEH, 32'h00000000);
        csr_read_expect(`CSR_MCYCLE, 32'h00000010);

        csr_commit(`CSR_OP_RW, `CSR_MINSTRETH, 32'h00000000, 1'b0);
        csr_commit(`CSR_OP_RW, `CSR_MINSTRET, 32'hffffffff, 1'b0);
        csr_commit_with_retire(`CSR_OP_RW, `CSR_MINSTRET, 32'h00000020, 2'd3);
        csr_read_expect(`CSR_MINSTRETH, 32'h00000000);
        csr_read_expect(`CSR_MINSTRET, 32'h00000020);

        csr_commit(`CSR_OP_RW, `CSR_MINSTRET, 32'hfffffffe, 1'b0);
        csr_commit_with_retire(`CSR_OP_RW, `CSR_MINSTRETH, 32'h00000022, 2'd3);
        csr_read_expect(`CSR_MINSTRETH, 32'h00000022);
        csr_read_expect(`CSR_MINSTRET, 32'hfffffffe);

        csr_commit(`CSR_OP_RW, `CSR_MINSTRET, 32'hffffffff, 1'b0);
        csr_commit(`CSR_OP_RW, `CSR_MINSTRETH, 32'hffffffff, 1'b0);
        retire_i = 1'b1;
        retire_count_i = 2'd1;
        @(posedge clk);
        #1;
        clear_req();
        csr_read_expect(`CSR_MINSTRET, 32'h00000000);
        csr_read_expect(`CSR_MINSTRETH, 32'h00000000);

        csr_commit(`CSR_OP_RWI, `CSR_MSCRATCH, 32'h0000001f, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001f);

        csr_commit(`CSR_OP_RSI, `CSR_MSCRATCH, 32'h00000000, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001f);

        csr_commit(`CSR_OP_RCI, `CSR_MSCRATCH, 32'h00000001, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001e);

        csr_commit(`CSR_OP_RS, `CSR_MSCRATCH, 32'h00000000, 1'b0);
        csr_read_expect(`CSR_MSCRATCH, 32'h0000001e);

        csr_commit(`CSR_OP_RW, `CSR_MSCRATCH, 32'haaaaaaaa, 1'b0);
        csr_read_valid_i = 1'b1;
        csr_read_op_i = `CSR_OP_RS;
        csr_read_addr_i = `CSR_MSCRATCH;
        csr_read_wdata_i = 32'h00000000;
        csr_read_rd_zero_i = 1'b0;
        #1;
        if (!disabled_read_illegal_o || disabled_read_data_o !== 32'h00000000) begin
            $display("FAIL disabled Zicsr read illegal=%b data=%08x", disabled_read_illegal_o, disabled_read_data_o);
            $finish;
        end
        clear_req();

        csr_read_expect(`CSR_MISA, 32'h40001100);
        csr_commit(`CSR_OP_RSI, `CSR_MISA, 32'h00000004, 1'b0);
        csr_read_expect(`CSR_MISA, 32'h40001100);
        csr_commit(`CSR_OP_RW, `CSR_MISA, 32'hffffffff, 1'b0);
        csr_read_expect(`CSR_MISA, 32'h40001100);

        $display("PASS csr_unit zicsr regression completed");
        $finish;
    end
endmodule
