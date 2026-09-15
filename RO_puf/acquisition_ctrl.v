//=============================================================================
// acquisition_ctrl.v  (FIXED)
//
// Key change: SETTLE_CYCLES increased from 2000 to 5000.
//
// SETTLE_CYCLES controls how many sys_clk cycles the FSM waits after
// osc_enable goes low before sampling the counters. This gives:
//   - The ring oscillators time to fully stop (happens in <10 ns in practice)
//   - The RO-derived counter clocks (R0, R1) time to go idle
//   - The counter registers time to become static before the sys_clk
//     domain comparator reads them
//
// 5000 × 10 ns = 50 µs settle window — very conservative and safe.
// The rings stop within a few ns; the extra margin costs ~50 µs per
// challenge but eliminates any possibility of reading a mid-transition
// counter value.
//
// Total time per challenge with ACQ_CYCLES=5000, SETTLE_CYCLES=5000:
//   ~10,010 sys_clk cycles = ~100 µs per challenge
//   × 1,048,576 challenges ≈ 105 seconds total sweep time
//=============================================================================
`timescale 1ns/1ps

module acquisition_ctrl #(
    parameter integer CNT_WIDTH     = 32,
    parameter integer SETTLE_CYCLES = 5000    // FIXED: was 8, then 2000, now 5000
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  start,
    input  wire [CNT_WIDTH-1:0]  acq_cycles,
    output reg                   osc_enable,
    output reg                   sample,
    output reg                   busy,
    output reg                   valid
);

    localparam IDLE   = 2'd0,
               RUN    = 2'd1,
               SETTLE = 2'd2,
               DONE   = 2'd3;

    reg [1:0]            state;
    reg [CNT_WIDTH-1:0]  cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            osc_enable <= 1'b0;
            sample     <= 1'b0;
            busy       <= 1'b0;
            valid      <= 1'b0;
            cnt        <= {CNT_WIDTH{1'b0}};
        end else begin
            sample <= 1'b0;
            valid  <= 1'b0;

            case (state)
                IDLE: begin
                    osc_enable <= 1'b0;
                    busy       <= 1'b0;
                    if (start) begin
                        cnt        <= {CNT_WIDTH{1'b0}};
                        osc_enable <= 1'b1;
                        busy       <= 1'b1;
                        state      <= RUN;
                    end
                end

                RUN: begin
                    if (cnt >= acq_cycles) begin
                        osc_enable <= 1'b0;
                        cnt        <= {CNT_WIDTH{1'b0}};
                        state      <= SETTLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                SETTLE: begin
                    if (cnt >= SETTLE_CYCLES) begin
                        sample <= 1'b1;
                        state  <= DONE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                DONE: begin
                    busy  <= 1'b0;
                    valid <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
