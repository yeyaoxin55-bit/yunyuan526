###############################################################################
# tinyriscv_huoyue_uart.xdc
# Board : Wildfire Xilinx ZYNQ-7000 Huoyue
# Device: xc7z020clg400 / xa7z020clg400
# Usage : TinyRISC-V UART board bring-up
###############################################################################

###############################################################################
# 50 MHz PL clock
###############################################################################
set_property PACKAGE_PIN N18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]

###############################################################################
# PL keys
###############################################################################
set_property PACKAGE_PIN G19 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

set_property PACKAGE_PIN G20 [get_ports uart_debug_key_n]
set_property IOSTANDARD LVCMOS33 [get_ports uart_debug_key_n]

###############################################################################
# USB-to-UART
###############################################################################
set_property PACKAGE_PIN B20 [get_ports uart_rx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_pin]

set_property PACKAGE_PIN C20 [get_ports uart_tx_pin]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx_pin]

###############################################################################
# Status LEDs
###############################################################################
set_property PACKAGE_PIN K16 [get_ports over]
set_property IOSTANDARD LVCMOS33 [get_ports over]

set_property PACKAGE_PIN J16 [get_ports succ]
set_property IOSTANDARD LVCMOS33 [get_ports succ]

set_property PACKAGE_PIN K14 [get_ports halted_ind]
set_property IOSTANDARD LVCMOS33 [get_ports halted_ind]

