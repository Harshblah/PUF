# 64-bit XOR-PUF (paper-accurate) + UART for Basys 3

## What was wrong with the previous ("Gemini") version, precisely

The paper's own citation for this circuit -- Della Sala, Bellizia, Scotti,
*"A Lightweight FPGA Compatible Weak-PUF Primitive Based on XOR Gates,"*
IEEE TCAS-II, 2022 -- states that the cross-coupled XOR pair can be
configured to behave as **either a ring oscillator or an SRAM cell**,
depending on how the two challenge inputs relate.

With `o1 = r_eval & (i1 ^ o2)` and `o2 = r_eval & (i2 ^ o1)`:

- If `i1 != i2` (the previous version wired `i2 = ~challenge[i]`,
  `i1 = challenge[i]` -- always unequal), the equations reduce to
  `o1 = NOT(o1)` once evaluating. No fixed point exists. The loop free-runs
  forever, on every input, on every cell. That's ring-oscillator mode, and
  it's why no `SETTLE_CYCLES` value could ever have fixed it.
- If `i1 == i2` (this version: both tied to a fixed `1`), the equations
  reduce to `o1 = NOT(o2)`, `o2 = NOT(o1)` -- a plain cross-coupled
  inverter pair. That's an SR-latch / SRAM cell: exactly two valid steady
  states, and which one it lands on is decided by real physical delay
  mismatch between the two branches. That's the actual PUF.

## Module map

| File | Role |
|---|---|
| `xor_puf_cell.v` | One bistable cross-coupled XOR-PUF cell (2× LUT3) |
| `xor_puf_pool.v` | Pool of 128 cells -> raw per-chip fingerprint |
| `index_selector.v` | Challenge picks which pool cell fills each response bit |
| `xor_puf_ctrl.v` | FSM: clear pool → evaluate → sample 64 selected bits |
| `uart_rx.v` / `uart_tx.v` | Standard 8-N-1 UART, 115200 baud @ 100 MHz |
| `puf_uart_top.v` | Top level: 4-byte challenge in, 8-byte response out |
| `basys3_puf.xdc` | Pins + PUF-loop constraints |
| `pc_crp_logger.py` | PC-side script to log CRPs and check Intra-HD |

## Be honest with yourself about what this circuit is

This is a **weak PUF**: each of the 128 cells has one fixed, chip-specific
resting value. That's what gives you good reliability (low Intra-HD) --
but it also means the "challenge" doesn't change the underlying physics of
any single race. `index_selector.v` gives you a genuine challenge-response
*interface* (different challenges → different 64-bit outputs, reproducibly)
by selecting which subset/ordering of the 128 fixed bits gets returned —
but the entropy source is still only 128 fixed bits, not an exponential
challenge space. That matches how weak PUFs are actually used in practice
(fingerprinting / key derivation against an enrolled CRP set), but don't
oversell it as a strong PUF resistant to an attacker who can query it
enough times to characterize the whole pool.

## Resource estimate (128-cell pool)

- 128 cells × 2 LUT3 = 256 LUTs for the pool
- Index selector, FSM, response register: well under 100 LUTs/FFs
- UART: ~100–150 LUTs
- **Total: roughly 400–500 LUTs** — about 2–3% of the XC7A35T's 20,800
  LUTs. No overflow risk, even before considering that a real design would
  never need the whole pool active outside a measurement window.

## Before you build

1. **Simulation cannot validate this circuit.** Both LUT3s in
   `xor_puf_cell` have zero modeled delay in behavioural sim, so there's
   no real "race" — most simulators will just deterministically settle on
   whatever the evaluation order happens to compute, the same way every
   time. A clean simulation proves the FSM/UART wrapper works. It proves
   nothing about whether real silicon produces balanced, chip-unique bits.
2. **Verify `ALLOW_COMBINATORIAL_LOOPS` against your installed Vivado
   version's docs** before trusting the XDC — this exact property is what
   held up the original build via a typo.
3. **Placement symmetry is not optional here** — read the comment block
   at the bottom of `basys3_puf.xdc` before you trust any uniqueness
   number. An uncontrolled placer can bias every cell on every chip the
   same way, which looks fine on one board and fails completely on a
   second board.
4. **Run Intra-HD first**, on repeated challenges, before trusting
   uniformity or uniqueness — use `pc_crp_logger.py --repeats N`.
5. Start with `SETTLE_CYCLES=16` and only raise it if hardware testing
   shows unresolved bits — if raising it makes reliability *worse*,
   that's a sign of a placement/clear bug, not a reason to keep raising it
   (lesson #5 from your notes).
