//=============================================================================
// ro_cell.v
//
// Basic Ring-Oscillator (RO) cell, as described in Fig. 1 / Section II of
// "Implementing a phase detection ring oscillator PUF on FPGA" (Lee et al.,
// ICTC 2018):
//
//   "The primitive RO cell consists of one flip-flop, one AND gate and odd
//    numbers of inverter cells."
//
// Structure:
//
//   enable ---\
//              AND ---> [inv_0]->[inv_1]->...->[inv_{NUM_INV-1}] ---+
//              ^                                                    |
//              +----------------------------------------------------+
//                                                  |
//                                          (oscillating node)
//                                                  |
//                                            toggle flip-flop  -> osc_clk_div2
//
// NOTE ON SYNTHESIS (important, read before building for hardware):
//   A free-running ring oscillator is, electrically, a combinational
//   feedback loop. Synthesis/implementation tools normally assume
//   combinational logic is loop-free and will either refuse to close
//   timing on this net or silently optimize/retime the loop away,
//   destroying the very physical randomness the PUF depends on.
//
//   To stop that from happening on Xilinx 7-series parts (Basys3 = Artix-7
//   XC7A35T):
//     1. Every inverter/AND stage below is instantiated as an explicit
//        UNISIM primitive (LUT1 / LUT2) with DONT_TOUCH / KEEP, so the
//        synthesizer cannot merge, retime, or remove any stage.
//     2. You still need a companion XDC constraint
//        (ALLOW_COMBINATIONAL_LOOPS / false-path, see
//        constraints/pdro_puf_basys3_example.xdc) or Vivado will error
//        out at implementation.
//     3. For real PUF *quality* (not just "it synthesizes"), every RO
//        cell instance should additionally be floorplanned into matching
//        slices (LOC/RLOC) so all 64 oscillators see near-identical
//        routing. That placement step is implementer-specific and is
//        only sketched in the example XDC.
//
//   This module targets Xilinx UNISIM primitives (LUT1/LUT2). If you are
//   on a different vendor's FPGA, replace the LUT1/LUT2 instances with
//   that vendor's equivalent primitives plus its own "keep this net /
//   allow this loop" attributes.
//=============================================================================
`timescale 1ns/1ps

(* DONT_TOUCH = "true" *)
module ro_cell #(
    parameter integer NUM_INV = 5   // odd number of inverter stages (paper uses 5)
) (
    input  wire enable,        // osc_enable: gates the ring on/off
    input  wire rst,
    output wire osc_clk_div2   // divide-by-2'd oscillator output ("osc_clock/2" in Fig. 1)
);

    // inv_chain[0]            = output of the AND gate (ring input)
    // inv_chain[NUM_INV]      = output of the last inverter (the raw oscillating node)
    (* DONT_TOUCH = "true" *) wire [NUM_INV:0] inv_chain;
    (* DONT_TOUCH = "true" *) wire gated;

    // ---- AND gate: enable & feedback from the last inverter ----
    (* DONT_TOUCH = "true" *)
    LUT2 #(.INIT(4'h8)) u_and_gate (   // INIT=8 => O = I0 & I1
        .O (gated),
        .I0(enable),
        .I1(inv_chain[NUM_INV])
    );

    assign inv_chain[0] = gated;

    // ---- odd number of inverter stages forming the ring ----
    genvar i;
    generate
        for (i = 0; i < NUM_INV; i = i + 1) begin : INV_STAGE
            (* DONT_TOUCH = "true", KEEP = "true" *)
            LUT1 #(.INIT(2'b01)) u_inv (  // INIT=01 => O = ~I0
                .O (inv_chain[i+1]),
                .I0(inv_chain[i])
            );
        end
    endgenerate

    // ---- divide-by-2 toggle flip-flop ----
    // This is the "one flip-flop" in the paper's cell description. It both
    // squares up the duty cycle and halves the raw ring frequency, giving
    // osc_clock/2 as shown in Fig. 1. Note that this flip-flop is clocked
    // by a free-running, combinationally-generated (and therefore
    // asynchronous / not statically timeable) signal -- this is expected
    // and normal for RO-PUF designs, but downstream logic that consumes
    // osc_clk_div2 must be treated as a separate, uncharacterized clock
    // domain (see phase_detector.v / event_counter.v).
    reg div2_q;
    always @(posedge inv_chain[NUM_INV] or posedge rst) begin
        if (rst)
            div2_q <= 1'b0;
        else
            div2_q <= ~div2_q;
    end

    assign osc_clk_div2 = div2_q;

endmodule
