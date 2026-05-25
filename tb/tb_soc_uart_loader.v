`timescale 1ns/1ps

module tb_soc_uart_loader;
    localparam UART_CLKS_PER_BIT = 4;
    localparam CMD_WRITE_IMEM = 8'h01;
    localparam CMD_START      = 8'h03;

    reg sys_clk;
    reg sys_rst_n;
    reg uart_debug_key_n;
    reg uart_rx_pin;
    wire uart_tx_pin;
    wire over;
    wire succ;
    wire halted_ind;

    integer wait_count;

    soc_top #(
        .XLEN(32),
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE(""),
        .DMEM_INIT_FILE(""),
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .MUL_STAGES(1),
        .FAST_MUL(0),
        .BOOT_FROM_INIT(0)
    ) dut (
        .sys_clk(sys_clk),
        .sys_rst_n(sys_rst_n),
        .uart_debug_key_n(uart_debug_key_n),
        .uart_rx_pin(uart_rx_pin),
        .uart_tx_pin(uart_tx_pin),
        .over(over),
        .succ(succ),
        .halted_ind(halted_ind)
    );

    initial begin
        sys_clk = 1'b0;
        forever #5 sys_clk = ~sys_clk;
    end

    task wait_clocks;
        input integer count;
        integer n;
        begin
            for (n = 0; n < count; n = n + 1) begin
                @(posedge sys_clk);
            end
        end
    endtask

    task fail;
        input [1023:0] msg;
        begin
            $display("FAIL soc_uart_loader: %0s", msg);
            $finish;
        end
    endtask

    task send_uart_byte;
        input [7:0] value;
        integer bit_index;
        begin
            uart_rx_pin = 1'b0;
            wait_clocks(UART_CLKS_PER_BIT);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_pin = value[bit_index];
                wait_clocks(UART_CLKS_PER_BIT);
            end
            uart_rx_pin = 1'b1;
            wait_clocks(UART_CLKS_PER_BIT);
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

    task send_write_imem_packet;
        input [31:0] addr;
        input [31:0] data;
        reg [7:0] sum;
        begin
            sum = CMD_WRITE_IMEM +
                  addr[31:24] + addr[23:16] + addr[15:8] + addr[7:0] +
                  8'h00 + 8'h00 + 8'h00 + 8'h01 +
                  data[31:24] + data[23:16] + data[15:8] + data[7:0];
            send_magic();
            send_uart_byte(CMD_WRITE_IMEM);
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

    initial begin
        sys_rst_n = 1'b0;
        uart_debug_key_n = 1'b1;
        uart_rx_pin = 1'b1;

        wait_clocks(6);
        sys_rst_n = 1'b1;
        wait_clocks(8);

        if (over !== 1'b0 || succ !== 1'b0) fail("CPU started before START packet");

        send_write_imem_packet(32'h00000000, 32'h00020137);
        send_write_imem_packet(32'h00000004, 32'h00100193);
        send_write_imem_packet(32'h00000008, 32'h00312823);
        send_write_imem_packet(32'h0000000c, 32'h0000006f);
        send_start_packet();

        wait_count = 0;
        while (over !== 1'b1 && wait_count < 2000) begin
            wait_clocks(1);
            wait_count = wait_count + 1;
        end

        if (over !== 1'b1) fail("over did not assert after UART-loaded program");
        if (succ !== 1'b1) fail("succ did not assert after UART-loaded program");
        if (halted_ind !== 1'b0) fail("halted_ind is not tied low");

        $display("PASS soc_uart_loader completed");
        $finish;
    end
endmodule
