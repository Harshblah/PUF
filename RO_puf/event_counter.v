//=============================================================================
// event_counter.v  (FIXED)
//
// Key change: added `clear` port for per-challenge counter reset.
//
// WHY async clear is required here (not synchronous):
//   This counter is clocked by R0 or R1 — a ring-oscillator-derived clock
//   that STOPS when osc_enable goes low. A synchronous clear (on posedge clk)
//   would never fire because the clock is frozen. An asynchronous clear
//   (in the sensitivity list) fires regardless of the clock state.
//
// WHY it is safe here:
//   `clear` is driven by `start` from crp_engine. When `start` fires,
//   acquisition_ctrl is still in IDLE with osc_enable=0, so the ring
//   oscillators are already stopped and R0/R1 are not toggling. There
//   are no active clock edges to cause metastability.
//
// Sequence per challenge:
//   1. crp_engine pulses start=1 (1 sys_clk cycle)
//   2. clear=start=1 → counter resets to 0 asynchronously  ← NEW
//   3. Next cycle: start=0, osc_enable goes high, ring starts
//   4. Counter accumulates fresh counts for this challenge only
//   5. osc_enable goes low, SETTLE wait, comparator samples clean counters
//=============================================================================
`timescale 1ns/1ps

module event_counter #(
    parameter integer WIDTH = 16
) (
    input  wire               clk,        // RO-derived reference clock (R0 or R1)
    input  wire               rst,        // global reset (BTNC)
    input  wire               clear,      // NEW: per-challenge async clear (= start)
    input  wire               enable,     // acquisition window (= osc_enable)
    input  wire               event_in,   // phase detector output
    output reg  [WIDTH-1:0]   count
);

    always @(posedge clk or posedge rst or posedge clear) begin
        if (rst || clear)
            count <= {WIDTH{1'b0}};       // reset on global rst OR per-challenge clear
        else if (enable && event_in)
            count <= count + 1'b1;
    end

endmodule
