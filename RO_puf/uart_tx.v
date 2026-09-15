//=============================================================================
// uart_tx.v
//
// 8N1 UART transmitter.  Sends one byte at a time.
//
// Frame format (10 bit-periods per byte):
//   [start=0] [D0] [D1] [D2] [D3] [D4] [D5] [D6] [D7] [stop=1]
//
// Default: 921600 baud @ 100 MHz  → 108 clock cycles per bit
// Change BAUD_RATE to 115200 if your USB-UART cable doesn't support 921600.
//
// Usage:
//   1. Put byte in tx_data, assert tx_send for exactly ONE clock cycle.
//   2. tx_busy goes high the following cycle and stays high until the
//      stop bit period is complete (~1090 cycles @ 921600).
//   3. Never assert tx_send while tx_busy is high.
//=============================================================================
`timescale 1ns/1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 100_000_000,
    parameter integer BAUD_RATE = 921_600
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] tx_data,   // byte to transmit
    input  wire       tx_send,   // 1-cycle strobe: start transmission
    output reg        tx,        // serial output (idle = 1)
    output reg        tx_busy    // 1 while transmitting
);

    // Number of system-clock cycles per UART bit period.
    // 100 MHz / 921600 = 108.5 → 108 (0.46% error, well within UART tolerance)
    localparam integer CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    reg [15:0] clk_cnt;   // counts 0 … CLKS_PER_BIT-1 within each bit period
    reg [3:0]  bit_cnt;   // counts 0 … 9 (start + 8 data + stop)
    reg [7:0]  data_latch;// holds byte being transmitted

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
            clk_cnt   <= 16'd0;
            bit_cnt   <= 4'd0;
            data_latch<= 8'h00;
        end

        // ── IDLE ──────────────────────────────────────────────────────────
        else if (!tx_busy) begin
            tx <= 1'b1;   // hold line high (idle)
            if (tx_send) begin
                data_latch <= tx_data;
                tx         <= 1'b0;   // assert start bit immediately
                clk_cnt    <= 16'd0;
                bit_cnt    <= 4'd0;
                tx_busy    <= 1'b1;
            end
        end

        // ── TRANSMITTING ──────────────────────────────────────────────────
        else begin
            if (clk_cnt < CLKS_PER_BIT - 1) begin
                clk_cnt <= clk_cnt + 1;
            end else begin
                // End of current bit period
                clk_cnt <= 16'd0;

                if (bit_cnt == 4'd9) begin
                    // Stop bit just finished → back to idle
                    tx_busy <= 1'b0;
                    tx      <= 1'b1;
                end else begin
                    bit_cnt <= bit_cnt + 1;
                    // bit_cnt 0 = start (already driven)
                    // bit_cnt 1–8 = data bits 0–7
                    // bit_cnt 9 = stop
                    case (bit_cnt + 1)
                        4'd1:    tx <= data_latch[0];
                        4'd2:    tx <= data_latch[1];
                        4'd3:    tx <= data_latch[2];
                        4'd4:    tx <= data_latch[3];
                        4'd5:    tx <= data_latch[4];
                        4'd6:    tx <= data_latch[5];
                        4'd7:    tx <= data_latch[6];
                        4'd8:    tx <= data_latch[7];
                        4'd9:    tx <= 1'b1;   // stop bit
                        default: tx <= 1'b1;
                    endcase
                end
            end
        end
    end

endmodule
