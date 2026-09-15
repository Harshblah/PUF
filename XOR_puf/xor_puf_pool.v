`timescale 1ns / 1ps
//=====================================================================
// xor_puf_pool.v
//
// A pool of N independent xor_puf_cell instances, all gated by the
// same r_eval signal, sharing a single evaluate/clear cycle. Every
// cell resolves to a fixed, chip-specific bit each time it is
// released -- together they form a raw N-bit silicon fingerprint.
//
// Only o1 of each cell is used as the raw response bit; o2 is its
// logical complement in steady state and is left unconnected here.
// (You can wire it out too and use mismatches between o1 and NOT(o2)
// as a built-in "did this cell actually resolve cleanly" self-check
// if you want extra robustness -- see README.)
//
// On implementation (per lessons-learned):
//   Physical placement matters as much as logic correctness here.
//   Both LUT3s inside each xor_puf_cell should be placed as close
//   together and as symmetrically as the tool allows -- if Vivado's
//   default placer routes one branch through a noticeably longer path
//   than the other, EVERY cell on EVERY chip will settle to the same
//   biased state, which looks like a working PUF in isolation but
//   destroys inter-chip uniqueness. See basys3_puf.xdc for a
//   best-effort RLOC starting point -- verify actual placement in
//   Vivado's Device view after implementation, don't assume the
//   constraint took effect.
//=====================================================================
module xor_puf_pool #(
    parameter N = 128
)(
    input  wire         r_eval,
    output wire [N-1:0] resp_raw
);

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : gen_cell
            wire o2_unused;
            (* DONT_TOUCH = "true" *)
            xor_puf_cell u_cell (
                .r_eval (r_eval),
                .o1     (resp_raw[i]),
                .o2     (o2_unused)
            );
        end
    endgenerate

endmodule
