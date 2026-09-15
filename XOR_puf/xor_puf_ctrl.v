`timescale 1ns / 1ps
//=====================================================================
// xor_puf_ctrl.v
//
// One evaluation of the whole pool per challenge (not 64 sequential
// races like an RO-PUF would need) -- this primitive resolves in a
// handful of clock cycles, consistent with the paper's own claim of
// near-instantaneous (nanosecond-scale) response generation.
//
// Lessons-learned applied:
//   #1 / #6  Explicit clear before every evaluation:
//              -> S_CLEAR drives r_eval=0 for CLEAR_CYCLES before
//                 every single challenge, not just on global rst.
//                 "What is this element's value at the start of
//                 challenge N+1?" -> always a clean 0, guaranteed.
//   #2       Settle time:
//              -> S_EVAL holds r_eval=1 for SETTLE_CYCLES before
//                 anything is sampled, giving every cell's race time
//                 to resolve to a real steady state. This is a much
//                 shorter window than an RO-PUF needs (this is gate-
//                 delay-scale, not oscillator-period-scale) -- start
//                 small and only increase if hardware testing shows
//                 unresolved/metastable-looking bits.
//   #5       Don't tune parameters to hide a logic bug:
//              -> CLEAR_CYCLES and SETTLE_CYCLES are separate,
//                 independently tunable. If Intra-HD gets WORSE as
//                 you increase SETTLE_CYCLES, that's a sign something
//                 in CLEAR/placement is wrong, not a reason to keep
//                 increasing it.
//   #7       Simulation cannot validate this circuit:
//              -> in behavioural simulation, xor_puf_cell's two LUT3s
//                 have zero modeled propagation delay, so the "race"
//                 has no winner -- most simulators will just latch
//                 onto whatever the last blocking assignment happened
//                 to compute, deterministically, EVERY time. A clean
//                 simulation waveform proves the wrapper FSM/UART
//                 framing works. It proves NOTHING about whether the
//                 real silicon actually produces balanced, chip-
//                 unique bits. Only hardware measurement (Intra-HD
//                 first, per your own notes) can tell you that.
//=====================================================================
module xor_puf_ctrl #(
    parameter POOL_N        = 128,
    parameter RESP_WIDTH    = 64,
    parameter CLEAR_CYCLES  = 4,
    parameter SETTLE_CYCLES = 16
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    input  wire [31:0]            challenge,
    output reg                    busy,
    output reg                    resp_valid,
    output reg  [RESP_WIDTH-1:0]  response
);

    localparam POOL_W = $clog2(POOL_N);

    // ---------------- PUF pool ----------------
    reg               r_eval;
    wire [POOL_N-1:0] resp_raw;

    xor_puf_pool #(.N(POOL_N)) u_pool (
        .r_eval   (r_eval),
        .resp_raw (resp_raw)
    );

    // ---------------- challenge -> cell selection ----------------
    reg  [5:0]        bit_index;
    wire [POOL_W-1:0] idx;

    index_selector #(.POOL_W(POOL_W)) u_sel (
        .challenge (challenge),
        .bit_index (bit_index),
        .index     (idx)
    );

    // ---------------- FSM ----------------
    localparam S_IDLE   = 0,
               S_CLEAR  = 1,
               S_EVAL   = 2,
               S_SAMPLE = 3,
               S_DONE   = 4;

    reg [2:0] state;
    reg [7:0] wait_cnt;
    reg [RESP_WIDTH-1:0] resp_shift;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            resp_valid <= 1'b0;
            r_eval     <= 1'b0;
            bit_index  <= 6'd0;
            wait_cnt   <= 8'd0;
            response   <= {RESP_WIDTH{1'b0}};
            resp_shift <= {RESP_WIDTH{1'b0}};
        end else begin
            resp_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    r_eval <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        wait_cnt <= 8'd0;
                        state    <= S_CLEAR;
                    end
                end

                // Explicit, per-challenge clear of the WHOLE pool --
                // lesson #1/#6.
                S_CLEAR: begin
                    r_eval <= 1'b0;
                    if (wait_cnt < CLEAR_CYCLES - 1) begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end else begin
                        wait_cnt <= 8'd0;
                        r_eval   <= 1'b1;
                        state    <= S_EVAL;
                    end
                end

                // Let every cell's race resolve before sampling --
                // lesson #2.
                S_EVAL: begin
                    if (wait_cnt < SETTLE_CYCLES - 1) begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end else begin
                        bit_index  <= 6'd0;
                        resp_shift <= {RESP_WIDTH{1'b0}};
                        state      <= S_SAMPLE;
                    end
                end

                // Pool is already settled; walk the 64 selected
                // indices out, one per cycle.
                S_SAMPLE: begin
                    resp_shift <= {resp_shift[RESP_WIDTH-2:0], resp_raw[idx]};
                    if (bit_index == RESP_WIDTH - 1) begin
                        state <= S_DONE;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end

                S_DONE: begin
                    response   <= resp_shift;
                    r_eval     <= 1'b0;   // clear again once done with it
                    busy       <= 1'b0;
                    resp_valid <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
