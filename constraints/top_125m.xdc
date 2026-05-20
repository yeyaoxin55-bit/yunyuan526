create_clock -period 8.000 [get_ports clk]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk]
