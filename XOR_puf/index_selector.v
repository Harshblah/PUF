`timescale 1ns / 1ps
//=====================================================================
// index_selector.v
//
// This is a weak PUF: each cell has a fixed, chip-specific resting
// value (that's the whole point -- it's what makes it reproducible,
// i.e. low Intra-HD). The raw pool by itself has no "challenge"
// dependence at all.
//
// To give the system an actual challenge-response surface (matching
// Figure 2 of the paper, where different challenges are expected to
// map to different stored responses), the 32-bit challenge selects
// WHICH pool cell fills each of the 64 response-bit positions. Same
// challenge -> same selection -> same 64-bit response every time
// (good reliability). Different challenges -> different subsets/
// orderings of the same underlying fixed fingerprint -> different
// apparent responses.
//
// Be upfront with yourself about the security model this gives you:
// the entropy source is still just N fixed bits (N = pool size), so
// the number of *independent* possible 64-bit responses is bounded by
// how many distinct index-subsets you can select, not by 2^64. This
// matches how "weak PUFs" are actually used in practice (device
// fingerprinting / key derivation with a limited, enrolled CRP set),
// not a "strong PUF" with an exponential CRP space. Enroll and store
// only as many CRPs as you actually intend to use.
//=====================================================================
module index_selector #(
    parameter POOL_W = 7   // pool size = 2**POOL_W
)(
    input  wire [31:0]        challenge,
    input  wire [5:0]         bit_index,   // 0..63
    output wire [POOL_W-1:0]  index
);

    // Simple, auditable diffusion -- not a cryptographic hash.
    // Truncation to POOL_W bits on assignment gives the mod-2^POOL_W
    // wraparound for free.
    assign index = (challenge[POOL_W-1:0] + bit_index)
                   ^ challenge[POOL_W+6:7];

endmodule
