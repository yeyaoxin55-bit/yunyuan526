`timescale 1ns/1ps

module tb_uart_tx;
    localparam CLKS_PER_BIT = 4;

    reg clk;
    reg rst;
    reg valid_i;
    reg [7:0] data_i;
    wire ready_o;
    wire busy_o;
    wire tx_o;

    integer i;

    uart #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .START_ON_RESET(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_i(1'b1),
        .tx_valid_i(valid_i),
        .tx_data_i(data_i),
        .tx_ready_o(ready_o),
        .tx_busy_o(busy_o),
        .tx_o(tx_o),
        .rx_valid_o(),
        .rx_data_o(),
        .imem_we_o(),
        .imem_addr_o(),
        .imem_wdata_o(),
        .dmem_we_o(),
        .dmem_addr_o(),
        .dmem_wdata_o(),
        .start_cpu_o(),
        .error_count_o()
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

    task fail;
        input [1023:0] msg;
        begin
            $display("FAIL uart_tx: %0s", msg);
            $finish;
        end
    endtask

    initial begin
        rst = 1'b1;
        valid_i = 1'b0;
        data_i = 8'h00;

        wait_clocks(3);
        rst = 1'b0;
        wait_clocks(2);

        if (tx_o !== 1'b1) fail("idle tx_o is not high");
        if (ready_o !== 1'b1) fail("ready_o is not high after reset");
        if (busy_o !== 1'b0) fail("busy_o is not low after reset");

        @(negedge clk);
        data_i = 8'ha5;
        valid_i = 1'b1;
        @(negedge clk);
        valid_i = 1'b0;

        wait (busy_o === 1'b1);
        wait (tx_o === 1'b0);
        if (ready_o !== 1'b0) fail("ready_o stayed high during transmit");

        wait_clocks(CLKS_PER_BIT + (CLKS_PER_BIT / 2));
        for (i = 0; i < 8; i = i + 1) begin
            if (tx_o !== data_i[i]) begin
                $display("FAIL uart_tx: data bit %0d expected=%b actual=%b", i, data_i[i], tx_o);
                $finish;
            end
            wait_clocks(CLKS_PER_BIT);
        end

        if (tx_o !== 1'b1) fail("stop bit is not high");
        wait_clocks(CLKS_PER_BIT);
        if (ready_o !== 1'b1) fail("ready_o did not return high");
        if (busy_o !== 1'b0) fail("busy_o did not return low");

        $display("PASS uart_tx frame completed");
        $finish;
    end
endmodule
