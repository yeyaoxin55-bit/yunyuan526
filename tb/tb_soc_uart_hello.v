`timescale 1ns/1ps

module tb_soc_uart_hello;
    localparam UART_CLKS_PER_BIT = 4;

    reg sys_clk;
    reg sys_rst_n;
    reg uart_debug_key_n;
    reg uart_rx_pin;
    wire uart_tx_pin;
    wire over;
    wire succ;
    wire halted_ind;

    reg [7:0] ch0;
    reg [7:0] ch1;
    reg [7:0] ch2;
    integer wait_count;

    soc_top #(
        .IMEM_DEPTH(256),
        .DMEM_DEPTH(256),
        .IMEM_INIT_FILE("sw/uart_hello/uart_hello.hex"),
        .DMEM_INIT_FILE(""),
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .MUL_STAGES(1),
        .FAST_MUL(0),
        .BOOT_FROM_INIT(1)
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
            $display("FAIL soc_uart_hello: %0s", msg);
            $finish;
        end
    endtask

    task recv_byte;
        output [7:0] value;
        integer bit_index;
        begin
            @(negedge uart_tx_pin);
            wait_clocks(UART_CLKS_PER_BIT + (UART_CLKS_PER_BIT / 2));
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx_pin;
                wait_clocks(UART_CLKS_PER_BIT);
            end
            if (uart_tx_pin !== 1'b1) fail("UART stop bit was not high");
        end
    endtask

    initial begin
        sys_rst_n = 1'b0;
        uart_debug_key_n = 1'b1;
        uart_rx_pin = 1'b1;

        wait_clocks(6);
        sys_rst_n = 1'b1;

        recv_byte(ch0);
        recv_byte(ch1);
        recv_byte(ch2);

        if (ch0 !== 8'h48) begin
            $display("FAIL soc_uart_hello: first byte expected=48 actual=%02x", ch0);
            $finish;
        end
        if (ch1 !== 8'h49) begin
            $display("FAIL soc_uart_hello: second byte expected=49 actual=%02x", ch1);
            $finish;
        end
        if (ch2 !== 8'h0a) begin
            $display("FAIL soc_uart_hello: third byte expected=0a actual=%02x", ch2);
            $finish;
        end

        wait_count = 0;
        while (over !== 1'b1 && wait_count < 2000) begin
            wait_clocks(1);
            wait_count = wait_count + 1;
        end

        if (over !== 1'b1) fail("over did not assert");
        if (succ !== 1'b1) fail("succ did not assert");
        if (halted_ind !== 1'b0) fail("halted_ind is not tied low");

        $display("PASS soc_uart_hello completed");
        $finish;
    end
endmodule
