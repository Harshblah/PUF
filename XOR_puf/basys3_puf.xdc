## basys3_puf.xdc
##
## Lessons-learned applied:
##   #3 - property name is ALLOW_COMBINATORIAL_LOOPS (COMBINATORIAL,
##        not COMBINATIONAL). Verify against your installed Vivado
##        version's own documentation before trusting this file.
##   #4 - no foreach/if/for. Every line is a direct Vivado command.
##
## After implementation, open the Messages tab (not just this file)
## and confirm every constraint below was actually applied to a real
## net/cell -- a misspelled or non-matching wildcard can be silently
## dropped rather than erroring.

# Clock signal (100 MHz)
set_property PACKAGE_PIN W5 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# Reset (center pushbutton, U18)
set_property PACKAGE_PIN U18 [get_ports rst]
set_property IOSTANDARD LVCMOS33 [get_ports rst]

# USB-UART bridge
set_property PACKAGE_PIN B18 [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]
set_property PACKAGE_PIN A18 [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]

# ---- XOR-PUF cross-coupled cells ----
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical *o1*]
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -hierarchical *o2*]
set_property DONT_TOUCH true [get_cells -hierarchical *u_gate1*]
set_property DONT_TOUCH true [get_cells -hierarchical *u_gate2*]

# Timing false paths
set_false_path -through [get_nets -hierarchical *o1*]
set_false_path -through [get_nets -hierarchical *o2*]

# These wildcard patterns depend on the real synthesized hierarchy
# names, which shift between Vivado versions and generate-block
# naming conventions. After synthesis, open the Device/Schematic view,
# find the ACTUAL hierarchical names for a few u_cell instances, and
# confirm (or replace) these patterns -- don't assume a wildcard match
# just because Vivado didn't throw an error.

# The race inside each cell resolves in a few gate delays, entirely
# asynchronous to sys_clk -- treat it as a false path rather than
# trying to close timing across it.
set_false_path -through [get_nets -hierarchical *u_cell*o1*]
set_false_path -through [get_nets -hierarchical *u_cell*o2*]

# Lock relative gate positions inside each paired SLICE for symmetry
set_property BEL A6LUT [get_cells -hierarchical *u_gate1*]
set_property BEL B6LUT [get_cells -hierarchical *u_gate2*]

# ---- Placement symmetry (READ THIS BEFORE YOU TRUST YOUR RESULTS) ----
# This PUF's entropy comes from the physical delay mismatch between
# each cell's two branches. If the placer routes one branch's LUT3
# noticeably further than the other's -- for EVERY cell, on EVERY
# chip, the same way -- your "PUF" will just reproduce that fixed
# tool bias instead of real silicon variation, and uniqueness across
# boards will fail even though reliability looks perfect on one board.
#
# A full RLOC/RPM (Relationally Placed Macro) constraint set that
# guarantees matched placement is beyond what can be hand-written
# blind here -- the exact syntax and legal RLOC values are device- and
# Vivado-version-specific (see UG903, "Relative Location Constraints").
# Before you trust any uniqueness result:
#   1. After implementation, open Device view and manually inspect
#      where a handful of u_cell instances actually landed.
#   2. If the two LUT3s of a cell are far apart or inconsistently
#      routed, add explicit RLOC constraints (or a Pblock) to force
#      them adjacent, and re-check.
#   3. Do this BEFORE running an inter-chip uniqueness comparison --
#      an uncontrolled placement is a plausible root cause if your
#      Hamming distance numbers look suspiciously close to 0% or 100%
#      instead of near 50%.
