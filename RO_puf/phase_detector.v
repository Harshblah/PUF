//=============================================================================
// phase_detector.v
//
// One phase-detection block (PD0 or PD1 in Fig. 1). Implements exactly
// the behaviour described in Section II / Fig. 2:
//
//   "If the target clock is detected as '1' at the rising edge of the
//    reference clock, the phase detection signal becomes active and the
//    corresponding counter is incremented."
//
// This is a single D flip-flop: D = target_clk, clock = ref_clk. Its
// output (pd_out) feeds an event_counter, which counts how many ref_clk
// cycles, during the acquisition window, saw the target clock high.
//=============================================================================
`timescale 1ns/1ps

module phase_detector (
    input  wire target_clk,
    input  wire ref_clk,
    input  wire rst,
    output reg  pd_out      // '1' => target sampled high at ref_clk's rising edge
);

    always @(posedge ref_clk or posedge rst) begin
        if (rst)
            pd_out <= 1'b0;
        else
            pd_out <= target_clk;
    end

endmodule
