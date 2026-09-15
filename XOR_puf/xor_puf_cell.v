`timescale 1ns / 1ps
//=====================================================================
// xor_puf_cell.v
//
// Gate-accurate reconstruction of the cross-coupled XOR-PUF primitive
// from Figure 3 of the paper (itself citing Della Sala, Bellizia,
// Scotti, "A Lightweight FPGA Compatible Weak-PUF Primitive Based on
// XOR Gates," IEEE TCAS-II, 2022).
//
// THE BUG IN THE PREVIOUS ("Gemini") VERSION, AND THE FIX
// ---------------------------------------------------------------
// The Della Sala paper is explicit that this exact primitive (two
// cross-coupled XOR gates) can be configured to behave as EITHER:
//   (a) a ring oscillator, or
//   (b) an SRAM cell (bistable latch)
// depending on how the two challenge inputs relate to each other.
//
// Algebraically, with output o1 = r_eval & (i1 ^ o2) and
// o2 = r_eval & (i2 ^ o1):
//   - if i1 != i2 (e.g. i2 = ~i1, which is what the previous version
//     wired), substituting gives o1 = NOT(o1) at r_eval=1 -- no fixed
//     point exists, so the loop free-runs forever. That's ring-
//     oscillator mode, and it is *why* nothing ever settled no matter
//     how large SETTLE_CYCLES was made.
//   - if i1 == i2 (this version: both tied to a constant EXCITE=1),
//     the equations reduce to o1 = NOT(o2), o2 = NOT(o1) -- a plain
//     cross-coupled inverter pair, i.e. an SR-latch / SRAM cell, with
//     exactly two valid steady states: (o1,o2) = (1,0) or (0,1).
//     Which one it lands on when r_eval transitions 0->1 is decided
//     by the physical delay mismatch between the two symmetric-in-
//     intent branches -- the actual PUF entropy source.
//
// Each branch collapses to a single LUT3 on Xilinx 7-series
// (O = (I0 XOR I1) AND I2), which is also why the paper can claim
// several PUF bits fit in one CLB.
//
// r_eval convention (matches the paper's own text and prior RTL):
//   0 = Clear/Reset  -> both outputs forced to 0, known state
//   1 = Evaluate      -> loop released, races to a random-per-chip,
//                        but per-chip REPRODUCIBLE, resting state
//=====================================================================
module xor_puf_cell (
    input  wire r_eval,
    output wire o1,
    output wire o2
);

    // O = (I0 ^ I1) & I2, with I0 tied to constant 1 (EXCITE).
    // INIT=8'h60 computed for addr={I2,I1,I0}: see README for the
    // truth table derivation.
    (* DONT_TOUCH = "TRUE", HLUTNM = "puf_pair" *)
    LUT3 #(.INIT(8'h60)) u_gate1 (
        .O (o1),
        .I0(1'b1),
        .I1(o2),
        .I2(r_eval)
    );

    (* DONT_TOUCH = "TRUE", HLUTNM = "puf_pair" *)
    LUT3 #(.INIT(8'h60)) u_gate2 (
        .O (o2),
        .I0(1'b1),
        .I1(o1),
        .I2(r_eval)
    );

endmodule
