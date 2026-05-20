module axi4lite_if (
    input wire aclk,
    input wire aresetn,
    input wire [31:0] awaddr,
    input wire awvalid,
    output wire awready,
    input wire [31:0] wdata,
    input wire [3:0] wstrb,
    input wire wvalid,
    output wire wready,
    output wire [1:0] bresp,
    output wire bvalid,
    input wire bready,
    input wire [31:0] araddr,
    input wire arvalid,
    output wire arready,
    output wire [31:0] rdata,
    output wire [1:0] rresp,
    output wire rvalid,
    input wire rready
);
    assign awready = awvalid;
    assign wready = wvalid;
    assign bresp = 2'b00;
    assign bvalid = awvalid & wvalid;
    assign arready = arvalid;
    assign rdata = 32'h00000000;
    assign rresp = 2'b00;
    assign rvalid = arvalid;
endmodule
