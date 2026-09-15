## =============================================================================
## puf_basys3.xdc  (FIXED v2)
## Basys3 (XC7A35T-1CPG236C) constraints for puf_uart_top
## =============================================================================

## ── 100 MHz system clock ─────────────────────────────────────────────────────
set_property PACKAGE_PIN W5       [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk -waveform {0 5} [get_ports clk]

## ── Reset: BTNC (centre, active-high) ────────────────────────────────────────
set_property PACKAGE_PIN U18      [get_ports rst]
set_property IOSTANDARD  LVCMOS33 [get_ports rst]

## ── Run: BTNU (up button) ────────────────────────────────────────────────────
set_property PACKAGE_PIN T18      [get_ports run]
set_property IOSTANDARD  LVCMOS33 [get_ports run]

## ── LEDs ─────────────────────────────────────────────────────────────────────
set_property PACKAGE_PIN U16      [get_ports done_led]
set_property IOSTANDARD  LVCMOS33 [get_ports done_led]

set_property PACKAGE_PIN E19      [get_ports busy_led]
set_property IOSTANDARD  LVCMOS33 [get_ports busy_led]

## ── USB-UART TX (FPGA → PC) ──────────────────────────────────────────────────
set_property PACKAGE_PIN A18      [get_ports uart_tx_pin]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx_pin]

## =============================================================================
## RO-PUF combinatorial loop acknowledgement
## =============================================================================
## XDC does NOT support Tcl foreach/if/for loops — only direct commands.
## set_property accepts a LIST of nets from get_nets, so one line handles
## all 64 RO cell loops (32 per block × 2 blocks) at once.
##
## Property name must be ALLOW_COMBINATORIAL_LOOPS (ORIAL, not ONAL).
## Vivado's own DRC LUTLP-1 message confirms this exact spelling.

set_property ALLOW_COMBINATORIAL_LOOPS TRUE \
    [get_nets -hierarchical -filter {NAME =~ *u_ro_cell*inv_chain*}]

