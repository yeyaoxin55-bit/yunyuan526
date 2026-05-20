module imem #(
    parameter IMEM_DEPTH = 16384,
    parameter IMEM_INIT_FILE = ""
) (
    input wire clk,
    input wire [31:0] addr,
    output reg [31:0] rdata,
    input wire loader_we,
    input wire [31:0] loader_addr,
    input wire [31:0] loader_wdata
);
    reg [31:0] mem [0:IMEM_DEPTH-1];
    integer i;

    initial begin
        rdata = 32'h00000013;
        for (i = 0; i < IMEM_DEPTH; i = i + 1) begin
            mem[i] = 32'h00000013;
        end
        if (IMEM_INIT_FILE != "") begin
            $readmemh(IMEM_INIT_FILE, mem);
        end
    end

    always @(posedge clk) begin
        if (loader_we && (loader_addr[31:2] < IMEM_DEPTH)) begin
            mem[loader_addr[31:2]] <= loader_wdata;
        end
        rdata <= mem[addr[31:2]];
    end
endmodule
