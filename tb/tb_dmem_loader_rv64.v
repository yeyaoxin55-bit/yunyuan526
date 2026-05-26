`timescale 1ns/1ps

module tb_dmem_loader_rv64;
    localparam DMEM_BASE = 32'h00010000;

    reg clk;
    reg mem_read;
    reg mem_write;
    reg [7:0] byte_en;
    reg [31:0] addr;
    reg [63:0] wdata;
    wire [63:0] rdata;
    reg loader_we;
    reg [31:0] loader_addr;
    reg [31:0] loader_wdata;

    dmem #(
        .XLEN(64),
        .DMEM_DEPTH(16),
        .DMEM_BASE(DMEM_BASE),
        .DMEM_INIT_FILE(""),
        .SUPPORT_MISALIGNED(0)
    ) dut (
        .clk(clk),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .byte_en(byte_en),
        .addr(addr),
        .wdata(wdata),
        .rdata(rdata),
        .debug_word0(),
        .debug_word1(),
        .debug_word2(),
        .debug_word3(),
        .debug_word4(),
        .debug_pass_word(),
        .debug_fail_word(),
        .debug_cycle_word(),
        .loader_we(loader_we),
        .loader_addr(loader_addr),
        .loader_wdata(loader_wdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task loader_write32;
        input [31:0] write_addr;
        input [31:0] write_data;
        begin
            @(negedge clk);
            loader_addr = write_addr;
            loader_wdata = write_data;
            loader_we = 1'b1;
            @(negedge clk);
            loader_we = 1'b0;
        end
    endtask

    task read64_and_check;
        input [31:0] read_addr;
        input [63:0] expected;
        begin
            @(negedge clk);
            addr = read_addr;
            mem_read = 1'b1;
            @(posedge clk);
            #1;
            if (rdata !== expected) begin
                $display("FAIL dmem_loader_rv64: addr=%08x rdata=%016x expected=%016x",
                    read_addr, rdata, expected);
                $finish;
            end
            @(negedge clk);
            mem_read = 1'b0;
        end
    endtask

    initial begin
        mem_read = 1'b0;
        mem_write = 1'b0;
        byte_en = 8'h00;
        addr = DMEM_BASE;
        wdata = 64'h0000000000000000;
        loader_we = 1'b0;
        loader_addr = DMEM_BASE;
        loader_wdata = 32'h00000000;

        repeat (3) @(posedge clk);

        loader_write32(DMEM_BASE + 32'd0, 32'h55667788);
        loader_write32(DMEM_BASE + 32'd4, 32'h11223344);

        read64_and_check(DMEM_BASE + 32'd0, 64'h1122334455667788);
        read64_and_check(DMEM_BASE + 32'd4, 64'h0000000011223344);

        $display("PASS RV64 DMEM loader halfword merge completed");
        $finish;
    end
endmodule
