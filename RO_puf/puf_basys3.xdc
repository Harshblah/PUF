## =============================================================================
## puf_basys3.xdc  –  Constraints for puf_uart_top on Basys3 (XC7A35T-1CPG236C)
##
## REPLACES: pdro_puf_basys3_example.xdc
## =============================================================================

## ── 100 MHz system clock ─────────────────────────────────────────────────────
set_property PACKAGE_PIN W5      [get_ports clk]
set_property IOSTANDARD  LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk -waveform {0 5} [get_ports clk]

## ── Reset: BTNC (centre button, active-high) ─────────────────────────────────
set_property PACKAGE_PIN U18     [get_ports rst]
set_property IOSTANDARD  LVCMOS33 [get_ports rst]

## ── Run: BTNU (up button) ────────────────────────────────────────────────────
set_property PACKAGE_PIN T18     [get_ports run]
set_property IOSTANDARD  LVCMOS33 [get_ports run]

## ── Status LEDs ──────────────────────────────────────────────────────────────
## LED[0] = done (all CRPs transmitted)
set_property PACKAGE_PIN U16     [get_ports done_led]
set_property IOSTANDARD  LVCMOS33 [get_ports done_led]

## LED[1] = busy (sweep in progress)
set_property PACKAGE_PIN E19     [get_ports busy_led]
set_property IOSTANDARD  LVCMOS33 [get_ports busy_led]

## ── USB-UART TX (FPGA → PC) ──────────────────────────────────────────────────
## Pin A18 is labeled "uart_rxd_out" in Digilent's master XDC, meaning
## "data going OUT from the FPGA to the USB-UART chip's RXD input".
## This is the FPGA's transmit line → correct pin for sending data to the PC.
##
## On Windows: open Device Manager → Ports → "USB Serial Port (COMx)" when
##             Basys3 is plugged in. Use that COMx in collect_crp.py.
## On Linux  : /dev/ttyUSB0 (or ttyUSB1). Check: ls /dev/ttyUSB*
set_property PACKAGE_PIN A18     [get_ports uart_tx_pin]
set_property IOSTANDARD  LVCMOS33 [get_ports uart_tx_pin]

## =============================================================================
## RO-PUF specific timing exceptions  (required for implementation)
## =============================================================================

## Allow the intentional combinational feedback loop inside ro_cell.
## Without this, Vivado aborts with DRC error LUTLP-1.
set_property ALLOW_COMBINATIONAL_LOOPS true \
    [get_nets -hierarchical -filter {NAME =~ *inv_chain*}]

## The oscillator-derived clocks (osc_clk_div2 inside every ro_cell, and
## the further-divided T0/R0/T1/R1 in pdro_puf_top) are free-running and
## asynchronous w.r.t. sys_clk.  Exclude all paths through them from
## static timing analysis so implementation does not error out.
set_false_path -through \
    [get_nets -hierarchical -filter {NAME =~ *u_puf*div2_q*}]
set_false_path -through \
    [get_nets -hierarchical -filter {NAME =~ *u_puf*osc_clk_div2*}]

## =============================================================================
## Synthesis / Implementation settings (set these in Vivado's GUI or tcl)
## =============================================================================
## In Vivado:
##   Settings → Synthesis   → More Options: -keep_equivalent_registers -no_lc
##   Settings → Implementation → opt_design Options: -directive Explore
##
## These prevent the synthesizer from merging or retiming the RO inverter chain.
