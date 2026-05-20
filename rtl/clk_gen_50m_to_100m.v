module clk_gen_50m_to_100m (
    input wire clk_50m,
    input wire rst,
    output wire clk_100m,
    output wire locked
);
`ifndef SYNTHESIS
    assign clk_100m = clk_50m;
    assign locked = !rst;
`else
    wire clkfb_mmcm;
    wire clkfb_buf;
    wire clkout0_mmcm;
    wire locked_mmcm;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(20.000),
        .CLKFBOUT_PHASE(0.000),
        .CLKIN1_PERIOD(20.000),
        .CLKOUT0_DIVIDE_F(10.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE(0.000),
        .CLKOUT1_DIVIDE(1),
        .CLKOUT1_DUTY_CYCLE(0.500),
        .CLKOUT1_PHASE(0.000),
        .CLKOUT2_DIVIDE(1),
        .CLKOUT2_DUTY_CYCLE(0.500),
        .CLKOUT2_PHASE(0.000),
        .CLKOUT3_DIVIDE(1),
        .CLKOUT3_DUTY_CYCLE(0.500),
        .CLKOUT3_PHASE(0.000),
        .CLKOUT4_DIVIDE(1),
        .CLKOUT4_DUTY_CYCLE(0.500),
        .CLKOUT4_PHASE(0.000),
        .CLKOUT5_DIVIDE(1),
        .CLKOUT5_DUTY_CYCLE(0.500),
        .CLKOUT5_PHASE(0.000),
        .CLKOUT6_DIVIDE(1),
        .CLKOUT6_DUTY_CYCLE(0.500),
        .CLKOUT6_PHASE(0.000),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKFBOUT(clkfb_mmcm),
        .CLKFBOUTB(),
        .CLKOUT0(clkout0_mmcm),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .LOCKED(locked_mmcm),
        .CLKFBIN(clkfb_buf),
        .CLKIN1(clk_50m),
        .PWRDWN(1'b0),
        .RST(rst)
    );

    BUFG u_clkfb_buf (
        .I(clkfb_mmcm),
        .O(clkfb_buf)
    );

    BUFG u_clkout0_buf (
        .I(clkout0_mmcm),
        .O(clk_100m)
    );

    assign locked = locked_mmcm;
`endif
endmodule
