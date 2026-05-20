`timescale 1ns/1ps

module tb_loader_memory_ports;
    reg clk;
    reg imem_loader_we;
    reg [31:0] imem_loader_addr;
    reg [31:0] imem_loader_wdata;
    reg [31:0] imem_addr;
    wire [31:0] imem_rdata;

    reg dmem_loader_we;
    reg [31:0] dmem_loader_addr;
    reg [31:0] dmem_loader_wdata;
    reg dmem_read;
    reg [31:0] dmem_addr;
    wire [31:0] dmem_rdata;

    imem #(
        .IMEM_DEPTH(16),
        .IMEM_INIT_FILE("")
    ) u_imem (
        .clk(clk),
        .addr(imem_addr),
        .rdata(imem_rdata),
        .loader_we(imem_loader_we),
        .loader_addr(imem_loader_addr),
        .loader_wdata(imem_loader_wdata)
    );

    dmem #(
        .DMEM_DEPTH(16),
        .DMEM_BASE(32'h00010000),
        .DMEM_INIT_FILE(""),
        .SUPPORT_MISALIGNED(0)
    ) u_dmem (
        .clk(clk),
        .mem_read(dmem_read),
        .mem_write(1'b0),
        .byte_en(4'b0000),
        .addr(dmem_addr),
        .wdata(32'h00000000),
        .rdata(dmem_rdata),
        .debug_word0(),
        .debug_word1(),
        .debug_word2(),
        .debug_word3(),
        .debug_word4(),
        .debug_pass_word(),
        .debug_fail_word(),
        .debug_cycle_word(),
        .loader_we(dmem_loader_we),
        .loader_addr(dmem_loader_addr),
        .loader_wdata(dmem_loader_wdata)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        imem_loader_we = 1'b0;
        imem_loader_addr = 32'h00000000;
        imem_loader_wdata = 32'h00000000;
        imem_addr = 32'h00000000;
        dmem_loader_we = 1'b0;
        dmem_loader_addr = 32'h00010000;
        dmem_loader_wdata = 32'h00000000;
        dmem_read = 1'b0;
        dmem_addr = 32'h00010000;

        @(posedge clk);
        imem_loader_we = 1'b1;
        imem_loader_addr = 32'h00000004;
        imem_loader_wdata = 32'h12345678;
        dmem_loader_we = 1'b1;
        dmem_loader_addr = 32'h00010008;
        dmem_loader_wdata = 32'hdeadbeef;
        @(posedge clk);
        imem_loader_we = 1'b0;
        dmem_loader_we = 1'b0;

        imem_addr = 32'h00000004;
        dmem_addr = 32'h00010008;
        dmem_read = 1'b1;
        @(posedge clk);
        @(posedge clk);

        if (imem_rdata !== 32'h12345678) begin
            $display("FAIL loader memory ports: imem=%08x", imem_rdata);
            $finish;
        end
        if (dmem_rdata !== 32'hdeadbeef) begin
            $display("FAIL loader memory ports: dmem=%08x", dmem_rdata);
            $finish;
        end

        $display("PASS loader memory ports completed");
        $finish;
    end
endmodule
