module dmem #(
    parameter DMEM_DEPTH = 8192,
    parameter DMEM_BASE = 32'h00000000,
    parameter DMEM_INIT_FILE = "",
    parameter DMEM_INIT_FILE_B0 = "",
    parameter DMEM_INIT_FILE_B1 = "",
    parameter DMEM_INIT_FILE_B2 = "",
    parameter DMEM_INIT_FILE_B3 = "",
    parameter SUPPORT_MISALIGNED = 1
) (
    input wire clk,
    input wire mem_read,
    input wire mem_write,
    input wire [3:0] byte_en,
    input wire [31:0] addr,
    input wire [31:0] wdata,
    output wire [31:0] rdata,
    output wire [31:0] debug_word0,
    output wire [31:0] debug_word1,
    output wire [31:0] debug_word2,
    output wire [31:0] debug_word3,
    output wire [31:0] debug_word4,
    output wire [31:0] debug_pass_word,
    output wire [31:0] debug_fail_word,
    output wire [31:0] debug_cycle_word,
    input wire loader_we,
    input wire [31:0] loader_addr,
    input wire [31:0] loader_wdata
);
    reg [31:0] mem [0:DMEM_DEPTH-1];
    localparam [31:0] PASS_INDEX = (32'h00017ff0 - DMEM_BASE) >> 2;
    localparam [31:0] FAIL_INDEX = (32'h00017ff4 - DMEM_BASE) >> 2;
    localparam [31:0] CYCLE_INDEX = (32'h00017ff8 - DMEM_BASE) >> 2;
    wire [31:0] word_index = (addr - DMEM_BASE) >> 2;
    wire [31:0] loader_word_index = (loader_addr - DMEM_BASE) >> 2;
    wire [1:0] byte_offset = addr[1:0];
    wire [3:0] aligned_byte_en = byte_en << byte_offset;
    wire [31:0] aligned_wdata = wdata << (8 * byte_offset);
    integer i;
    integer j;
    reg [31:0] write_addr;
    reg [31:0] write_index;
    reg [1:0] write_offset;
    reg [31:0] debug_word0_r;
    reg [31:0] debug_word1_r;
    reg [31:0] debug_word2_r;
    reg [31:0] debug_word3_r;
    reg [31:0] debug_word4_r;
    reg [31:0] debug_pass_word_r;
    reg [31:0] debug_fail_word_r;
    reg [31:0] debug_cycle_word_r;

    task update_debug_byte;
        input [31:0] index;
        input [1:0] offset;
        input [7:0] value;
        reg [31:0] next_word0;
        reg [31:0] next_word1;
        reg [31:0] next_word2;
        reg [31:0] next_word3;
        reg [31:0] next_word4;
        reg [31:0] next_pass_word;
        reg [31:0] next_fail_word;
        reg [31:0] next_cycle_word;
        begin
            next_word0 = debug_word0_r;
            next_word1 = debug_word1_r;
            next_word2 = debug_word2_r;
            next_word3 = debug_word3_r;
            next_word4 = debug_word4_r;
            next_pass_word = debug_pass_word_r;
            next_fail_word = debug_fail_word_r;
            next_cycle_word = debug_cycle_word_r;

            case (offset)
                2'd0: begin
                    next_word0[7:0] = value; next_word1[7:0] = value; next_word2[7:0] = value; next_word3[7:0] = value; next_word4[7:0] = value;
                    next_pass_word[7:0] = value; next_fail_word[7:0] = value; next_cycle_word[7:0] = value;
                end
                2'd1: begin
                    next_word0[15:8] = value; next_word1[15:8] = value; next_word2[15:8] = value; next_word3[15:8] = value; next_word4[15:8] = value;
                    next_pass_word[15:8] = value; next_fail_word[15:8] = value; next_cycle_word[15:8] = value;
                end
                2'd2: begin
                    next_word0[23:16] = value; next_word1[23:16] = value; next_word2[23:16] = value; next_word3[23:16] = value; next_word4[23:16] = value;
                    next_pass_word[23:16] = value; next_fail_word[23:16] = value; next_cycle_word[23:16] = value;
                end
                default: begin
                    next_word0[31:24] = value; next_word1[31:24] = value; next_word2[31:24] = value; next_word3[31:24] = value; next_word4[31:24] = value;
                    next_pass_word[31:24] = value; next_fail_word[31:24] = value; next_cycle_word[31:24] = value;
                end
            endcase

            if (index == 32'd0) debug_word0_r = next_word0;
            if (index == 32'd1) debug_word1_r = next_word1;
            if (index == 32'd2) debug_word2_r = next_word2;
            if (index == 32'd3) debug_word3_r = next_word3;
            if (index == 32'd4) debug_word4_r = next_word4;
            if (index == PASS_INDEX) debug_pass_word_r = next_pass_word;
            if (index == FAIL_INDEX) debug_fail_word_r = next_fail_word;
            if (index == CYCLE_INDEX) debug_cycle_word_r = next_cycle_word;
        end
    endtask

    initial begin
        for (i = 0; i < DMEM_DEPTH; i = i + 1) begin
            mem[i] = 32'h00000000;
        end
        if (DMEM_INIT_FILE != "") begin
            $readmemh(DMEM_INIT_FILE, mem);
        end
        debug_word0_r = 32'h00000000;
        debug_word1_r = 32'h00000000;
        debug_word2_r = 32'h00000000;
        debug_word3_r = 32'h00000000;
        debug_word4_r = 32'h00000000;
        debug_pass_word_r = 32'h00000000;
        debug_fail_word_r = 32'h00000000;
        debug_cycle_word_r = 32'h00000000;
    end

    generate
        if (SUPPORT_MISALIGNED != 0) begin : gen_misaligned
            wire [63:0] read_window = {((word_index + 1) < DMEM_DEPTH) ? mem[word_index + 1] : 32'h00000000,
                                       (word_index < DMEM_DEPTH) ? mem[word_index] : 32'h00000000};
            wire [63:0] shifted_read_window = read_window >> (8 * byte_offset);
            reg [31:0] rdata_q;
            assign rdata = rdata_q;

            always @(posedge clk) begin
                if (mem_read) begin
                    rdata_q <= shifted_read_window[31:0];
                end else begin
                    rdata_q <= 32'h00000000;
                end

                if (loader_we && (loader_word_index < DMEM_DEPTH)) begin
                    mem[loader_word_index] <= loader_wdata;
                    update_debug_byte(loader_word_index, 2'd0, loader_wdata[7:0]);
                    update_debug_byte(loader_word_index, 2'd1, loader_wdata[15:8]);
                    update_debug_byte(loader_word_index, 2'd2, loader_wdata[23:16]);
                    update_debug_byte(loader_word_index, 2'd3, loader_wdata[31:24]);
                end else if (mem_write) begin
                    for (j = 0; j < 4; j = j + 1) begin
                        if (byte_en[j]) begin
                            write_addr = (addr - DMEM_BASE) + j;
                            write_index = write_addr >> 2;
                            write_offset = write_addr[1:0];
                            if (write_index < DMEM_DEPTH) begin
                                case (write_offset)
                                    2'd0: mem[write_index][7:0]   <= wdata[(8 * j) +: 8];
                                    2'd1: mem[write_index][15:8]  <= wdata[(8 * j) +: 8];
                                    2'd2: mem[write_index][23:16] <= wdata[(8 * j) +: 8];
                                    2'd3: mem[write_index][31:24] <= wdata[(8 * j) +: 8];
                                endcase
                                update_debug_byte(write_index, write_offset, wdata[(8 * j) +: 8]);
                            end
                        end
                    end
                end
            end
        end else begin : gen_bram_friendly
            (* ram_style = "block" *) reg [31:0] mem_bram [0:DMEM_DEPTH-1];
            reg [31:0] read_word_q;
            reg [1:0] read_offset_q;
            wire bram_write = loader_we || mem_write;
            wire [31:0] bram_write_index = loader_we ? loader_word_index : word_index;
            wire [3:0] bram_write_be = loader_we ? 4'b1111 : aligned_byte_en;
            wire [31:0] bram_write_data = loader_we ? loader_wdata : aligned_wdata;
            integer k;
            assign rdata = read_word_q >> (8 * read_offset_q);

            initial begin
                read_word_q = 32'h00000000;
                read_offset_q = 2'd0;
                for (k = 0; k < DMEM_DEPTH; k = k + 1) begin
                    mem_bram[k] = 32'h00000000;
                end
                if (DMEM_INIT_FILE != "") begin
                    $readmemh(DMEM_INIT_FILE, mem_bram);
                end
            end

            always @(posedge clk) begin
                if (mem_read && (word_index < DMEM_DEPTH)) begin
                    read_word_q <= mem_bram[word_index];
                    read_offset_q <= byte_offset;
                end

                if (bram_write && (bram_write_index < DMEM_DEPTH)) begin
                    if (bram_write_be[0]) mem_bram[bram_write_index][7:0] <= bram_write_data[7:0];
                    if (bram_write_be[1]) mem_bram[bram_write_index][15:8] <= bram_write_data[15:8];
                    if (bram_write_be[2]) mem_bram[bram_write_index][23:16] <= bram_write_data[23:16];
                    if (bram_write_be[3]) mem_bram[bram_write_index][31:24] <= bram_write_data[31:24];
                    if (bram_write_be[0]) update_debug_byte(bram_write_index, 2'd0, bram_write_data[7:0]);
                    if (bram_write_be[1]) update_debug_byte(bram_write_index, 2'd1, bram_write_data[15:8]);
                    if (bram_write_be[2]) update_debug_byte(bram_write_index, 2'd2, bram_write_data[23:16]);
                    if (bram_write_be[3]) update_debug_byte(bram_write_index, 2'd3, bram_write_data[31:24]);
                end
            end
        end
    endgenerate

    assign debug_word0 = debug_word0_r;
    assign debug_word1 = debug_word1_r;
    assign debug_word2 = debug_word2_r;
    assign debug_word3 = debug_word3_r;
    assign debug_word4 = debug_word4_r;
    assign debug_pass_word = debug_pass_word_r;
    assign debug_fail_word = debug_fail_word_r;
    assign debug_cycle_word = debug_cycle_word_r;
endmodule
