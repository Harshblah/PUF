//=============================================================================
// puf_uart_top.v  (FIXED)
//
// Key change: ACQ_CYCLES increased from 750 to 5000 (50 µs @ 100 MHz).
//
// With the counter clear bug now fixed in event_counter.v, each challenge
// starts with counters at zero. At ~37.5 MHz effective reference clock
// (ring ~300 MHz ÷2 ÷4), 50 µs gives:
//   ~37.5 MHz × 50 µs × 50% duty ≈ ~937 counts per counter
//
// A count value of ~937 means closely-matched oscillator pairs
// differ by more counts than thermal/noise jitter, giving a stable
// comparison result. This is why longer acquisition reduces Intra-HD.
//
// Sweep time estimate:
//   (ACQ_CYCLES=5000 + SETTLE_CYCLES=5000 + overhead) × 1,048,576
//   ≈ 10,010 cycles × 1,048,576 ≈ 105 seconds total
//   (down from ~10 seconds before — acceptable for one-time enrollment)
//=============================================================================
`timescale 1ns/1ps

module puf_uart_top #(
    parameter integer N          = 32,
    parameter integer SEL_BITS   = 5,
    parameter integer NUM_INV    = 5,
    parameter integer DIV_STAGES = 2,
    parameter integer CNT_WIDTH  = 16,

    parameter integer ACQ_CYCLES = 5000,   // FIXED: was 750 (7.5µs), now 5000 (50µs)

    parameter integer CLK_FREQ   = 100_000_000,
    parameter integer BAUD_RATE  = 921_600,
    parameter integer CHW        = 4 * SEL_BITS   // 20
) (
    input  wire clk,
    input  wire rst,
    input  wire run,
    output wire done_led,
    output wire busy_led,
    output wire uart_tx_pin
);

    wire [CHW-1:0] challenge;
    wire           puf_start, puf_valid, puf_response, puf_busy;
    wire           uart_send, uart_busy;
    wire [7:0]     uart_byte;

    crp_engine #(
        .CHW      (CHW),
        .ACQ_WIDTH(32)
    ) u_engine (
        .clk         (clk),
        .rst         (rst),
        .run         (run),
        .acq_cycles  (32'd5000),       // matches ACQ_CYCLES above
        .challenge   (challenge),
        .puf_start   (puf_start),
        .puf_valid   (puf_valid),
        .puf_response(puf_response),
        .uart_send   (uart_send),
        .uart_byte   (uart_byte),
        .uart_busy   (uart_busy),
        .busy        (busy_led),
        .done        (done_led)
    );

    pdro_puf_top #(
        .N         (N),
        .SEL_BITS  (SEL_BITS),
        .NUM_INV   (NUM_INV),
        .DIV_STAGES(DIV_STAGES),
        .CNT_WIDTH (CNT_WIDTH),
        .ACQ_WIDTH (32)
    ) u_puf (
        .clk       (clk),
        .rst       (rst),
        .start     (puf_start),
        .challenge (challenge),
        .acq_cycles(32'd5000),         // matches ACQ_CYCLES above
        .response  (puf_response),
        .valid     (puf_valid),
        .busy      (puf_busy)
    );

    uart_tx #(
        .CLK_FREQ (CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart (
        .clk    (clk),
        .rst    (rst),
        .tx_data(uart_byte),
        .tx_send(uart_send),
        .tx     (uart_tx_pin),
        .tx_busy(uart_busy)
    );

endmodule
