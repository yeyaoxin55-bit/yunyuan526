`timescale 1ns/1ps

module tb_uart_loader;
    localparam CLKS_PER_BIT = 4;
    localparam CMD_WRITE_IMEM = 8'h01;
    localparam CMD_WRITE_DMEM = 8'h02;
    localparam CMD_START      = 8'h03;

    reg clk;
    reg rst;
    reg rx_i;
    wire imem_we_o;
    wire [31:0] imem_addr_o;
    wire [31:0] imem_wdata_o;
    wire dmem_we_o;
    wire [31:0] dmem_addr_o;
    wire [31:0] dmem_wdata_o;
    wire start_cpu_o;
    wire [31:0] error_count_o;

    reg saw_imem;
    reg saw_dmem;

    uart #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .START_ON_RESET(0)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_i(rx_i),
        .tx_valid_i(1'b0),
        .tx_data_i(8'h00),
        .tx_ready_o(),
        .tx_busy_o(),
        .tx_o(),
        .rx_valid_o(),
        .rx_data_o(),
        .imem_we_o(imem_we_o),
        .imem_addr_o(imem_addr_o),
        .imem_wdata_o(imem_wdata_o),
        .dmem_we_o(dmem_we_o),
        .dmem_addr_o(dmem_addr_o),
        .dmem_wdata_o(dmem_wdata_o),
        .start_cpu_o(start_cpu_o),
        .error_count_o(error_count_o)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task wait_clocks;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task send_uart_byte;
        input [7:0] value;
        integer bit_index;
        begin
            rx_i = 1'b0;
            wait_clocks(CLKS_PER_BIT);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                rx_i = value[bit_index];
                wait_clocks(CLKS_PER_BIT);
            end
            rx_i = 1'b1;
            wait_clocks(CLKS_PER_BIT);
            wait_clocks(1);
        end
    endtask

    task send_magic;
        begin
            send_uart_byte(8'h59);
            send_uart_byte(8'h4c);
            send_uart_byte(8'h33);
            send_uart_byte(8'h4c);
        end
    endtask

    task send_write_packet;
        input [7:0] cmd;
        input [31:0] addr;
        input [31:0] data;
        reg [7:0] sum;
        begin
            sum = cmd +
                  addr[31:24] + addr[23:16] + addr[15:8] + addr[7:0] +
                  8'h00 + 8'h00 + 8'h00 + 8'h01 +
                  data[31:24] + data[23:16] + data[15:8] + data[7:0];
            send_magic();
            send_uart_byte(cmd);
            send_uart_byte(addr[31:24]);
            send_uart_byte(addr[23:16]);
            send_uart_byte(addr[15:8]);
            send_uart_byte(addr[7:0]);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h01);
            send_uart_byte(data[31:24]);
            send_uart_byte(data[23:16]);
            send_uart_byte(data[15:8]);
            send_uart_byte(data[7:0]);
            send_uart_byte(sum);
        end
    endtask

    task send_start_packet;
        reg [7:0] sum;
        begin
            sum = CMD_START;
            send_magic();
            send_uart_byte(CMD_START);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(8'h00);
            send_uart_byte(sum);
        end
    endtask

    always @(posedge clk) begin
        if (imem_we_o) begin
            if (imem_addr_o !== 32'h00000004 || imem_wdata_o !== 32'h12345678) begin
                $display("FAIL uart_loader: imem addr=%08x data=%08x", imem_addr_o, imem_wdata_o);
                $finish;
            end
            saw_imem <= 1'b1;
        end
        if (dmem_we_o) begin
            if (dmem_addr_o !== 32'h00010008 || dmem_wdata_o !== 32'hdeadbeef) begin
                $display("FAIL uart_loader: dmem addr=%08x data=%08x", dmem_addr_o, dmem_wdata_o);
                $finish;
            end
            saw_dmem <= 1'b1;
        end
    end

    initial begin
        rst = 1'b1;
        rx_i = 1'b1;
        saw_imem = 1'b0;
        saw_dmem = 1'b0;
        repeat (4) @(posedge clk);
        rst = 1'b0;
        repeat (4) @(posedge clk);

        send_write_packet(CMD_WRITE_IMEM, 32'h00000004, 32'h12345678);
        send_write_packet(CMD_WRITE_DMEM, 32'h00010008, 32'hdeadbeef);
        send_start_packet();
        repeat (8) @(posedge clk);

        if (!saw_imem) begin
            $display("FAIL uart_loader: missing imem write");
            $finish;
        end
        if (!saw_dmem) begin
            $display("FAIL uart_loader: missing dmem write");
            $finish;
        end
        if (!start_cpu_o) begin
            $display("FAIL uart_loader: start_cpu_o not set");
            $finish;
        end
        if (error_count_o !== 32'h00000000) begin
            $display("FAIL uart_loader: error_count=%08x", error_count_o);
            $finish;
        end

        $display("PASS uart_loader protocol completed");
        $finish;
    end
endmodule
