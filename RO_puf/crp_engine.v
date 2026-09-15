//=============================================================================
// crp_engine.v
//
// Automatically sweeps every 20-bit challenge (0 → 2^20 − 1 = 1,048,575),
// fires pdro_puf_top once per challenge, packs 8 response bits into one
// byte, and streams bytes to the UART TX module.
//
// Total data sent to PC
// ─────────────────────
//   4 header bytes  : 0xAA 0x55 0xAA 0x55  (sync / framing)
//   131,072 data bytes: 1,048,576 responses / 8 = 131,072 bytes
//   Total: 131,076 bytes → ~1.54 s at 921600 baud
//
// Bit packing inside each byte
// ─────────────────────────────
//   Byte index  i  covers challenges  8*i … 8*i+7.
//   Bit position b (0 = LSB) holds the response for challenge  8*i + b.
//   Python: challenge = byte_idx * 8 + bit_pos
//           response  = (byte >> bit_pos) & 1
//
// State machine
// ─────────────
//   IDLE    → wait for `run` pulse
//   S_HDR   → assert uart_send for current header byte
//   WS_HDR  → 1-cycle spin (lets uart_tx latch send and assert tx_busy)
//   W_HDR   → wait for !uart_busy; advance hdr_idx or move to EVAL
//   EVAL    → pulse puf_start
//   PEND    → wait for puf_valid from pdro_puf_top
//   PACK    → store response bit into bit_pack[challenge[2:0]]
//             if challenge[2:0]==7 → S_DATA (byte complete)
//             else                 → NEXT
//   S_DATA  → assert uart_send for packed data byte
//   WS_DATA → 1-cycle spin
//   W_DATA  → wait for !uart_busy, then → NEXT
//   NEXT    → advance challenge; loop or → DONE
//   DONE    → assert done, hold until reset
//
// Why the SPIN states?
// ────────────────────
//   uart_tx updates tx_busy one clock cycle after sampling tx_send.
//   Without a 1-cycle gap, the W_HDR/W_DATA states would see tx_busy=0
//   (stale) and exit immediately before the UART has started.
//   The WS_HDR / WS_DATA states consume that one cycle.
//=============================================================================
`timescale 1ns/1ps

module crp_engine #(
    parameter integer CHW       = 20,  // 4*SEL_BITS: 20 for N=32, SEL_BITS=5
    parameter integer ACQ_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  run,         // 1-cycle pulse: start sweep
    input  wire [ACQ_WIDTH-1:0]  acq_cycles,  // forwarded to pdro_puf_top

    // ── pdro_puf_top interface ────────────────────────────────────────────
    output reg  [CHW-1:0]        challenge,
    output reg                   puf_start,   // 1-cycle pulse
    input  wire                  puf_valid,   // 1-cycle pulse when response ready
    input  wire                  puf_response,// stable while valid and until next start

    // ── uart_tx interface ─────────────────────────────────────────────────
    output reg                   uart_send,   // 1-cycle strobe
    output reg  [7:0]            uart_byte,   // byte to send
    input  wire                  uart_busy,   // 1 while uart_tx is transmitting

    // ── status ───────────────────────────────────────────────────────────
    output reg                   busy,
    output reg                   done
);

    // ── State encoding ────────────────────────────────────────────────────
    localparam [3:0]
        IDLE    = 4'd0,
        S_HDR   = 4'd1,
        WS_HDR  = 4'd2,
        W_HDR   = 4'd3,
        EVAL    = 4'd4,
        PEND    = 4'd5,
        PACK    = 4'd6,
        S_DATA  = 4'd7,
        WS_DATA = 4'd8,
        W_DATA  = 4'd9,
        NEXT    = 4'd10,
        DONE    = 4'd11;

    reg [3:0] state;
    reg [7:0] bit_pack;   // accumulates 8 response bits before a UART send
    reg [1:0] hdr_idx;    // 0..3 indexes the 4 header bytes

    // ── Header byte ROM ───────────────────────────────────────────────────
    // 0xAA 0x55 0xAA 0x55 — Python looks for this to synchronise.
    function [7:0] hdr_byte;
        input [1:0] idx;
        case (idx)
            2'd0: hdr_byte = 8'hAA;
            2'd1: hdr_byte = 8'h55;
            2'd2: hdr_byte = 8'hAA;
            2'd3: hdr_byte = 8'h55;
            default: hdr_byte = 8'h00;
        endcase
    endfunction

    // ── Main FSM ──────────────────────────────────────────────────────────
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            challenge <= {CHW{1'b0}};
            puf_start <= 1'b0;
            uart_send <= 1'b0;
            uart_byte <= 8'h00;
            bit_pack  <= 8'h00;
            hdr_idx   <= 2'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            // Default: clear one-cycle strobes each cycle
            puf_start <= 1'b0;
            uart_send <= 1'b0;

            case (state)

                // ── Wait for user to press run ──────────────────────────
                IDLE: begin
                    done <= 1'b0;
                    busy <= 1'b0;
                    if (run) begin
                        challenge <= {CHW{1'b0}};
                        bit_pack  <= 8'h00;
                        hdr_idx   <= 2'd0;
                        busy      <= 1'b1;
                        state     <= S_HDR;
                    end
                end

                // ── Send one header byte ────────────────────────────────
                S_HDR: begin
                    uart_send <= 1'b1;
                    uart_byte <= hdr_byte(hdr_idx);
                    state     <= WS_HDR;
                end

                // 1-cycle spin: uart_tx is latching send, tx_busy will
                // assert at the end of THIS cycle (visible next cycle)
                WS_HDR: begin
                    state <= W_HDR;
                end

                W_HDR: begin
                    if (!uart_busy) begin
                        if (hdr_idx == 2'd3)
                            state <= EVAL;       // all 4 header bytes sent
                        else begin
                            hdr_idx <= hdr_idx + 1;
                            state   <= S_HDR;    // next header byte
                        end
                    end
                end

                // ── Fire the PUF for the current challenge ──────────────
                EVAL: begin
                    puf_start <= 1'b1;
                    state     <= PEND;
                end

                PEND: begin
                    if (puf_valid)
                        state <= PACK;
                end

                // ── Accumulate response bit ─────────────────────────────
                // puf_response is stable (held by pdro_puf_top's resp_reg)
                // from the puf_valid pulse until the next puf_start.
                PACK: begin
                    bit_pack[challenge[2:0]] <= puf_response;
                    //  ↑ NBC: resolved at end of this cycle, visible in S_DATA
                    if (challenge[2:0] == 3'b111)
                        state <= S_DATA;   // byte complete → send it
                    else
                        state <= NEXT;
                end

                // ── Send one packed data byte ───────────────────────────
                // bit_pack is fully updated here (NBC from PACK resolved).
                S_DATA: begin
                    uart_send <= 1'b1;
                    uart_byte <= bit_pack;   // all 8 bits, incl. [7] from PACK
                    bit_pack  <= 8'h00;      // clear accumulator
                    state     <= WS_DATA;
                end

                WS_DATA: begin
                    state <= W_DATA;
                end

                W_DATA: begin
                    if (!uart_busy)
                        state <= NEXT;
                end

                // ── Advance challenge counter ───────────────────────────
                NEXT: begin
                    if (challenge == {CHW{1'b1}}) begin
                        // Processed all 2^CHW challenges
                        state <= DONE;
                    end else begin
                        challenge <= challenge + 1'b1;
                        state     <= EVAL;
                    end
                end

                // ── Finished ────────────────────────────────────────────
                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    // Hold here until reset; re-run requires rst then run
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
