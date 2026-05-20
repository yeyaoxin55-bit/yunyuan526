`timescale 1ns/1ps

module tb_uart_rx;
    localparam CLKS_PER_BIT = 4;

    reg clk;
    reg rst;
    reg rx_i;
    wire valid_o;
    wire [7:0] data_o;

    uart #(
        .CLKS_PER_BIT(CLKS_PER_BIT),
        .START_ON_RESET(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rx_i(rx_i),
        .tx_valid_i(1'b0),
        .tx_data_i(8'h00),
        .tx_ready_o(),
        .tx_busy_o(),
        .tx_o(),
        .rx_valid_o(valid_o),
        .rx_data_o(data_o),
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
        integer i;
        begin
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk);
            end
        end
    endtask

    task send_byte;
        input [7:0] value;
        integer i;
        begin
            rx_i = 1'b0;
            wait_clocks(CLKS_PER_BIT);
            for (i = 0; i < 8; i = i + 1) begin
                rx_i = value[i];
                wait_clocks(CLKS_PER_BIT);
            end
            rx_i = 1'b1;
            wait_clocks(CLKS_PER_BIT);
        end
    endtask

    initial begin
        rst = 1'b1;
        rx_i = 1'b1;
        wait_clocks(4);
        rst = 1'b0;
        wait_clocks(4);

        fork
            begin
                send_byte(8'hA5);
            end
            begin : monitor
                repeat (64) begin
                    @(posedge clk);
                    if (valid_o) begin
                        if (data_o !== 8'hA5) begin
                            $display("FAIL uart_rx: expected a5 actual=%02x", data_o);
                            $finish;
                        end
                        $display("PASS uart_rx frame completed");
                        $finish;
                    end
                end
                $display("FAIL uart_rx: valid_o did not assert");
                $finish;
            end
        join
    end
endmodule
