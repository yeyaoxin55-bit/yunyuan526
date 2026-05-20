module soc_top #(
    parameter XLEN = 32,
    parameter IMEM_DEPTH = 16384,
    parameter DMEM_DEPTH = 8192,
    parameter DMEM_BASE = 32'h00010000,
    parameter IMEM_INIT_FILE = "sw/uart_hello/uart_hello.hex",
    parameter DMEM_INIT_FILE = "",
    parameter UART_CLKS_PER_BIT = 868,
    parameter MUL_STAGES = 1,
    parameter FAST_MUL = 0,
    parameter ENABLE_LOAD_RESP_EX_FORWARD = 0,
    parameter ENABLE_LOAD_CONTROL_EARLY_REPLAY = 0,
    parameter ENABLE_ID_LOAD_EARLY_READ = 0,
    parameter BP_BHT_DEPTH = 64,
    parameter BP_BHR_WIDTH = 2,
    parameter BP_BTB_DEPTH = 32,
    parameter BP_LOCAL_HISTORY = 0,
    parameter DMEM_INIT_FILE_B0 = "",
    parameter DMEM_INIT_FILE_B1 = "",
    parameter DMEM_INIT_FILE_B2 = "",
    parameter DMEM_INIT_FILE_B3 = "",
    parameter SUPPORT_MISALIGNED_DMEM = 0,
    parameter BOOT_FROM_INIT = 1
) (
    input wire sys_clk,
    input wire sys_rst_n,
    input wire uart_debug_key_n,
    input wire uart_rx_pin,
    output wire uart_tx_pin,
    output wire over,
    output wire succ,
    output wire halted_ind
);
    localparam [31:0] UART_TXDATA_ADDR = 32'h00020000;
    localparam [31:0] UART_STATUS_ADDR = 32'h00020004;
    localparam [31:0] PASS_ADDR        = 32'h00020010;
    localparam [31:0] FAIL_ADDR        = 32'h00020014;
    localparam [31:0] CYCLE_ADDR       = 32'h00020018;
    localparam [31:0] DMEM_LIMIT       = DMEM_BASE + (DMEM_DEPTH * 4);

    wire raw_rst = ~sys_rst_n;
    wire clk;
    wire clk_locked;
    wire rst = raw_rst || !clk_locked;
    wire uart_debug_active = !uart_debug_key_n;

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;
    wire cpu_dmem_read;
    wire cpu_dmem_read_early;
    wire cpu_dmem_write;
    wire [3:0] cpu_dmem_byte_en;
    wire [31:0] cpu_dmem_addr;
    wire [31:0] cpu_dmem_wdata;
    wire [31:0] cpu_dmem_rdata;
    wire [31:0] dmem_rdata;
    wire loader_imem_we;
    wire [31:0] loader_imem_addr;
    wire [31:0] loader_imem_wdata;
    wire loader_dmem_we;
    wire [31:0] loader_dmem_addr;
    wire [31:0] loader_dmem_wdata;
    wire loader_start_cpu;
    reg loader_start_cpu_q;
    reg run_armed_q;
    wire [31:0] loader_error_count;
    wire loader_start_pulse = loader_start_cpu && !loader_start_cpu_q;
    wire cpu_rst = rst || !run_armed_q;
    wire cpu_dmem_arch_read = cpu_dmem_read && !cpu_dmem_read_early;

    wire dmem_sel = (cpu_dmem_addr >= DMEM_BASE) && (cpu_dmem_addr < DMEM_LIMIT);
    wire mmio_txdata_sel = (cpu_dmem_addr == UART_TXDATA_ADDR);
    wire mmio_status_sel = (cpu_dmem_addr == UART_STATUS_ADDR);
    wire mmio_pass_sel = (cpu_dmem_addr == PASS_ADDR);
    wire mmio_fail_sel = (cpu_dmem_addr == FAIL_ADDR);
    wire mmio_cycle_sel = (cpu_dmem_addr == CYCLE_ADDR);
    wire mmio_sel = mmio_txdata_sel || mmio_status_sel || mmio_pass_sel ||
                    mmio_fail_sel || mmio_cycle_sel;

    wire uart_ready;
    wire uart_busy;
    wire uart_tx_valid = cpu_dmem_write && mmio_txdata_sel && uart_ready;
    wire unused_board_inputs = loader_error_count[0];

    reg mmio_read_q;
    reg [31:0] mmio_rdata_q;
    reg [31:0] pass_reg;
    reg [31:0] fail_reg;
    reg [31:0] cycle_counter;
    reg [31:0] cycle_latched;

    clk_gen_50m_to_100m u_clk_gen (
        .clk_50m(sys_clk),
        .rst(raw_rst),
        .clk_100m(clk),
        .locked(clk_locked)
    );

    always @(posedge clk) begin
        if (rst) begin
            loader_start_cpu_q <= 1'b0;
            run_armed_q <= (BOOT_FROM_INIT != 0) && !uart_debug_active;
        end else begin
            loader_start_cpu_q <= loader_start_cpu;
            if (uart_debug_active) begin
                run_armed_q <= 1'b0;
            end else if (loader_start_pulse) begin
                run_armed_q <= 1'b1;
            end
        end
    end

    imem #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_INIT_FILE(IMEM_INIT_FILE)
    ) u_imem (
        .clk(clk),
        .addr(imem_addr),
        .rdata(imem_rdata),
        .loader_we(loader_imem_we),
        .loader_addr(loader_imem_addr),
        .loader_wdata(loader_imem_wdata)
    );

    dmem #(
        .DMEM_DEPTH(DMEM_DEPTH),
        .DMEM_BASE(DMEM_BASE),
        .DMEM_INIT_FILE(DMEM_INIT_FILE),
        .DMEM_INIT_FILE_B0(DMEM_INIT_FILE_B0),
        .DMEM_INIT_FILE_B1(DMEM_INIT_FILE_B1),
        .DMEM_INIT_FILE_B2(DMEM_INIT_FILE_B2),
        .DMEM_INIT_FILE_B3(DMEM_INIT_FILE_B3),
        .SUPPORT_MISALIGNED(SUPPORT_MISALIGNED_DMEM)
    ) u_dmem (
        .clk(clk),
        .mem_read(cpu_dmem_read && dmem_sel),
        .mem_write(cpu_dmem_write && dmem_sel),
        .byte_en(cpu_dmem_byte_en),
        .addr(cpu_dmem_addr),
        .wdata(cpu_dmem_wdata),
        .rdata(dmem_rdata),
        .debug_word0(),
        .debug_word1(),
        .debug_word2(),
        .debug_word3(),
        .debug_word4(),
        .debug_pass_word(),
        .debug_fail_word(),
        .debug_cycle_word(),
        .loader_we(loader_dmem_we),
        .loader_addr(loader_dmem_addr),
        .loader_wdata(loader_dmem_wdata)
    );

    uart #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .START_ON_RESET(BOOT_FROM_INIT)
    ) u_uart (
        .clk(clk),
        .rst(rst),
        .rx_i(uart_rx_pin),
        .tx_valid_i(uart_tx_valid),
        .tx_data_i(cpu_dmem_wdata[7:0]),
        .tx_ready_o(uart_ready),
        .tx_busy_o(uart_busy),
        .tx_o(uart_tx_pin),
        .rx_valid_o(),
        .rx_data_o(),
        .imem_we_o(loader_imem_we),
        .imem_addr_o(loader_imem_addr),
        .imem_wdata_o(loader_imem_wdata),
        .dmem_we_o(loader_dmem_we),
        .dmem_addr_o(loader_dmem_addr),
        .dmem_wdata_o(loader_dmem_wdata),
        .start_cpu_o(loader_start_cpu),
        .error_count_o(loader_error_count)
    );

    cpu_core #(
        .XLEN(XLEN),
        .ENABLE_LOAD_USE_STALL(1),
        .ENABLE_LOAD_RESP_EX_FORWARD(ENABLE_LOAD_RESP_EX_FORWARD),
        .ENABLE_LOAD_CONTROL_EARLY_REPLAY(ENABLE_LOAD_CONTROL_EARLY_REPLAY),
        .ENABLE_ID_LOAD_EARLY_READ(ENABLE_ID_LOAD_EARLY_READ),
        .MUL_STAGES(MUL_STAGES),
        .FAST_MUL(FAST_MUL),
        .BP_BHT_DEPTH(BP_BHT_DEPTH),
        .BP_BHR_WIDTH(BP_BHR_WIDTH),
        .BP_BTB_DEPTH(BP_BTB_DEPTH),
        .BP_LOCAL_HISTORY(BP_LOCAL_HISTORY)
    ) u_core (
        .clk(clk),
        .rst(cpu_rst),
        .imem_addr(imem_addr),
        .imem_rdata(imem_rdata),
        .dmem_read(cpu_dmem_read),
        .dmem_read_early(cpu_dmem_read_early),
        .dmem_write(cpu_dmem_write),
        .dmem_byte_en(cpu_dmem_byte_en),
        .dmem_addr(cpu_dmem_addr),
        .dmem_wdata(cpu_dmem_wdata),
        .dmem_rdata(cpu_dmem_rdata)
    );

    always @(posedge clk) begin
        if (rst) begin
            mmio_read_q <= 1'b0;
            mmio_rdata_q <= 32'h00000000;
            pass_reg <= 32'h00000000;
            fail_reg <= 32'h00000000;
            cycle_counter <= 32'h00000000;
            cycle_latched <= 32'h00000000;
        end else begin
            cycle_counter <= cycle_counter + 32'd1;
            mmio_read_q <= cpu_dmem_arch_read && mmio_sel;

            if (cpu_dmem_arch_read && mmio_sel) begin
                if (mmio_status_sel) begin
                    mmio_rdata_q <= {30'h00000000, uart_busy, uart_ready};
                end else if (mmio_pass_sel) begin
                    mmio_rdata_q <= pass_reg;
                end else if (mmio_fail_sel) begin
                    mmio_rdata_q <= fail_reg;
                end else if (mmio_cycle_sel) begin
                    mmio_rdata_q <= cycle_latched;
                end
            end

            if (cpu_dmem_write && mmio_pass_sel) begin
                pass_reg <= cpu_dmem_wdata;
                cycle_latched <= cycle_counter;
            end
            if (cpu_dmem_write && mmio_fail_sel) begin
                fail_reg <= cpu_dmem_wdata;
                cycle_latched <= cycle_counter;
            end
        end
    end

    assign cpu_dmem_rdata = mmio_read_q ? mmio_rdata_q : dmem_rdata;
    assign over = (pass_reg != 32'h00000000) || (fail_reg != 32'h00000000);
    assign succ = (pass_reg != 32'h00000000);
    assign halted_ind = unused_board_inputs & 1'b0;
endmodule
