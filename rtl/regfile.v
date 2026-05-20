module regfile #(
    parameter XLEN = 32
) (
    input wire clk,
    input wire rst,
    input wire we,
    input wire [4:0] waddr,
    input wire [XLEN-1:0] wdata,
    input wire we2,
    input wire [4:0] waddr2,
    input wire [XLEN-1:0] wdata2,
    input wire [4:0] raddr1,
    output wire [XLEN-1:0] rraw1,
    output wire [XLEN-1:0] rdata1,
    input wire [4:0] raddr2,
    output wire [XLEN-1:0] rraw2,
    output wire [XLEN-1:0] rdata2,
    input wire [4:0] raddr3,
    output wire [XLEN-1:0] rdata3
);
    reg [XLEN-1:0] regs [0:31];
    integer i;

    assign rraw1 = (raddr1 == 5'd0) ? {XLEN{1'b0}} : regs[raddr1];
    assign rraw2 = (raddr2 == 5'd0) ? {XLEN{1'b0}} : regs[raddr2];
    assign rdata1 = (raddr1 == 5'd0) ? {XLEN{1'b0}} :
                    (we && (waddr == raddr1) && (waddr != 5'd0)) ? wdata :
                    (we2 && (waddr2 == raddr1) && (waddr2 != 5'd0)) ? wdata2 :
                    rraw1;
    assign rdata2 = (raddr2 == 5'd0) ? {XLEN{1'b0}} :
                    (we && (waddr == raddr2) && (waddr != 5'd0)) ? wdata :
                    (we2 && (waddr2 == raddr2) && (waddr2 != 5'd0)) ? wdata2 :
                    rraw2;
    assign rdata3 = (raddr3 == 5'd0) ? {XLEN{1'b0}} :
                    (we && (waddr == raddr3) && (waddr != 5'd0)) ? wdata :
                    (we2 && (waddr2 == raddr3) && (waddr2 != 5'd0)) ? wdata2 :
                    regs[raddr3];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= {XLEN{1'b0}};
            end
        end else begin
            if (we2 && (waddr2 != 5'd0)) begin
                regs[waddr2] <= wdata2;
            end
            if (we && (waddr != 5'd0)) begin
                regs[waddr] <= wdata;
            end
        end
    end
endmodule
