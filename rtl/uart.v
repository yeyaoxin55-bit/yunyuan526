module uart #(
    parameter CLKS_PER_BIT = 434,
    parameter START_ON_RESET = 1
) (
    input wire clk,
    input wire rst,
    input wire rx_i,
    input wire tx_valid_i,
    input wire [7:0] tx_data_i,
    output wire tx_ready_o,
    output wire tx_busy_o,
    output wire tx_o,
    output reg rx_valid_o,
    output reg [7:0] rx_data_o,
    output reg imem_we_o,
    output reg [31:0] imem_addr_o,
    output reg [31:0] imem_wdata_o,
    output reg dmem_we_o,
    output reg [31:0] dmem_addr_o,
    output reg [31:0] dmem_wdata_o,
    output reg start_cpu_o,
    output reg [31:0] error_count_o
);
    localparam [1:0] TX_IDLE  = 2'd0;
    localparam [1:0] TX_START = 2'd1;
    localparam [1:0] TX_DATA  = 2'd2;
    localparam [1:0] TX_STOP  = 2'd3;

    localparam [1:0] RX_IDLE  = 2'd0;
    localparam [1:0] RX_START = 2'd1;
    localparam [1:0] RX_DATA  = 2'd2;
    localparam [1:0] RX_STOP  = 2'd3;

    localparam CMD_WRITE_IMEM = 8'h01;
    localparam CMD_WRITE_DMEM = 8'h02;
    localparam CMD_START      = 8'h03;

    localparam LD_MAGIC    = 3'd0;
    localparam LD_CMD      = 3'd1;
    localparam LD_ADDR     = 3'd2;
    localparam LD_COUNT    = 3'd3;
    localparam LD_PAYLOAD  = 3'd4;
    localparam LD_CHECKSUM = 3'd5;

    reg [1:0] tx_state;
    reg [31:0] tx_clk_count;
    reg [2:0] tx_bit_index;
    reg [7:0] tx_data_q;
    reg tx_q;

    reg [1:0] rx_state;
    reg [31:0] rx_clk_count;
    reg [2:0] rx_bit_index;
    reg [7:0] rx_data_q;

    reg [2:0] ld_state;
    reg [1:0] ld_magic_index;
    reg [7:0] ld_cmd_q;
    reg [31:0] ld_addr_q;
    reg [31:0] ld_count_q;
    reg [31:0] ld_word_index_q;
    reg [31:0] ld_payload_word_q;
    reg [1:0] ld_field_index;
    reg [1:0] ld_payload_index;
    reg [7:0] ld_checksum_q;

    wire [7:0] ld_expected_magic =
        (ld_magic_index == 2'd0) ? 8'h59 :
        (ld_magic_index == 2'd1) ? 8'h4c :
        (ld_magic_index == 2'd2) ? 8'h33 :
                                   8'h4c;

    assign tx_ready_o = (tx_state == TX_IDLE);
    assign tx_busy_o = (tx_state != TX_IDLE);
    assign tx_o = tx_q;

    task reset_loader_packet;
        begin
            ld_state <= LD_MAGIC;
            ld_magic_index <= 2'd0;
            ld_cmd_q <= 8'h00;
            ld_addr_q <= 32'h00000000;
            ld_count_q <= 32'h00000000;
            ld_word_index_q <= 32'h00000000;
            ld_payload_word_q <= 32'h00000000;
            ld_field_index <= 2'd0;
            ld_payload_index <= 2'd0;
            ld_checksum_q <= 8'h00;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            tx_state <= TX_IDLE;
            tx_clk_count <= 32'd0;
            tx_bit_index <= 3'd0;
            tx_data_q <= 8'h00;
            tx_q <= 1'b1;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    tx_q <= 1'b1;
                    tx_clk_count <= 32'd0;
                    tx_bit_index <= 3'd0;
                    if (tx_valid_i) begin
                        tx_data_q <= tx_data_i;
                        tx_q <= 1'b0;
                        tx_state <= TX_START;
                    end
                end

                TX_START: begin
                    tx_q <= 1'b0;
                    if (tx_clk_count == (CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= 32'd0;
                        tx_bit_index <= 3'd0;
                        tx_q <= tx_data_q[0];
                        tx_state <= TX_DATA;
                    end else begin
                        tx_clk_count <= tx_clk_count + 32'd1;
                    end
                end

                TX_DATA: begin
                    if (tx_clk_count == (CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= 32'd0;
                        if (tx_bit_index == 3'd7) begin
                            tx_bit_index <= 3'd0;
                            tx_q <= 1'b1;
                            tx_state <= TX_STOP;
                        end else begin
                            tx_bit_index <= tx_bit_index + 3'd1;
                            tx_q <= tx_data_q[tx_bit_index + 3'd1];
                        end
                    end else begin
                        tx_clk_count <= tx_clk_count + 32'd1;
                    end
                end

                default: begin
                    tx_q <= 1'b1;
                    if (tx_clk_count == (CLKS_PER_BIT - 1)) begin
                        tx_clk_count <= 32'd0;
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_clk_count <= tx_clk_count + 32'd1;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            rx_state <= RX_IDLE;
            rx_clk_count <= 32'd0;
            rx_bit_index <= 3'd0;
            rx_data_q <= 8'h00;
            rx_data_o <= 8'h00;
            rx_valid_o <= 1'b0;
        end else begin
            rx_valid_o <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_clk_count <= 32'd0;
                    rx_bit_index <= 3'd0;
                    if (!rx_i) begin
                        rx_state <= RX_START;
                    end
                end

                RX_START: begin
                    if (rx_clk_count == ((CLKS_PER_BIT / 2) - 1)) begin
                        rx_clk_count <= 32'd0;
                        if (!rx_i) begin
                            rx_state <= RX_DATA;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 32'd1;
                    end
                end

                RX_DATA: begin
                    if (rx_clk_count == (CLKS_PER_BIT - 1)) begin
                        rx_clk_count <= 32'd0;
                        rx_data_q[rx_bit_index] <= rx_i;
                        if (rx_bit_index == 3'd7) begin
                            rx_bit_index <= 3'd0;
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_index <= rx_bit_index + 3'd1;
                        end
                    end else begin
                        rx_clk_count <= rx_clk_count + 32'd1;
                    end
                end

                default: begin
                    if (rx_clk_count == (CLKS_PER_BIT - 1)) begin
                        rx_clk_count <= 32'd0;
                        if (rx_i) begin
                            rx_data_o <= rx_data_q;
                            rx_valid_o <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_clk_count <= rx_clk_count + 32'd1;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            reset_loader_packet();
            imem_we_o <= 1'b0;
            imem_addr_o <= 32'h00000000;
            imem_wdata_o <= 32'h00000000;
            dmem_we_o <= 1'b0;
            dmem_addr_o <= 32'h00000000;
            dmem_wdata_o <= 32'h00000000;
            start_cpu_o <= (START_ON_RESET != 0);
            error_count_o <= 32'h00000000;
        end else begin
            imem_we_o <= 1'b0;
            dmem_we_o <= 1'b0;

            if (rx_valid_o) begin
                case (ld_state)
                    LD_MAGIC: begin
                        if (rx_data_o == ld_expected_magic) begin
                            if (ld_magic_index == 2'd3) begin
                                ld_state <= LD_CMD;
                                ld_magic_index <= 2'd0;
                            end else begin
                                ld_magic_index <= ld_magic_index + 2'd1;
                            end
                        end else begin
                            ld_magic_index <= (rx_data_o == 8'h59) ? 2'd1 : 2'd0;
                        end
                    end

                    LD_CMD: begin
                        ld_cmd_q <= rx_data_o;
                        ld_checksum_q <= rx_data_o;
                        ld_addr_q <= 32'h00000000;
                        ld_field_index <= 2'd0;
                        ld_state <= LD_ADDR;
                    end

                    LD_ADDR: begin
                        ld_addr_q <= {ld_addr_q[23:0], rx_data_o};
                        ld_checksum_q <= ld_checksum_q + rx_data_o;
                        if (ld_field_index == 2'd3) begin
                            ld_field_index <= 2'd0;
                            ld_count_q <= 32'h00000000;
                            ld_state <= LD_COUNT;
                        end else begin
                            ld_field_index <= ld_field_index + 2'd1;
                        end
                    end

                    LD_COUNT: begin
                        ld_count_q <= {ld_count_q[23:0], rx_data_o};
                        ld_checksum_q <= ld_checksum_q + rx_data_o;
                        if (ld_field_index == 2'd3) begin
                            ld_field_index <= 2'd0;
                            ld_word_index_q <= 32'h00000000;
                            ld_payload_index <= 2'd0;
                            ld_payload_word_q <= 32'h00000000;
                            if ({ld_count_q[23:0], rx_data_o} == 32'h00000000) begin
                                ld_state <= LD_CHECKSUM;
                            end else begin
                                ld_state <= LD_PAYLOAD;
                            end
                        end else begin
                            ld_field_index <= ld_field_index + 2'd1;
                        end
                    end

                    LD_PAYLOAD: begin
                        ld_payload_word_q <= {ld_payload_word_q[23:0], rx_data_o};
                        ld_checksum_q <= ld_checksum_q + rx_data_o;
                        if (ld_payload_index == 2'd3) begin
                            if (ld_cmd_q == CMD_WRITE_IMEM) begin
                                imem_we_o <= 1'b1;
                                imem_addr_o <= ld_addr_q + (ld_word_index_q << 2);
                                imem_wdata_o <= {ld_payload_word_q[23:0], rx_data_o};
                            end else if (ld_cmd_q == CMD_WRITE_DMEM) begin
                                dmem_we_o <= 1'b1;
                                dmem_addr_o <= ld_addr_q + (ld_word_index_q << 2);
                                dmem_wdata_o <= {ld_payload_word_q[23:0], rx_data_o};
                            end

                            ld_payload_index <= 2'd0;
                            ld_payload_word_q <= 32'h00000000;
                            if ((ld_word_index_q + 32'd1) == ld_count_q) begin
                                ld_state <= LD_CHECKSUM;
                            end
                            ld_word_index_q <= ld_word_index_q + 32'd1;
                        end else begin
                            ld_payload_index <= ld_payload_index + 2'd1;
                        end
                    end

                    LD_CHECKSUM: begin
                        if (rx_data_o == ld_checksum_q) begin
                            if (ld_cmd_q == CMD_START) begin
                                start_cpu_o <= 1'b1;
                            end else if ((ld_cmd_q != CMD_WRITE_IMEM) && (ld_cmd_q != CMD_WRITE_DMEM)) begin
                                error_count_o <= error_count_o + 32'd1;
                            end
                        end else begin
                            error_count_o <= error_count_o + 32'd1;
                        end
                        reset_loader_packet();
                    end

                    default: begin
                        reset_loader_packet();
                    end
                endcase
            end
        end
    end
endmodule
