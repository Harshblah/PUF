# Phase Detection Ring Oscillator PUF (PDRO PUF) — Verilog implementation

RTL implementation of the architecture in Fig. 1 of:
S. Lee, M.-K. Oh, Y. Kang, D. Choi, *"Implementing a phase detection ring
oscillator PUF on FPGA,"* ICTC 2018.

## File map

```
rtl/
  ro_cell.v           Basic RO cell: 1 flip-flop + 1 AND gate + 5 inverters
  ro_block.v          One RO BLOCK (32 ro_cells) + target/ref select muxes
  clk_divider.v        Cascaded /2 dividers (the extra /2,/4 stages in Fig. 2)
  phase_detector.v     PD0 / PD1: samples target_clk at ref_clk's rising edge
  event_counter.v      Counter 0 / Counter 1
  acquisition_ctrl.v   FSM: runs the acquisition window, then samples
  pdro_puf_top.v       Top level: wires two ro_blocks into PD0/PD1 + compare
constraints/
  pdro_puf_basys3_example.xdc   Illustrative Basys3 constraints (see caveats below)
sim/
  tb_pdro_puf_top.v    Testbench for the digital backend (see note inside)
```

## Paper -> RTL mapping

| Paper element | RTL |
|---|---|
| Basic RO cell (1 FF + 1 AND + odd inverters) | `ro_cell.v` |
| BLOCK 0 / BLOCK 1 (n identical RO cells) | `ro_block.v`, instantiated twice in `pdro_puf_top.v` |
| Mux0..Mux3 / Target_sel0,1 / Ref_sel0,1 | `target_sel` / `ref_sel` ports of `ro_block.v` |
| /2, /4 stages before phase detection (Fig. 2) | `clk_divider.v` |
| PD0, PD1 | `phase_detector.v` (instantiated twice) |
| Counter 0, Counter 1 (16-bit) | `event_counter.v` (instantiated twice) |
| Final comparator -> 1-bit response | `resp_reg` logic in `pdro_puf_top.v` |
| Acquisition time sweep (5–20us, Table I) | `acq_cycles` input to `pdro_puf_top.v` |

Default parameters reproduce the Section III build: `N=32` cells/block (64
total), `NUM_INV=5`, 16-bit counters.

### Challenge format (20 bits, N=32)

```
challenge[ 4: 0] = target_sel0   -> BLOCK0's "target" cell
challenge[ 9: 5] = ref_sel0      -> BLOCK0's "reference" cell
challenge[14:10] = target_sel1   -> BLOCK1's "target" cell
challenge[19:15] = ref_sel1      -> BLOCK1's "reference" cell
```

Cross-wiring (matches the paper's text exactly):
- **PD0**: Target = BLOCK0's target cell, Reference = BLOCK1's reference cell
- **PD1**: Target = BLOCK1's target cell, Reference = BLOCK0's reference cell
- `response = (counter0 > counter1)`

With `N=32`, this gives `32^4 = 1,048,576` CRPs, matching the paper's "about
1 million different challenge-response pairs," versus `C(64,2)=2016` for a
classical RO PUF built from the same 64 cells.

## Basys3 resource fit

| Resource | Estimated use | Basys3 (XC7A35T) budget | Utilization |
|---|---|---|---|
| LUTs | ~500 | 20,800 | ~2.4% |
| Flip-flops | ~150 | 41,600 | ~0.4% |

Comfortably fits with large margin. **The constraint is not logic capacity —
it's getting a combinational feedback loop (the ring) through synthesis
correctly, and physically matching the placement of all 64 oscillators.**

## Implementation notes / what's still implementer-specific

1. **Combinational loops.** Each `ro_cell` is an intentional combinational
   feedback loop. `ro_cell.v` uses explicit UNISIM `LUT1`/`LUT2` primitives
   with `DONT_TOUCH`/`KEEP` so Vivado can't optimize the loop away, but you
   still need `set_property ALLOW_COMBINATIONAL_LOOPS true` (or an
   equivalent false-path) in your XDC — see the example file — or
   implementation will error out.
2. **Asynchronous clocks.** Every RO cell's output, and the further-divided
   target/reference clocks, are free-running and not meant to be analyzed by
   static timing analysis. Declare them as asynchronous clock groups or
   false-path them, as sketched in the example XDC.
3. **Placement for PUF quality.** Resource fit is not the issue — *matching*
   physical placement of all 64 ring oscillators is. For real uniqueness/
   reliability numbers anywhere near Table I, you'd want a Tcl script that
   LOC/RLOC-places every `ro_cell` instance into a regular, symmetric grid.
   That's design-specific and intentionally left out here.
4. **Clock-domain crossing.** `acquisition_ctrl.v` drives `osc_enable`
   (system-clock domain) into the RO/reference-clock domains, and the two
   asynchronous 16-bit counters are read back by the system-clock domain
   comparator. A `SETTLE` state adds margin before sampling, which is
   adequate for a lab/demo build; for a hardened design add explicit 2-FF
   synchronizers on `osc_enable` and on the counter outputs.
5. **Simulation.** `ro_cell.v`'s feedback loop has zero modeled delay in
   plain RTL simulation, so it won't oscillate outside of a timing-annotated
   Vivado simulation (or hardware). `sim/tb_pdro_puf_top.v` instead exercises
   the digital backend (`phase_detector`, `event_counter`,
   `acquisition_ctrl`, and the comparator) using two behavioral clocks with
   slightly different periods as oscillator stand-ins — this has been run
   with Icarus Verilog and produces sensible diverging counts and a stable
   response bit. Validate the actual ring behaviour with a Vivado
   post-implementation timing simulation or on hardware.

## Example usage

```verilog
pdro_puf_top #(
    .N(32), .SEL_BITS(5), .NUM_INV(5), .DIV_STAGES(2), .CNT_WIDTH(16)
) u_puf (
    .clk        (sys_clk_100mhz),
    .rst        (rst),
    .start      (start_pulse),
    .challenge  (challenge_20b),
    .acq_cycles (32'd750),     // 7.5us @ 100MHz, matches Table I's best row
    .response   (puf_response),
    .valid      (puf_valid),
    .busy       (puf_busy)
);
```

Pulse `start` with a new `challenge` each time; wait for `valid`; read
`response`. Repeat across many challenges to build up a CRP database, exactly
as Section III's "10,000 random 20-bit challenges x 1,000 repetitions" test
methodology does.
